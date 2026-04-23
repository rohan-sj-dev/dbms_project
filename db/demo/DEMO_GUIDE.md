# VCS Demo – Detailed Walkthrough Guide

**File:** `db/demo/06_demo_walkthrough_pgadmin.sql`  
**Database:** `bank_versioning_demo` (isolated from the live banking app)  
**Setup:** Run `db/demo/00_setup_demo_db.ps1` before every demo run

---

## How the VCS System Works (Background)

The system implements Git-like versioning entirely inside PostgreSQL using three layers:

| Layer | Tables / Functions | Purpose |
|---|---|---|
| **Staging area** | `vcs_staged_change` | Every INSERT/UPDATE/DELETE is auto-captured here by a trigger |
| **Commit store** | `vcs_commit`, `vcs_change` | `vcs_commit()` moves staged changes into permanent history |
| **Metadata** | `vcs_repository`, `vcs_branch`, `vcs_config`, `vcs_tag` | Branch/table registry |

**The auto-staging trigger (`vcs_trigger_fn`)** is the key piece. After `vcs_init()` registers a table, every DML operation on that table fires `vcs_trigger_fn()`, which:
1. Reads the active branch from `vcs_config`
2. Serialises `OLD` and `NEW` rows to JSONB
3. For UPDATE, computes the diff (only changed column names are stored in `changed_columns`)
4. Inserts one row into `vcs_staged_change`

Nothing goes to permanent history until `vcs_commit()` is explicitly called.

---

## Step 0 — Database Setup

```powershell
powershell -ExecutionPolicy Bypass -File "db\demo\00_setup_demo_db.ps1"
```

**What happens:**
1. `DROP DATABASE IF EXISTS bank_versioning_demo` — destroys any previous demo state
2. `CREATE DATABASE bank_versioning_demo` — fresh empty database
3. Runs `db/00_install_all.sql` which sequentially executes:
   - `schema/retail_banking_setup_final.sql` — all 9 banking tables + seed data (6 customers, 7 accounts, 6 employees, 3 loans, etc.)
   - `vcs/01_vcs_schema.sql` — VCS metadata tables (`vcs_repository`, `vcs_branch`, `vcs_commit`, `vcs_change`, `vcs_staged_change`, `vcs_tag`, `vcs_config`, `vcs_commit_parent`)
   - `vcs/02_vcs_core_functions.sql` through `05_vcs_rollback_functions.sql` — all VCS stored functions
   - `functions/banking_layer.sql` + `functions/patch_functions.sql` — banking business logic functions
   - `schema/views.sql` — reporting views including `branch_summary`

**DB state after setup:** Clean seed data, no VCS tracking active, no triggers on banking tables.

---

## Step 1 — INIT & Snapshot (`git init` + `git commit -m "baseline"`)

```sql
SELECT vcs_init('branch');
SELECT vcs_init('department');
SELECT vcs_init('employee');
SELECT vcs_init('employee_hr_update');
SELECT vcs_init('customer');
SELECT vcs_init('account');
SELECT vcs_init('transaction');
SELECT vcs_init('fund_transfer');
SELECT vcs_init('loan');
```

**Function called:** `vcs_init(p_table_name)`

**What `vcs_init` does for each table:**
1. Checks the table exists in `information_schema.tables`
2. Auto-detects the primary key column from `information_schema.table_constraints`
3. Inserts a row into `vcs_repository` (table name + PK column)
4. Executes `CREATE TRIGGER vcs_track_<table> AFTER INSERT OR UPDATE OR DELETE ON <table> FOR EACH ROW EXECUTE FUNCTION vcs_trigger_fn()`

**After 9 calls:** 9 rows in `vcs_repository`, 9 live triggers on banking tables. Every subsequent DML on any of these tables will auto-stage changes.

---

```sql
SELECT vcs_snapshot_all('v1.0 baseline — Kottayam Branch initial state');
```

**Function called:** `vcs_snapshot_all(message)`

**What it does:**
- Iterates all tables in `vcs_repository`
- For each table, does a full `SELECT *` and inserts every row as an `INSERT` operation into `vcs_staged_change`
- Then calls `vcs_commit()` internally to move all those staged rows into `vcs_change` under one commit

