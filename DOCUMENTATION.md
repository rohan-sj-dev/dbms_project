# DS3020 DBMS Project — Retail Banking System with Git-Like VCS
## Comprehensive Documentation

**Project:** IIT Palakkad DS3020 — Banking System with Version Control  
**Database:** PostgreSQL 17, database `bank_versioning`  
**Application:** Express.js (port 3001) + React + Tailwind (port 5173)

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Roles and Privileges](#2-roles-and-privileges)
3. [Views and Justification](#3-views-and-justification)
4. [Functions](#4-functions)
5. [Triggers](#5-triggers)
6. [Indices](#6-indices)
7. [Integrity and General Constraints](#7-integrity-and-general-constraints)
8. [Sample Queries Using Functions, Roles, and Indices](#8-sample-queries-using-functions-roles-and-indices)
9. [Search Functionality](#9-search-functionality)

---

## 1. System Overview

The system models a multi-branch retail bank with 9 core business tables and an 8-table Git-like Version Control System (VCS) that tracks every INSERT, UPDATE, and DELETE on monitored tables as auditable commits on named branches.

### Core Business Tables

| Table | Description |
|---|---|
| `branch` | Physical bank branches |
| `department` | Departments within each branch |
| `employee` | Staff records |
| `employee_hr_update` | Audit log of all HR changes |
| `customer` | Customer profiles with KYC |
| `account` | Bank accounts (savings, current, salary, NRE, NRO) |
| `transaction` | Credit/debit transaction ledger |
| `fund_transfer` | Inter-account and inter-bank transfers |
| `loan` | Loan records with collateral info |
| `loan_application` | Pre-approval loan applications |

### VCS Metadata Tables

| Table | Git Analogue |
|---|---|
| `vcs_config` | Global settings (active branch pointer) |
| `vcs_repository` | Registered/tracked tables (`git init`) |
| `vcs_branch` | Named branch pointers |
| `vcs_commit` | Commit records with hash and author |
| `vcs_commit_parent` | Parent linkage for merge commits |
| `vcs_change` | Permanent row-level JSONB deltas per commit |
| `vcs_staged_change` | Uncommitted staged changes (working area) |
| `vcs_tag` | Immutable named references to commits |

---

## 2. Roles and Privileges

The system implements a **three-tier Role-Based Access Control (RBAC)** model. Each role is a PostgreSQL `NOLOGIN` group role; individual database users are granted one of these roles at login.

A session variable (`app.current_user_id` or `app.current_employee_id`) is set by the application layer at connection time, enabling Row-Level Security policies to enforce data isolation at the engine level.

---

### Role 1: `bank_customer`

**Description:** End customers who access the bank portal to view their own accounts, transactions, loans, and submit loan applications.

**Table Permissions:**

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|:---:|:---:|:---:|:---:|
| `customer` | ✅ (own row only via RLS) | | | |
| `account` | ✅ (own accounts via RLS) | | | |
| `transaction` | ✅ (own accounts' txns via RLS) | | | |
| `loan` | ✅ (own loans via RLS) | | | |
| `loan_application` | ✅ (own applications via RLS) | | | |
| `fund_transfer` | ✅ (own transfers via RLS) | | | |

**Function Permissions:**

| Function | Granted |
|---|:---:|
| `bank_apply_loan(customer_id, amount, purpose)` | ✅ |
| `bank_mini_statement(account_id, limit)` | ✅ |
| `bank_customer_summary(customer_id)` | ✅ |

**RLS Policies Applied:**
- `policy_customer_self` on `customer` — `customer_id = app.current_user_id`
- `policy_customer_own_accounts` on `account` — `customer_id = app.current_user_id`
- `policy_customer_own_txns` on `transaction` — via account ownership
- `policy_customer_own_loans` on `loan` — `customer_id = app.current_user_id`
- `policy_customer_own_apps` on `loan_application` — `customer_id = app.current_user_id`
- `policy_customer_own_transfers` on `fund_transfer` — via account ownership

---

### Role 2: `bank_employee`

**Description:** Bank staff (Relationship Managers, Loan Officers, Credit Analysts, Operations Executives). They can see customers assigned to them, manage loan applications in their queue, view their own HR record, and perform deposits/withdrawals/transfers.

**Table Permissions:**

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|:---:|:---:|:---:|:---:|
| `customer` | ✅ (assigned customers via RLS) | | | |
| `account` | ✅ (managed accounts via RLS) | | | |
| `transaction` | ✅ (managed customers' txns via RLS) | | | |
| `loan` | ✅ (assigned loans via RLS) | | | |
| `loan_application` | ✅ | ✅ | ✅ (assigned apps) | |
| `fund_transfer` | ✅ (managed via RLS) | | | |
| `employee` | ✅ (own record via RLS) | | | |
| `employee_hr_update` | ✅ (own events via RLS) | | | |
| `department` | ✅ | | | |
| `branch` | ✅ | | | |

**Function Permissions:**

| Function | Granted |
|---|:---:|
| `bank_deposit(account_id, amount)` | ✅ |
| `bank_withdraw(account_id, amount)` | ✅ |
| `bank_transfer(from_id, to_id, amount)` | ✅ |
| `bank_apply_loan(customer_id, amount, purpose)` | ✅ |
| `bank_review_loan(app_id, emp_id, status, notes)` | ✅ |
| `bank_mini_statement(account_id, limit)` | ✅ |
| `bank_customer_summary(customer_id)` | ✅ |
| `bank_emp_queue(emp_id)` | ✅ |
| `bank_emp_hr_history(emp_id)` | ✅ |

**RLS Policies Applied:**
- `policy_employee_customers` — sees customers where `assigned_rm_id = app.current_employee_id`
- `policy_employee_managed_accounts` — via assigned customer linkage
- `policy_employee_self` on `employee` — `emp_id = app.current_employee_id`
- `policy_employee_own_hr` on `employee_hr_update` — own HR events only
- `policy_employee_assigned_apps` on `loan_application` — `assigned_emp_id = app.current_employee_id`

---

### Role 3: `bank_manager`

**Description:** Branch Manager with full supervisory access across all branch data. Can perform all DML, process HR changes, override any loan application, and view all data unfiltered.

**Table Permissions:**

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|:---:|:---:|:---:|:---:|
| All 10 business tables | ✅ | ✅ | ✅ | ✅ |

Full access granted via `USING (TRUE)` RLS policies (bypass for all tables).

**Function Permissions:**

| Function | Granted |
|---|:---:|
| All `bank_employee` functions | ✅ |
| `bank_hr_update(emp_id, authorized_by, type, date, reason, ...)` | ✅ (exclusive) |
| `bank_emp_hr_history(emp_id)` | ✅ |

**RLS Policies Applied:**
- `policy_manager_all_*` on every table — unrestricted access with `USING (TRUE)`.

---

## 3. Views and Justification

The system defines **4 role-scoped views** plus a **branch summary utility view**. Each view is built on top of RLS-protected tables, so the same view used by a customer returns only their own rows, while a manager sees all rows.

---

### View 1: `view_customer_portal`

**Purpose:** Provides a complete, self-contained snapshot of a customer's banking profile — identity, branch, all accounts (with JSONB array), all active loans, and pending loan applications — in a single query.

**Justification:**
- Eliminates the need for the frontend to join 5 tables on every page load.
- Sensitive fields (Aadhaar, PAN) are kept in the underlying `customer` table and are not exposed in this view.
- Customers see only their own row (via RLS); managers see all customers.

**Access:** `bank_customer`, `bank_employee`, `bank_manager`

**Key columns:**

| Column | Description |
|---|---|
| `customer_id`, `full_name`, `kyc_status` | Customer identity |
| `branch_name`, `city` | Home branch |
| `active_account_count`, `total_active_balance` | Aggregated account data |
| `account_details` | JSONB array of all accounts |
| `active_loan_count`, `outstanding_loan_balance` | Aggregated loan data |
| `loan_details` | JSONB array of all active loans |
| `pending_application_count`, `application_details` | Loan application pipeline |

**Sample usage:**
```sql
SET app.current_user_id = '1';
SELECT full_name, total_active_balance, active_loan_count
FROM view_customer_portal;
```

---

### View 2: `view_employee_workbench`

**Purpose:** Gives each employee a unified view of their identity, the customers they manage, loan applications in their queue, and active loans they oversee. Sensitive identity fields (Aadhaar, PAN) are **masked** for non-manager employees.

**Justification:**
- Employees should not see full Aadhaar/PAN of customers — the view conditionally masks these based on `app.current_role`.
- Consolidates data from `employee`, `department`, `branch`, `customer`, `loan_application`, and `loan` into one queryable surface.
- RLS on underlying tables ensures employees can only see their assigned customers.

**Access:** `bank_employee`, `bank_manager`

**Key columns:**

| Column | Description |
|---|---|
| `emp_id`, `designation`, `salary` | Employee identity |
| `dept_name`, `branch_name` | Org structure |
| `customer_name`, `kyc_status`, `aadhaar_masked`, `pan_masked` | Customer data (masked for employees) |
| `application_id`, `application_status`, `days_pending` | Loan queue |
| `loan_id`, `outstanding_principal`, `emi_amount` | Active loan oversight |

**Sample usage:**
```sql
SET app.current_employee_id = '3';
SELECT customer_name, application_status, days_pending
FROM view_employee_workbench
WHERE application_status IN ('submitted', 'under_review');
```

---

### View 3: `view_employee_hr_record`

**Purpose:** Presents the full, human-readable HR history for an employee — all salary revisions, promotions, transfers, and designation changes — with department and authoriser names resolved.

**Justification:**
- The raw `employee_hr_update` table stores FK IDs (dept_id, authorized_by). This view joins in names, making the data directly usable in the UI without additional queries.
- Employees can only see their own HR events (via RLS policy `policy_employee_own_hr`); managers see all.
- Supports the self-service HR History page and audit reporting.

**Access:** `bank_employee`, `bank_manager`

**Key columns:**

| Column | Description |
|---|---|
| `update_type` | Type of HR event |
| `effective_date` | When the change took effect |
| `old_designation` → `new_designation` | Designation change trail |
| `old_dept_name` → `new_dept_name` | Department transfer trail |
| `old_salary` → `new_salary` | Salary revision trail |
| `authorised_by` | Full name of approving manager |

**Sample usage:**
```sql
SET app.current_employee_id = '2';
SELECT update_type, effective_date, old_salary, new_salary, authorised_by
FROM view_employee_hr_record
ORDER BY effective_date;
```

---

### View 4: `view_manager_dashboard`

**Purpose:** Branch-level operational overview for the branch manager. Shows staffing breakdown, customer acquisition counts, deposit book, loan book size, NPA count, and the full application pipeline — all aggregated per branch.

**Justification:**
- Branch managers need a bird's-eye view of branch health without writing complex aggregate queries.
- Includes JSONB staff listing for dynamic rendering.
- Access restricted to `bank_manager` only.

**Access:** `bank_manager` only

**Key columns:**

| Column | Description |
|---|---|
| `total_staff`, `permanent_staff`, `contract_staff` | Headcount breakdown |
| `total_customers`, `active_customers`, `kyc_pending_count` | Customer metrics |
| `total_deposit_book` | Sum of active account balances |
| `active_loans`, `total_outstanding`, `npa_loans` | Loan book health |
| `submitted_count`, `under_review_count`, `approved_count` | Application pipeline |

**Sample usage:**
```sql
-- Manager-only view; no RLS session variable needed
SELECT branch_name, total_customers, total_deposit_book, npa_loans
FROM view_manager_dashboard;
```

---

### View 5: `branch_summary` (Utility View)

**Purpose:** A lightweight aggregate of each branch's customer count, account count, total deposits, active loan book, and staff count. Used by the dashboard homepage.

**Justification:** Provides a quick KPI rollup for the home page without hitting multiple tables. No RLS — this is accessed only by the application backend which enforces access at the API layer.

**Sample usage:**
```sql
SELECT * FROM branch_summary;
```

---

## 4. Functions

The system has **13 stored functions** across banking operations, VCS operations, and utility helpers. At least one function exists for each role.

---

### Banking Functions (10 functions)

#### F1: `bank_deposit(p_account_id INT, p_amount NUMERIC)` → `TEXT`
**Role:** `bank_employee`, `bank_manager`  
**Purpose:** Validates the account is active, credits the balance atomically, and writes a `transaction` record with a unique reference number.  
**Consistency preserved:** Account status check prevents deposits to frozen/closed accounts. Balance update and transaction record are in the same transaction — no partial updates.

```sql
SELECT bank_deposit(1, 5000.00);
-- Returns: 'Deposit successful'
```

---

#### F2: `bank_withdraw(p_account_id INT, p_amount NUMERIC)` → `TEXT`
**Role:** `bank_employee`, `bank_manager`  
**Purpose:** Validates active status and sufficient balance before debiting. Records a debit transaction.  
**Consistency preserved:** Raises `EXCEPTION` if `current_balance < p_amount`, preventing overdrafts. Atomic with the transaction insert.

```sql
SELECT bank_withdraw(1, 2000.00);
-- Returns: 'Withdrawal successful'
-- Raises: 'Insufficient balance' if funds are low
```

---

#### F3: `bank_transfer(p_from INT, p_to INT, p_amount NUMERIC)` → `TEXT`
**Role:** `bank_employee`, `bank_manager`  
**Purpose:** Atomic debit from source and credit to destination account. Both `UPDATE` statements execute within the same function call (PostgreSQL implicit transaction).  
**Consistency preserved:** Insufficient funds check before any update. If either UPDATE fails, the entire function rolls back.

```sql
SELECT bank_transfer(1, 2, 10000.00);
-- Returns: 'Transfer successful'
```

---

#### F4: `bank_apply_loan(p_customer_id INT, p_requested_amount DECIMAL, p_purpose TEXT)` → `TEXT`
**Role:** `bank_customer`, `bank_employee`, `bank_manager`  
**Purpose:** Validates customer exists, amount is positive, determines the customer's branch, auto-assigns a Loan Officer from that branch, and inserts a `loan_application` record.  
**Consistency preserved:** Foreign key to `customer` validated before insert. Falls back gracefully to any active employee if no Loan Officer is found.

```sql
SELECT bank_apply_loan(1, 500000, 'Home renovation');
-- Returns: 'Loan application 5 submitted. Customer: 1, Amount: ₹500000.00, ...'
```

---

#### F5: `bank_review_loan(p_app_id INT, p_emp_id INT, p_new_status VARCHAR, p_notes TEXT)` → `TEXT`
**Role:** `bank_employee` (assigned officer only), `bank_manager` (any application)  
**Purpose:** Implements a role-based workflow for loan application state transitions. Validates the employee's designation and assignment before allowing status changes. If approved, creates a corresponding `loan` record.  
**Consistency preserved:** Role check inside the function enforces business rules independent of DB-level permissions. Prevents unauthorized employees from approving loans they are not assigned to.

```sql
SELECT bank_review_loan(1, 3, 'approved', 'Documents verified, credit score satisfactory');
-- Returns: 'Application 1 updated to: approved'
```

---

#### F6: `bank_mini_statement(p_account_id INT, p_limit INT)` → `TABLE`
**Role:** `bank_customer`, `bank_employee`, `bank_manager`  
**Purpose:** Returns the last N transactions for an account ordered by date descending, with a CR/DR direction label and balance after each transaction.  
**Consistency preserved:** Read-only function; used solely for display.

```sql
SELECT * FROM bank_mini_statement(1, 5);
-- Returns: txn_id, txn_type, amount, direction (CR/DR), txn_time, balance
```

---

#### F7: `bank_customer_summary(p_customer_id INT)` → `TEXT`
**Role:** `bank_customer`, `bank_employee`, `bank_manager`  
**Purpose:** Returns a formatted text summary of a customer's accounts, active loans, and pending loan applications. Designed for quick terminal/API lookup.  
**Consistency preserved:** Validates customer existence before querying; raises exception for invalid IDs.

```sql
SELECT bank_customer_summary(1);
-- Returns: === Customer Summary: Arjun Pillai (ID: 1) ===
--          --- Accounts ---
--          1 [savings] active — ₹85000.00
--          ...
```

---

#### F8: `bank_emp_queue(p_emp_id INT)` → `TABLE`
**Role:** `bank_employee`, `bank_manager`  
**Purpose:** Returns all loan applications assigned to an employee that are still pending review, with the number of days they have been waiting.  
**Consistency preserved:** Read-only; helps employees prioritise work and prevents applications from going unnoticed.

```sql
SELECT * FROM bank_emp_queue(3);
-- Returns: app_id, customer_name, amount, app_status, days_waiting
```

---

#### F9: `bank_hr_update(p_emp_id INT, p_authorized_by INT, p_update_type VARCHAR, p_effective_date DATE, p_reason TEXT, p_new_designation VARCHAR, p_new_dept_id INT, p_new_salary NUMERIC, p_new_emp_type VARCHAR)` → `TEXT`
**Role:** `bank_manager` (exclusive)  
**Purpose:** The master HR event function. Validates the authorising manager's role, captures the current employee state as "old" data, writes a full audit record to `employee_hr_update`, then applies the change to `employee` — all atomically. Supports: salary_revision, promotion, demotion, department_transfer, designation_change, employment_type_change, termination, reinstatement.  
**Consistency preserved:**  
- An employee cannot authorise their own change.
- Only Branch Manager or Senior Relationship Manager may authorise.
- Type-specific validations (e.g., `p_new_salary` required for salary_revision).
- `termination` on an already-terminated employee is rejected.
- `reinstatement` on a non-terminated employee is rejected.

```sql
SELECT bank_hr_update(
    3,                    -- emp_id (Arun Kumar)
    1,                    -- authorized_by (Rajesh Nair, Branch Manager)
    'salary_revision',
    CURRENT_DATE,
    'Annual increment FY2025-26',
    NULL, NULL, 60000.00, NULL
);
-- Returns: ✅ HR Update #6 recorded. Salary: ₹55000.00 → ₹60000.00
```

---

#### F10: `bank_emp_hr_history(p_emp_id INT)` → `TABLE`
**Role:** `bank_employee` (own history only via RLS), `bank_manager`  
**Purpose:** Returns the complete HR event history for an employee with all FK IDs resolved to names (department name, authoriser name).  
**Consistency preserved:** Validates employee existence. RLS on `employee_hr_update` ensures employees only see their own rows when querying directly.

```sql
SELECT * FROM bank_emp_hr_history(2);
-- Returns: hr_update_id, update_type, effective_date, old_designation,
--          new_designation, old_dept, new_dept, old_salary, new_salary,
--          authorized_by, recorded_at
```

---

### VCS Functions (selected key functions)

#### F11: `vcs_init(p_table_name VARCHAR, p_pk_column VARCHAR)` → `TEXT`
**Purpose:** Registers a table for version tracking. Auto-detects the primary key column. Creates a `AFTER INSERT OR UPDATE OR DELETE` trigger on the target table that routes all changes to the staging area.

```sql
SELECT vcs_init('customer');
-- Returns: ✅ Now tracking table "customer" (PK: customer_id). Changes will be auto-staged.
```

---

#### F12: `vcs_commit(p_message TEXT, p_author VARCHAR)` → `TEXT`
**Purpose:** Moves all staged changes on the active branch into permanent `vcs_change` records, linked to a new `vcs_commit` entry with an MD5 hash. Clears the staging area afterwards.

```sql
SELECT vcs_commit('Added 10 new customers for October batch', 'admin');
-- Returns: ✅ [main a3f21b9c] Added 10 new customers ... 10 change(s) committed
```

---

#### F13: `vcs_trigger_fn()` → `TRIGGER`
**Purpose:** The auto-capture trigger function. For each row change on a tracked table, it serialises `OLD` and `NEW` as JSONB, computes the list of changed columns (for UPDATEs), and inserts into `vcs_staged_change` under the currently active branch. Returns `NEW` (or `OLD` for DELETE) to allow the underlying DML to proceed normally.

---

## 5. Triggers

The system has **5 triggers** (4 on business tables + 1 VCS master trigger template).

---

### Trigger 1–4: `vcs_track_<tablename>` (Auto-Staging Triggers)

Created dynamically by `vcs_init()` on each tracked table. Four tables are tracked by default:

| Trigger Name | Table | Event |
|---|---|---|
| `vcs_track_branch` | `branch` | `AFTER INSERT OR UPDATE OR DELETE` |
| `vcs_track_employee` | `employee` | `AFTER INSERT OR UPDATE OR DELETE` |
| `vcs_track_customer` | `customer` | `AFTER INSERT OR UPDATE OR DELETE` |
| `vcs_track_account` | `account` | `AFTER INSERT OR UPDATE OR DELETE` |

**Trigger Function:** `vcs_trigger_fn()` (defined once, shared by all four triggers via `EXECUTE FUNCTION`)

**How it preserves consistency:**
- Every data change on a tracked table is automatically captured in JSONB format with both old and new states — there is no way for a change to occur without being staged.
- For `UPDATE`, only columns that actually changed are listed in `changed_columns`, reducing noise in the change log.
- The trigger fires `AFTER` the DML, so the staged record is only written if the underlying change committed successfully — no phantom staging for rolled-back transactions.
- This creates a full, tamper-evident audit trail for customer, account, employee, and branch data, which is critical for banking compliance.

**Execution flow:**
```
INSERT/UPDATE/DELETE on customer
  → vcs_track_customer trigger fires
    → vcs_trigger_fn() reads vcs_config for active_branch
    → serialises NEW/OLD as JSONB
    → inserts into vcs_staged_change
  → change is now in staging, awaiting vcs_commit()
```

---

### Trigger 5: Implicit Account Balance Integrity (via `bank_deposit` / `bank_withdraw`)

While not a PostgreSQL `CREATE TRIGGER` statement, the deposit and withdrawal functions enforce a trigger-like constraint: the balance in `account.current_balance` is always updated in the same atomic operation as the corresponding `transaction` record insertion, preventing the account balance from ever diverging from the transaction ledger.

> **Note:** If a true balance-ledger reconciliation trigger is required, it can be added with `CREATE TRIGGER check_balance_after_txn AFTER INSERT ON transaction ...` to validate `balance_after = (prior balance ± amount)`.

---

## 6. Indices

### Default Indices (Created Automatically by PostgreSQL)

PostgreSQL creates a B-tree index on every `PRIMARY KEY` and `UNIQUE` constraint. These are the default indices:

| Index | Table | Column(s) | Reason |
|---|---|---|---|
| `branch_pkey` | `branch` | `branch_id` | Primary key |
| `branch_ifsc_code_key` | `branch` | `ifsc_code` | UNIQUE constraint |
| `department_pkey` | `department` | `dept_id` | Primary key |
| `employee_pkey` | `employee` | `emp_id` | Primary key |
| `employee_hr_update_pkey` | `employee_hr_update` | `hr_update_id` | Primary key |
| `customer_pkey` | `customer` | `customer_id` | Primary key |
| `customer_aadhaar_number_key` | `customer` | `aadhaar_number` | UNIQUE constraint |
| `customer_pan_number_key` | `customer` | `pan_number` | UNIQUE constraint |
| `account_pkey` | `account` | `account_id` | Primary key |
| `account_account_number_key` | `account` | `account_number` | UNIQUE constraint |
| `transaction_pkey` | `transaction` | `txn_id` | Primary key |
| `transaction_reference_number_key` | `transaction` | `reference_number` | UNIQUE constraint |
| `fund_transfer_pkey` | `fund_transfer` | `transfer_id` | Primary key |
| `loan_pkey` | `loan` | `loan_id` | Primary key |
| `loan_application_pkey` | `loan_application` | `application_id` | Primary key |

---

### Additional Indices (Explicitly Created)

These indices were created to optimise the most frequent queries in the system — customer lookups, transaction history retrieval, loan status filtering, and transfer queries.

#### Business Table Indices

| Index Name | Table | Column | Purpose |
|---|---|---|---|
| `idx_customer_branch` | `customer` | `branch_id` | Speeds up branch-wise customer listing (manager dashboard, `branch_summary` view) |
| `idx_account_customer` | `account` | `customer_id` | Accelerates fetching all accounts for a customer (used in `view_customer_portal`, `bank_customer_summary`) |
| `idx_txn_account` | `transaction` | `account_id` | Core index for transaction history lookup — every mini-statement query filters on this |
| `idx_txn_date` | `transaction` | `txn_date` | Range queries on transaction date (e.g., monthly statement, date-range filters) |
| `idx_loan_customer` | `loan` | `customer_id` | Loan lookup by customer (used in `view_customer_portal`, loan page filters) |
| `idx_loan_status` | `loan` | `status` | Filters active/NPA/closed loans efficiently (used in `branch_summary`, manager dashboard) |
| `idx_transfer_from` | `fund_transfer` | `from_account_id` | Speeds up listing outgoing transfers for an account |
| `idx_hr_emp` | `employee_hr_update` | `emp_id` | Accelerates HR history queries per employee (used in `view_employee_hr_record`, `bank_emp_hr_history`) |

#### VCS System Indices

| Index Name | Table | Column | Purpose |
|---|---|---|---|
| `idx_vcs_change_pk` | `vcs_change` | `(table_name, row_pk)` | Composite index for looking up the full history of a specific row across all commits |
| `idx_vcs_staged_branch` | `vcs_staged_change` | `branch_name` | Filters staged changes by branch (used in `vcs_status`, `vcs_commit`) |
| `idx_vcs_commit_branch` | `vcs_commit` | `(branch_name, committed_at)` | Ordered lookup of commits on a branch — critical for `vcs_get_head_commit` and `vcs_log` |
| `idx_vcs_commit_hash` | `vcs_commit` | `commit_hash` | Direct lookup of a commit by its hash (used in `vcs_checkout`) |
| `idx_vcs_commit_parent` | `vcs_commit_parent` | `commit_id` | Traverses commit ancestry for history walk and merge-base detection |

---

### Frequent Queries Benefiting From Additional Indices

**1. Transaction history for an account (uses `idx_txn_account`, `idx_txn_date`):**
```sql
SELECT txn_type, amount, balance_after, txn_date, description
FROM transaction
WHERE account_id = 1
ORDER BY txn_date DESC
LIMIT 20;
-- idx_txn_account filters account_id=1; idx_txn_date supports ORDER BY txn_date
```

**2. All active accounts for a customer (uses `idx_account_customer`):**
```sql
SELECT account_number, account_type, current_balance, status
FROM account
WHERE customer_id = 1 AND status = 'active';
-- idx_account_customer narrows to customer rows before status filter
```

**3. Active loan book for a branch (uses `idx_loan_status`, `idx_customer_branch`):**
```sql
SELECT l.loan_type, l.outstanding_principal, c.full_name
FROM loan l
JOIN customer c ON c.customer_id = l.customer_id
WHERE l.status = 'active'
  AND c.branch_id = 1;
-- idx_loan_status filters active loans; idx_customer_branch filters by branch
```

**4. HR history for an employee (uses `idx_hr_emp`):**
```sql
SELECT update_type, effective_date, old_salary, new_salary
FROM employee_hr_update
WHERE emp_id = 2
ORDER BY effective_date;
-- idx_hr_emp directly locates all HR records for emp_id=2
```

**5. VCS status — staged changes for active branch (uses `idx_vcs_staged_branch`):**
```sql
SELECT table_name, operation, row_pk, staged_at
FROM vcs_staged_change
WHERE branch_name = 'main'
ORDER BY staged_at;
-- idx_vcs_staged_branch makes this O(staged changes on main), not a full table scan
```

**6. Find full history of a specific customer row in VCS (uses `idx_vcs_change_pk`):**
```sql
SELECT c.commit_hash, c.message, ch.operation, ch.old_data, ch.new_data
FROM vcs_change ch
JOIN vcs_commit c ON c.commit_id = ch.commit_id
WHERE ch.table_name = 'customer' AND ch.row_pk = '1'
ORDER BY ch.changed_at;
-- idx_vcs_change_pk (table_name, row_pk) is a composite index hit
```

**7. Outgoing transfers from an account (uses `idx_transfer_from`):**
```sql
SELECT transfer_mode, amount, status, initiated_at
FROM fund_transfer
WHERE from_account_id = 3
ORDER BY initiated_at DESC;
-- idx_transfer_from covers from_account_id lookup directly
```

---

## 7. Integrity and General Constraints

### Entity Integrity (Primary Keys)
Every table has a `SERIAL PRIMARY KEY`. PostgreSQL enforces uniqueness and NOT NULL on all primary key columns automatically.

### Referential Integrity (Foreign Keys)

| Constraint | Child Table | Column | References |
|---|---|---|---|
| `fk_dept_branch` | `department` | `branch_id` | `branch(branch_id)` |
| `fk_dept_head` | `department` | `dept_head_id` | `employee(emp_id)` |
| `fk_emp_branch` | `employee` | `branch_id` | `branch(branch_id)` |
| `fk_emp_dept` | `employee` | `dept_id` | `department(dept_id)` |
| `fk_emp_manager` | `employee` | `manager_id` | `employee(emp_id)` (self-reference) |
| `fk_hr_emp` | `employee_hr_update` | `emp_id` | `employee(emp_id)` |
| `fk_hr_auth` | `employee_hr_update` | `authorized_by` | `employee(emp_id)` |
| `fk_cust_branch` | `customer` | `branch_id` | `branch(branch_id)` |
| `fk_cust_rm` | `customer` | `assigned_rm_id` | `employee(emp_id)` |
| `fk_cust_kyc_verif` | `customer` | `kyc_verified_by` | `employee(emp_id)` |
| `fk_acct_customer` | `account` | `customer_id` | `customer(customer_id)` |
| `fk_acct_branch` | `account` | `branch_id` | `branch(branch_id)` |
| `fk_acct_opened_by` | `account` | `opened_by` | `employee(emp_id)` |
| `fk_txn_account` | `transaction` | `account_id` | `account(account_id)` |
| `fk_txn_emp` | `transaction` | `initiated_by` | `employee(emp_id)` |
| `fk_ft_from` | `fund_transfer` | `from_account_id` | `account(account_id)` |
| `fk_ft_to` | `fund_transfer` | `to_account_id` | `account(account_id)` |
| `fk_loan_customer` | `loan` | `customer_id` | `customer(customer_id)` |
| `fk_loan_account` | `loan` | `account_id` | `account(account_id)` |
| `fk_loan_officer` | `loan` | `assigned_officer` | `employee(emp_id)` |
| `fk_loanapp_cust` | `loan_application` | `customer_id` | `customer(customer_id)` |
| `fk_loanapp_emp` | `loan_application` | `assigned_emp_id` | `employee(emp_id)` |

### Domain Constraints (CHECK)

| Table | Column | Allowed Values | Description |
|---|---|---|---|
| `branch` | `status` | `'active', 'inactive', 'closed'` | Branch lifecycle |
| `employee` | `employment_type` | `'permanent', 'contract', 'probation'` | Contract category |
| `employee` | `status` | `'active', 'resigned', 'terminated'` | Employment status |
| `employee_hr_update` | `update_type` | 8 values (salary_revision, promotion, demotion, etc.) | HR event taxonomy |
| `customer` | `gender` | `'M', 'F', 'O'` | ISO gender codes |
| `customer` | `income_bracket` | 5 bracket values | Income categorisation |
| `customer` | `kyc_status` | `'pending', 'verified', 'expired', 'rejected'` | KYC lifecycle |
| `customer` | `status` | `'active', 'dormant', 'closed', 'blocked'` | Account holder status |
| `account` | `account_type` | `'savings', 'current', 'salary', 'nre', 'nro'` | Deposit product type |
| `account` | `status` | `'active', 'frozen', 'dormant', 'closed'` | Account lifecycle |
| `transaction` | `txn_type` | `'credit', 'debit'` | Direction of money movement |
| `transaction` | `channel` | `'branch', 'atm', 'upi', 'neft', 'rtgs', 'imps', 'system'` | Transaction channel |
| `transaction` | `amount` | `> 0` | Positive amounts only |
| `fund_transfer` | `transfer_mode` | `'neft', 'rtgs', 'imps', 'upi', 'internal'` | Transfer protocol |
| `fund_transfer` | `status` | `'pending', 'processing', 'completed', 'failed', 'reversed'` | Transfer lifecycle |
| `fund_transfer` | `amount` | `> 0` | Positive amounts only |
| `loan` | `loan_type` | `'home', 'personal', 'vehicle', 'education', 'gold'` | Loan product category |
| `loan` | `application_status` | 6 values | Approval workflow state |
| `loan` | `collateral_type` | `'property', 'gold', 'vehicle', 'fd', 'none'` | Collateral category |
| `loan` | `status` | 6 values | Loan lifecycle state |
| `loan_application` | `status` | `'submitted', 'under_review', 'approved', 'rejected'` | Pre-approval workflow |
| `vcs_staged_change` | `operation` | `'INSERT', 'UPDATE', 'DELETE'` | DML type |
| `vcs_change` | `operation` | `'INSERT', 'UPDATE', 'DELETE'` | DML type |

### Uniqueness Constraints

| Table | Column | Description |
|---|---|---|
| `branch` | `ifsc_code` | Every branch has a globally unique IFSC |
| `customer` | `aadhaar_number` | Aadhaar is a unique national ID |
| `customer` | `pan_number` | PAN is a unique tax identifier |
| `account` | `account_number` | No two accounts share a number |
| `transaction` | `reference_number` | Every transaction has a unique reference |
| `vcs_branch` | `branch_name` | VCS branches must be uniquely named |
| `vcs_repository` | `table_name` | Each table can only be tracked once |

### NOT NULL Constraints (Key Columns)

Critical columns enforced as NOT NULL:
- `employee.full_name`, `employee.designation`, `employee.join_date`, `employee.salary`
- `customer.full_name`, `customer.dob`, `customer.phone`, `customer.kyc_status`
- `account.account_number`, `account.account_type`, `account.current_balance`
- `transaction.txn_type`, `transaction.channel`, `transaction.amount`, `transaction.reference_number`
- `loan.applied_amount`, `loan.application_date`, `loan.status`
- `employee_hr_update.reason` (mandatory justification for all HR changes)

### General Business Rule Constraints (Enforced in Functions)

| Rule | Enforced in | Description |
|---|---|---|
| No overdraft | `bank_withdraw()` | Balance must be ≥ withdrawal amount before debit |
| Active account required | `bank_deposit()`, `bank_withdraw()` | Only `status = 'active'` accounts accept transactions |
| Positive loan amount | `bank_apply_loan()` | `p_requested_amount > 0` |
| HR authorisation hierarchy | `bank_hr_update()` | Only Branch Manager or Senior RM may approve HR changes |
| Self-authorisation ban | `bank_hr_update()` | `p_emp_id ≠ p_authorized_by` |
| Loan review assignment | `bank_review_loan()` | Loan Officers may only review applications assigned to them |
| Reinstatement guard | `bank_hr_update()` | Reinstatement only allowed on `status = 'terminated'` employees |

---

## 8. Sample Queries Using Functions, Roles, and Indices

These five queries demonstrate distinct combinations of roles, functions, and indexed columns.

---

### Query 1: Customer views their own mini-statement (`bank_customer` role + `idx_txn_account`)

```sql
-- Session setup for Customer role
SET app.current_user_id = '1';

-- Call function (bank_customer has EXECUTE privilege)
-- Uses idx_txn_account on transaction.account_id
SELECT
    txn_id,
    txn_type,
    amount,
    direction,
    txn_time,
    balance
FROM bank_mini_statement(1, 10);
```

**Role used:** `bank_customer`  
**Function used:** `bank_mini_statement(account_id, limit)`  
**Index used:** `idx_txn_account` (filters `transaction.account_id = 1`)  
**What it shows:** Last 10 transactions with CR/DR direction label, supporting the customer's passbook view.

---

### Query 2: Employee processes a deposit and reviews their work queue (`bank_employee` role + `idx_account_customer` + `bank_deposit` + `bank_emp_queue`)

```sql
-- Session setup for Employee role
SET app.current_employee_id = '3';  -- Arun Kumar, Loan Officer

-- Step 1: Perform a deposit (uses idx_account_customer internally)
SELECT bank_deposit(2, 15000.00);

-- Step 2: Check pending applications queue
-- Uses idx_txn_account and loan_application.assigned_emp_id filter
SELECT * FROM bank_emp_queue(3);
```

**Role used:** `bank_employee`  
**Functions used:** `bank_deposit()`, `bank_emp_queue()`  
**Index used:** `idx_account_customer` (to validate account ownership within `bank_deposit`)  
**What it shows:** An employee can service a customer (deposit) and then review their pending loan approval tasks in the same session.

---

### Query 3: Manager applies an HR update and queries the HR history (`bank_manager` role + `idx_hr_emp` + `bank_hr_update` + `bank_emp_hr_history`)

```sql
-- Manager session (no RLS variable needed — USING(TRUE))

-- Promote employee 5 (Anitha Varghese) with salary revision
SELECT bank_hr_update(
    5,                          -- emp_id
    1,                          -- authorized_by (Rajesh Nair, Branch Manager)
    'promotion',
    CURRENT_DATE,
    'Exceptional FY2025 performance; exceeded RM targets by 28%',
    'Senior Relationship Manager',  -- new designation
    NULL,                           -- dept unchanged
    58000.00,                       -- new salary
    NULL                            -- emp_type unchanged
);

-- Verify the change (uses idx_hr_emp on employee_hr_update.emp_id)
SELECT update_type, effective_date, old_salary, new_salary, authorized_by
FROM bank_emp_hr_history(5);
```

**Role used:** `bank_manager`  
**Functions used:** `bank_hr_update()`, `bank_emp_hr_history()`  
**Index used:** `idx_hr_emp` (filters `employee_hr_update.emp_id = 5`)  
**What it shows:** The complete HR change lifecycle — authorised update recorded with before/after state, then the audit trail retrieved.

---

### Query 4: Loan application workflow across all three roles

```sql
-- === Step 1: Customer submits a loan application ===
SET app.current_user_id = '4';   -- Lakshmi Nair
SELECT bank_apply_loan(4, 800000, 'Purchase of electric vehicle');

-- === Step 2: Employee reviews and moves to 'under_review' ===
SET app.current_employee_id = '3';
SELECT bank_review_loan(
    (SELECT MAX(application_id) FROM loan_application),
    3,
    'under_review',
    'Income documents requested from customer'
);

-- === Step 3: Manager approves the loan (uses idx_loan_customer) ===
-- Manager session (no SET needed)
SELECT bank_review_loan(
    (SELECT MAX(application_id) FROM loan_application),
    1,
    'approved',
    'All documents verified. Credit profile strong.'
);

-- Verify loan created (uses idx_loan_customer and idx_loan_status)
SELECT loan_id, loan_type, application_status, status
FROM loan
WHERE customer_id = 4
ORDER BY application_date DESC;
```

**Roles used:** `bank_customer`, `bank_employee`, `bank_manager` (all three)  
**Function used:** `bank_apply_loan()`, `bank_review_loan()` (across roles)  
**Indices used:** `idx_loan_customer`, `idx_loan_status`  
**What it shows:** The complete loan approval workflow — customer submits, employee processes, manager approves — demonstrating multi-role collaboration on the same data.

---

### Query 5: Manager queries branch KPIs combining views and indexed joins

```sql
-- Manager-only query combining view_manager_dashboard + indexed loan/customer counts

SELECT
    vmd.branch_name,
    vmd.total_customers,
    vmd.active_customers,
    vmd.total_deposit_book,
    vmd.active_loans,
    vmd.total_outstanding,
    vmd.npa_loans,
    vmd.submitted_count + vmd.under_review_count  AS pending_applications,
    bs.total_staff
FROM view_manager_dashboard vmd
JOIN branch_summary bs USING (branch_name)
ORDER BY vmd.total_deposit_book DESC;
```

**Role used:** `bank_manager`  
**View used:** `view_manager_dashboard`, `branch_summary`  
**Indices used:** `idx_customer_branch`, `idx_loan_status`, `idx_account_customer` (all used internally by the view's lateral joins)  
**What it shows:** A single query gives the manager a complete branch health dashboard — deposit book, active loans, NPA count, pending application pipeline, and headcount.

---

## 9. Search Functionality

### Implementation

Search is implemented as **per-page client-side filtering** in the React frontend. There is no separate search page; instead, each of the 7 CRUD table pages has an inline search bar.

### Technical Approach

Each page uses React's `useMemo` hook to filter the already-loaded data array without additional API calls:

```jsx
const [search, setSearch] = useState('');

const filtered = useMemo(() => {
    if (!data || !search.trim()) return data || [];
    const q = search.toLowerCase();
    return data.filter(r =>
        [r.field1, r.field2, r.field3].some(v =>
            v && String(v).toLowerCase().includes(q)
        )
    );
}, [data, search]);
```

### Searchable Fields Per Page

| Page | Searchable Fields |
|---|---|
| Customers | `full_name`, `phone`, `email`, `occupation`, `pan_number`, `aadhaar_number`, `status`, `kyc_status` |
| Accounts | `account_number`, `customer_name`, `account_type`, `status` |
| Transactions | `account_number`, `reference_number`, `description`, `txn_type`, `channel` |
| Loans | `customer_name`, `loan_type`, `application_status`, `status`, `purpose`, `officer_name` |
| Employees | `full_name`, `designation`, `dept_name`, `branch_name`, `employment_type`, `status`, `manager_name` |
| Transfers | `from_account_number`, `to_account_number`, `transfer_mode`, `status`, `remarks` |
| Branches | `branch_name`, `ifsc_code`, `city`, `state`, `phone`, `status` |

### Indices Supporting Search-Related Queries

When the backend API endpoints populate these pages (loading the data to be searched client-side), the following indices are used:

| Page Endpoint | Index Used | Column Filtered |
|---|---|---|
| `GET /api/customers` | `idx_customer_branch` | Filters by `branch_id` for branch-scoped managers |
| `GET /api/accounts` | `idx_account_customer` | Joins accounts to customers for `customer_name` lookup |
| `GET /api/transactions` | `idx_txn_account`, `idx_txn_date` | Loads recent transactions efficiently |
| `GET /api/loans` | `idx_loan_customer`, `idx_loan_status` | Joins loan to customer; filters by status |
| `GET /api/transfers` | `idx_transfer_from` | Loads transfers by source account |
| `GET /api/employees` | `idx_hr_emp` | Used when joining HR update counts |

The client-side search then operates as a fast in-memory `Array.filter()` on the already-loaded dataset (50 customers, 70 accounts, 521 transactions, 38 loans, 30 transfers, 24 employees across 9 branches).

---

*End of Documentation*