**VCS state after snapshot:**
- 1 commit on `main` with `change_count` = total seed rows across all 9 tables
- `vcs_staged_change` is now empty (everything committed)

---

```sql
SELECT vcs_tag_create('v1.0', NULL, 'Production baseline — all seed data captured');
```

**Function called:** `vcs_tag_create(tag_name, commit_id, message)`

- `commit_id = NULL` means "tag HEAD of active branch"
- Inserts a row into `vcs_tag` pointing to the current HEAD commit
- This tag is later used by `vcs_time_travel()` and `vcs_reconstruct_at()` in Step 11

---

## Step 2 — Basic Commit (`git add` + `git commit`)

```sql
-- New customer Vivek Chandran is inserted via a DO block
-- using RETURNING to avoid hardcoded IDs
INSERT INTO customer (...) RETURNING customer_id INTO v_cust_id;
INSERT INTO account  (...) RETURNING account_id  INTO v_acct_id;
INSERT INTO transaction (...);
```

**Triggers fired automatically:**
- `vcs_track_customer` → stages 1 INSERT into `vcs_staged_change`
- `vcs_track_account` → stages 1 INSERT
- `vcs_track_transaction` → stages 1 INSERT

**3 rows now sit in `vcs_staged_change` (staged but not yet committed)**

```sql
SELECT table_name, operation, row_pk, changed_columns FROM vcs_status();
```

`vcs_status()` reads `vcs_staged_change` for the active branch — shows the 3 pending INSERTs.

```sql
SELECT vcs_commit('Onboarded new customer Vivek Chandran...', 'Priya Menon');
```

**Function called:** `vcs_commit(message, author)`

**What `vcs_commit` does:**
1. Creates a new row in `vcs_commit` (branch = `main`, message, author, timestamp, hash = `md5(message || now)`)
2. Moves all rows from `vcs_staged_change` → `vcs_change` (permanent record), linking them to the new commit
3. Sets `change_count` on the commit = number of rows moved
4. Clears `vcs_staged_change` for this branch

**VCS state:** 2 commits on `main` (baseline + onboarding)

---

## Step 3 — Branch (`git checkout -b feature/loan-restructure`)

```sql
SELECT vcs_branch_create(
    'feature/loan-restructure',
    'main',
    'Restructure Arjun Pillai home loan + approve Meena personal loan',
    TRUE   -- auto checkout
);
```

**Function called:** `vcs_branch_create(name, from_branch, description, checkout)`

**What it does:**
1. Records the current HEAD of `main` as the fork-point commit
2. Inserts into `vcs_branch` with `created_from_branch = 'main'`
3. Creates a "branch creation" commit on the new branch (so the branch has its own HEAD immediately)
4. Since `checkout = TRUE`: updates `vcs_config SET value = 'feature/loan-restructure' WHERE key = 'active_branch'`

**All subsequent DML triggers now tag staged changes with branch = `feature/loan-restructure`**

---

## Step 4 — Feature Work (on `feature/loan-restructure`)

### 4a — Approve Meena's personal loan

```sql
UPDATE loan SET application_status='disbursed', sanctioned_amount=300000, ... WHERE loan_id = 3;
INSERT INTO transaction (...);  -- disbursal credit
SELECT vcs_commit('Approved & disbursed personal loan for Meena Suresh...', 'Arun Kumar');
```

**Triggers fired:**
- `vcs_track_loan` → stages 1 UPDATE on `loan_id=3` (changed columns: `application_status`, `sanctioned_amount`, `disbursed_amount`, `interest_rate`, `tenure_months`, `emi_amount`, `disbursement_date`, `maturity_date`, `outstanding_principal`, `collateral_type`, `status`)
- `vcs_track_transaction` → stages 1 INSERT (disbursal transaction)

**Commit created on `feature/loan-restructure`**

### 4b — Restructure Arjun's home loan

```sql
UPDATE loan SET tenure_months=300, emi_amount=33150, interest_rate=8.25, ... WHERE loan_id = 1;
INSERT INTO fund_transfer (..., remarks='LOAN RESTRUCTURE MEMO: ...');
SELECT vcs_commit('Restructured home loan LOAN-1 for Arjun Pillai...', 'Arun Kumar');
```

**Triggers fired:**
- `vcs_track_loan` → stages 1 UPDATE on `loan_id=1` (changed: `tenure_months`, `emi_amount`, `interest_rate`)
- `vcs_track_fund_transfer` → stages 1 INSERT (internal memo record)

**Commit created on `feature/loan-restructure`**

**VCS state:** `main` has 2 commits, `feature/loan-restructure` has 3 commits (branch-creation + 2 feature commits)

---

## Step 5 — Parallel Work (on `main`)

```sql
SELECT vcs_checkout('main');
```

Updates `vcs_config SET value = 'main'`. All subsequent trigger-staged changes now belong to `main`.

### 5a — HR Update: Manoj Krishnan contract → permanent

```sql
INSERT INTO employee_hr_update (...);        -- audit record
UPDATE employee SET employment_type='permanent', salary=43000 WHERE emp_id=6;
SELECT vcs_commit('HR: Manoj Krishnan (EMP-6) converted...', 'Rajesh Nair');
```

**Triggers fired:**
- `vcs_track_employee_hr_update` → stages 1 INSERT
- `vcs_track_employee` → stages 1 UPDATE (changed: `employment_type`, `salary`)

### 5b — RBI interest rate update

```sql
UPDATE account SET interest_rate=4.00 WHERE account_type='savings' AND status='active';
SELECT vcs_commit('RBI policy update: savings account interest rate...', 'Rajesh Nair');
```

**Triggers fired:**
- `vcs_track_account` → stages N UPDATEs (one per active savings account), each with `changed_columns = ['interest_rate']`

### 5c — KYC expiry freeze

```sql
UPDATE customer SET kyc_status='expired', status='blocked' WHERE customer_id=5;
UPDATE account SET status='frozen' WHERE customer_id=5;
SELECT vcs_commit('Compliance: Rajan Varma (CUST-5) KYC expired...', 'Suresh Pillai');
```

**Triggers fired:**
- `vcs_track_customer` → 1 UPDATE (changed: `kyc_status`, `status`)
- `vcs_track_account` → 1 UPDATE (changed: `status`)

**VCS state:** `main` has 5 commits, `feature/loan-restructure` has 3 commits — both modified `loan_id=1`, which is the conflict.

---

## Step 6 — History, Diff & Blame

These are **read-only** queries — no DML, no triggers fire.

### `vcs_log_all(20)`
Reads `vcs_commit` joined with `vcs_branch`, returns all commits across all branches sorted by `committed_at`. Shows `is_merge` flag.

### `vcs_diff(from_commit_id, to_commit_id)`
Reads `vcs_change` for commits in the range `(from, to]` on the active branch. Returns the aggregated set of changed rows — useful for seeing what changed between the baseline snapshot (commit 2) and HEAD.

### `vcs_blame('loan', 'feature/loan-restructure')`
For each row in the `loan` table, finds the most recent commit on the given branch that touched that row. Returns `last_author`, `last_message`, `modified_at` — exactly like `git blame` per row.

### `vcs_row_history('loan', '1')`
Returns all `vcs_change` records for `table_name='loan'` and `row_pk='1'` across all commits, ordered chronologically. Shows the full mutation history of a single row.

### `vcs_diff_branch('feature/loan-restructure', 'main')`
Finds rows changed on one branch that are also changed on the other (potential conflicts), and rows changed only on one side — the full inter-branch diff.

---

## Step 7 — Tags

```sql
SELECT vcs_tag_create('v1.1-pre-merge', NULL, '...');   -- tags main HEAD
SELECT vcs_checkout('feature/loan-restructure');
SELECT vcs_tag_create('feature-loan-restructure-ready', NULL, '...');  -- tags feature HEAD
SELECT vcs_checkout('main');
```

Each `vcs_tag_create` inserts into `vcs_tag` with `commit_id = vcs_get_head_commit(active_branch)`. Tags are permanent labels on specific commit IDs — they do not move when new commits are added.

---

## Step 8 — Conflict Detection & Resolution

```sql
SELECT * FROM vcs_merge_conflicts('feature/loan-restructure', 'main');
```

**What it does:** Finds rows where both branches have changes since their common fork-point commit. Here it returns `loan_id=1` because:
- `feature/loan-restructure` updated `loan_id=1` (tenure, EMI, rate)
- `main` did not update `loan_id=1` after branching… but the conflict is detected because the feature branch diverged from the same baseline row

**Resolution:**

```sql
UPDATE loan SET tenure_months=300, emi_amount=33150, interest_rate=8.25 WHERE loan_id=1;
SELECT vcs_commit('Conflict resolution: align main loan-1 terms...', 'Rajesh Nair');
```

Both branches now agree on `loan_id=1`. Re-running `vcs_merge_conflicts()` returns 0 rows.

---

## Step 9 — Merge (`git merge feature/loan-restructure`)

```sql
SELECT vcs_merge(
    'feature/loan-restructure',
    'main',
    'Merge feature/loan-restructure: Meena loan approved + Arjun loan restructured'
);
```

**Function called:** `vcs_merge(source_branch, target_branch, message)`

**What it does:**
1. Gets all `vcs_change` records from the source branch that are not in the target
2. Creates a new merge commit on `target_branch` (with `is_merge = TRUE`)
3. Copies the source branch's changes into `vcs_change` under this merge commit
4. Inserts rows into `vcs_commit_parent` to record the two parent commits (preserving the DAG)

**VCS state after merge:** `main` has a merge commit. All feature branch changes are now visible in `vcs_log('main')` and `vcs_diff()`.

```sql
SELECT vcs_tag_create('v1.2', NULL, 'Post-merge: loan restructure and new customer fully integrated');
```

---

## Step 10 — Rollback (`git revert`)

### Simulate the mistake

```sql
UPDATE employee SET salary = 999999 WHERE emp_id = 2;
INSERT INTO employee_hr_update (..., reason='DATA ENTRY ERROR — wrong amount entered', ...);
SELECT vcs_commit('WRONG: Salary entry error for Priya Menon — ₹999999...', 'Suresh Pillai');
```

**Triggers fired:** `vcs_track_employee` (1 UPDATE), `vcs_track_employee_hr_update` (1 INSERT). Committed to `main`.

### Dry run

```sql
SELECT vcs_rollback(vcs_get_head_commit('main') - 1, NULL, TRUE);
```

`p_dry_run = TRUE` → function iterates the changes to be undone but does **not** execute any DML. Returns a text summary of what would be reverted.

### Actual rollback

```sql
DO $$
DECLARE v_rollback_to INT;
BEGIN
    SELECT commit_id INTO v_rollback_to
    FROM vcs_commit WHERE branch_name = 'main'
    ORDER BY commit_id DESC OFFSET 1 LIMIT 1;  -- HEAD-1 = merge commit
    PERFORM vcs_rollback(v_rollback_to);
END $$;
```

**What `vcs_rollback(target_commit_id)` does:**
1. Finds all `vcs_change` rows on the active branch with `commit_id > target_commit_id` (i.e. everything after the target)
2. Replays them in **reverse order** with inverse operations:
   - Original `INSERT` → execute `DELETE`
   - Original `DELETE` → execute `INSERT ... SELECT * FROM jsonb_populate_record(NULL::table, old_data)`
   - Original `UPDATE` → execute `UPDATE ... SET (cols) = (SELECT cols FROM jsonb_populate_record(NULL::table, old_data))`
3. Creates a new "rollback" commit on the branch — **the bad commit is not deleted**, just reversed. The full audit trail is preserved.

**Result:** `employee.salary` for `emp_id=2` is restored to `65000`. The wrong commit and the rollback commit both remain visible in `vcs_log()`.

---

## Step 11 — Time Travel (`git checkout v1.0 -- table`)

These are **read-only** — no DML, no triggers fire.

### `vcs_time_travel('customer', commit_id)`

Reconstructs the full state of the `customer` table as it was at the given commit. Reads all `vcs_change` rows up to and including that commit, applies them as a forward replay in memory, and returns each row as `(row_pk, row_state JSONB)`.

```sql
SELECT row_pk, row_state->>'full_name', row_state->>'kyc_status'
FROM vcs_time_travel('customer', (SELECT commit_id FROM vcs_tag WHERE tag_name = 'v1.0'))
ORDER BY row_pk::INT;
```

At `v1.0`: Rajan Varma's `kyc_status = 'expired'`, `status = 'dormant'` (seed values).  
Now: `status = 'blocked'` (changed in Step 5c).

### `vcs_reconstruct_at('loan', '1', commit_id)`

Returns the JSONB state of a **single row** (`loan_id=1`) at the specified commit. Faster than `vcs_time_travel` when you only need one row.

At `v1.0`: `tenure_months=240, interest_rate=8.50, emi_amount=39204`  
Now: `tenure_months=300, interest_rate=8.25, emi_amount=33150` (restructured in Step 4b)

---

## VCS Tables Reference

| Table | Purpose |
|---|---|
| `vcs_config` | Key-value store — `active_branch` is the critical entry |
| `vcs_repository` | Registry of tracked tables and their PK column |
| `vcs_branch` | Branch metadata (name, created_from, fork_commit) |
| `vcs_commit` | One row per commit (hash, message, author, timestamp, change_count, is_merge) |
| `vcs_commit_parent` | Parent links for merge commits (the DAG edges) |
| `vcs_staged_change` | Transient staging area — populated by `vcs_trigger_fn`, cleared by `vcs_commit` |
| `vcs_change` | Permanent change history — copied from staged on commit |
| `vcs_tag` | Named pointers to specific commit IDs |

---

## VCS Functions Reference

| Function | Git Equivalent | Demo Step |
|---|---|---|
| `vcs_init(table)` | `git init` (per table) | 1 |
| `vcs_snapshot_all(msg)` | `git add -A && git commit` (seed data) | 1 |
| `vcs_status()` | `git status` | 2 |
| `vcs_commit(msg, author)` | `git add -A && git commit -m` | 2, 4, 5, 8, 10 |
| `vcs_branch_create(name, from, desc, checkout)` | `git checkout -b` | 3 |
| `vcs_checkout(branch)` | `git checkout` | 3, 5, 7 |
| `vcs_branch_list()` | `git branch -a -v` | 3 |
| `vcs_log(branch)` | `git log` | 2, 4, 5, 9, 10 |
| `vcs_log_all(n)` | `git log --all` | 6a |
| `vcs_diff(from, to)` | `git diff <hash1> <hash2>` | 6b |
| `vcs_blame(table, branch)` | `git blame` | 6c |
| `vcs_row_history(table, pk)` | `git log -p -- <file>` | 6d, 6e |
| `vcs_diff_branch(source, target)` | `git diff branch1..branch2` | 6f |
| `vcs_tag_create(tag, commit, msg)` | `git tag -a` | 1, 7, 9 |
| `vcs_tag_list()` | `git tag -l` | 7 |
| `vcs_merge_conflicts(source, target)` | `git merge --no-commit` (conflict check) | 8 |
| `vcs_merge(source, target, msg)` | `git merge` | 9 |
| `vcs_rollback(commit_id, table, dry_run)` | `git revert` | 10 |
| `vcs_time_travel(table, commit_id)` | `git show <hash>:table` | 11 |
| `vcs_reconstruct_at(table, pk, commit_id)` | `git show <hash>:table -- row` | 11 |
| `vcs_get_active_branch()` | `git branch --show-current` | internal |
| `vcs_get_head_commit(branch)` | `git rev-parse HEAD` | internal |

---

## Expected Commit Count After Full Run

| Branch | Commits |
|---|---|
| `main` | ~9 (baseline, onboarding, HR, RBI rate, KYC, conflict-resolution, merge, wrong-entry, rollback) |
| `feature/loan-restructure` | 3 (branch-creation, loan approval, loan restructure) |
| **Total** | ~12 |

Tags created: `v1.0`, `v1.1-pre-merge`, `feature-loan-restructure-ready`, `v1.2`
