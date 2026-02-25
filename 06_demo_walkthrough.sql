-- ============================================================
-- GIT-LIKE DATABASE VERSIONING - COMPLETE DEMO WALKTHROUGH
-- ============================================================
-- This script demonstrates the full versioning system using
-- the banking database. Run setup.sql and files 01-05 first.
--
-- Workflow mirrors a real Git session:
--   1) Init tracking on tables
--   2) Snapshot baseline
--   3) Make changes & commit
--   4) Create branches
--   5) Branch-specific changes
--   6) View diffs, logs, history
--   7) Merge branches
--   8) Rollback
--   9) Tags & blame
-- ============================================================

-- ============================================================
-- STEP 0: VERIFY SYSTEM IS READY
-- ============================================================
SELECT '========================================' AS "STEP 0: System Check";

-- Check if VCS system is installed
DO $$
DECLARE
    v_function_count INT;
    v_table_count INT;
BEGIN
    -- Count VCS functions
    SELECT COUNT(*) INTO v_function_count
    FROM information_schema.routines
    WHERE routine_schema = 'public' AND routine_name LIKE 'vcs_%';
    
    -- Count VCS tables
    SELECT COUNT(*) INTO v_table_count
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name LIKE 'vcs_%';
    
    IF v_function_count < 20 THEN
        RAISE EXCEPTION 
            E'\n❌ VCS FUNCTIONS NOT INSTALLED!\n\nFound only % VCS functions. Expected 25+.\n\nYou must install the VCS system first:\n  \\i 00_install_all.sql\n\nOR run files individually in order:\n  \\i setup.sql\n  \\i 01_vcs_schema.sql\n  \\i 02_vcs_core_functions.sql\n  \\i 03_vcs_branch_functions.sql\n  \\i 04_vcs_history_functions.sql\n  \\i 05_vcs_rollback_functions.sql\n', 
            v_function_count;
    END IF;
    
    IF v_table_count < 7 THEN
        RAISE EXCEPTION 
            E'\n❌ VCS TABLES NOT CREATED!\n\nFound only % VCS tables. Expected 7+.\n\nYou must install the VCS schema first:\n  \\i 01_vcs_schema.sql\n', 
            v_table_count;
    END IF;
    
    RAISE NOTICE E'✅ VCS System Check Passed\n   Functions: %\n   Tables: %', v_function_count, v_table_count;
END $$;

-- Verify branch system works
SELECT * FROM vcs_branch_list();
SELECT vcs_get_active_branch() AS current_branch;

-- ============================================================
-- STEP 0.5: RESET VCS DATA (for re-running the demo)
-- ============================================================
SELECT '========================================' AS "STEP 0.5: Cleanup Previous Demo Data";

DO $$
DECLARE
    tbl RECORD;
    v_has_data BOOLEAN;
BEGIN
    -- Check if this is a fresh run or re-run
    SELECT EXISTS(SELECT 1 FROM vcs_commit WHERE commit_id > 1) INTO v_has_data;
    
    IF v_has_data THEN
        RAISE NOTICE 'Detected existing VCS data. Cleaning up for fresh demo run...';
        
        -- ========== 1. Stop tracking all tables (removes triggers) ==========
        FOR tbl IN (SELECT table_name FROM vcs_repository WHERE is_active = TRUE)
        LOOP
            EXECUTE format('DROP TRIGGER IF EXISTS vcs_track_%I ON %I', tbl.table_name, tbl.table_name);
        END LOOP;
        
        -- ========== 2. Clear all VCS metadata ==========
        TRUNCATE TABLE vcs_tag CASCADE;
        TRUNCATE TABLE vcs_staged_change CASCADE;
        TRUNCATE TABLE vcs_change CASCADE;
        TRUNCATE TABLE vcs_commit_parent CASCADE;
        DELETE FROM vcs_commit WHERE commit_id > 1;  -- Keep genesis commit
        DELETE FROM vcs_branch WHERE branch_name != 'main';
        TRUNCATE TABLE vcs_repository CASCADE;
        UPDATE vcs_config SET value = 'main' WHERE key = 'active_branch';
        
        -- ========== 3. Clean up banking data added by demo ==========
        -- Delete in FK-safe order (children first)
        DELETE FROM ai_predictions WHERE prediction_id = 'PRED009';
        DELETE FROM loan_current WHERE loan_id = 'LOAN009';
        DELETE FROM account WHERE account_id = 'ACC013';
        DELETE FROM transaction WHERE txn_id = 'TXN016';
        DELETE FROM customer_financials WHERE customer_id = 'CUST011';
        DELETE FROM customer WHERE customer_id = 'CUST011';
        DELETE FROM employee WHERE emp_id = 'EMP011';
        
        -- ========== 4. Restore rows modified by demo to original seed values ==========
        -- CUST001 financials (Step 3 changes credit_score & annual_income)
        UPDATE customer_financials
        SET credit_score = 750, annual_income = 68000.00, last_updated = '2024-02-20 10:00:00'
        WHERE customer_id = 'CUST001';
        
        -- CUST003 customer name (Step 9 sets it to 'WRONG NAME')
        UPDATE customer SET full_name = 'Noah Thompson'
        WHERE customer_id = 'CUST003';
        
        -- CUST008 contact info (Step 9 corrupts phone & email)
        UPDATE customer SET phone = '555-1008', email = 'ava.l@email.com'
        WHERE customer_id = 'CUST008';
        
        -- CUST006 financials (Step 5 updates credit_score & income, but
        -- CUST006 has no seed financials row - delete if demo created one)
        DELETE FROM customer_financials WHERE customer_id = 'CUST006';
        
        RAISE NOTICE '✅ VCS data + banking demo data reset complete. Ready for fresh demo run.';
    ELSE
        RAISE NOTICE '✅ Fresh installation detected. No cleanup needed.';
    END IF;
END $$;

-- ============================================================
-- STEP 1: REGISTER TABLES FOR TRACKING (git init per table)
-- ============================================================
SELECT '========================================' AS "STEP 1: Init Tracking";

-- NOTE: You may see INFO messages like 'trigger "vcs_track_*" does not exist, skipping'
-- These are harmless - it's just PostgreSQL saying the triggers don't exist yet (first run)

SELECT vcs_init('customer');
SELECT vcs_init('customer_financials');
SELECT vcs_init('account');
SELECT vcs_init('loan_current');
SELECT vcs_init('branch');
SELECT vcs_init('employee');
SELECT vcs_init('transaction');
SELECT vcs_init('ai_models');
SELECT vcs_init('ai_predictions');
SELECT vcs_init('dataset_versions');

-- Verify tracked tables
SELECT table_name, primary_key_column, tracked_since 
FROM vcs_repository WHERE is_active = TRUE;

-- ============================================================
-- STEP 2: SNAPSHOT BASELINE (git add . && git commit -m "...")
-- Take a full snapshot of the current database state.
-- This becomes our "v1.0" baseline.
-- ============================================================
SELECT '========================================' AS "STEP 2: Baseline Snapshot";

SELECT vcs_snapshot_all('v1.0 - Initial banking database baseline');

-- Tag this as v1.0
SELECT vcs_tag_create('v1.0', NULL, 'Initial production release');

-- See the commit log
SELECT * FROM vcs_log();

-- ============================================================
-- STEP 3: MAKE CHANGES ON MAIN BRANCH & COMMIT
-- Scenario: A new customer joins, opens an account, and 
-- an existing customer gets a credit score update.
-- ============================================================
SELECT '========================================' AS "STEP 3: Changes on main";

-- 3a. New customer signs up
INSERT INTO customer VALUES
('CUST011', 'Daniel Kim', '1994-02-14', 'Male', '555-1011', 
 'daniel.k@email.com', '123 River St, NY', NOW());

INSERT INTO customer_financials (customer_id, credit_score, annual_income, employment_status, total_debt, last_updated)
VALUES ('CUST011', 720, 75000.00, 'Employed', 3000.00, NOW());

-- 3b. New account for the customer
INSERT INTO account VALUES
('ACC013', 'CUST011', 'Savings', 10000.00, CURRENT_DATE, 'Active', 'BR001', 'EMP001');

-- 3c. Update existing customer credit score (CUST001 got a raise)
UPDATE customer_financials 
SET credit_score = 780, annual_income = 85000.00, last_updated = NOW()
WHERE customer_id = 'CUST001';

-- Check staged changes (git status)
SELECT '--- Staged Changes (git status) ---' AS info;
SELECT * FROM vcs_status();

-- Commit these changes
SELECT vcs_commit('Add new customer CUST011 + update CUST001 financials', 'alice_admin');

-- ============================================================
-- STEP 4: CREATE A FEATURE BRANCH
-- Scenario: Dev team wants to test a new loan product
-- in isolation before merging to main.
-- ============================================================
SELECT '========================================' AS "STEP 4: Create Feature Branch";

SELECT vcs_branch_create('feature/new-loan-product', NULL, 'Testing premium loan product', TRUE);

-- Verify we're on the new branch
SELECT vcs_get_active_branch() AS current_branch;
SELECT * FROM vcs_branch_list();

-- ============================================================
-- STEP 5: MAKE CHANGES ON THE FEATURE BRANCH
-- These changes are isolated from main.
-- ============================================================
SELECT '========================================' AS "STEP 5: Feature Branch Changes";

-- 5a. Create a premium loan for CUST006 (Sophia Robinson)
INSERT INTO loan_current VALUES
('LOAN009', 'CUST006', 75000.00, 5.50, 120000.00, 15, 'EMP002', 'Current', NOW());

-- 5b. Add a prediction for this loan
INSERT INTO ai_predictions VALUES
('PRED009', 'LOAN009', 'MODEL004', 0.93, 'Premium customer - excellent profile');

-- 5c. Update CUST006 financials
UPDATE customer_financials 
SET credit_score = 800, annual_income = 120000.00, last_updated = NOW()
WHERE customer_id = 'CUST006';

-- Check status & commit on feature branch
SELECT * FROM vcs_status();
SELECT vcs_commit('Add premium loan product for CUST006', 'dev_team');

-- Tag the feature work
SELECT vcs_tag_create('feature-loan-v1', NULL, 'First version of premium loan feature');

-- ============================================================
-- STEP 6: SWITCH BACK TO MAIN & MAKE PARALLEL CHANGES
-- Simulates concurrent development happening on main.
-- ============================================================
SELECT '========================================' AS "STEP 6: Parallel Changes on Main";

SELECT vcs_checkout('main');

-- 6a. A payment comes in on main
INSERT INTO transaction VALUES
('TXN016', 'Deposit', 15000.00, NOW(), 'ACC007', NULL);

-- 6b. New employee hired
INSERT INTO employee VALUES
('EMP011', 'BR001', 'Karen White', 'Analyst', 65000.00, CURRENT_DATE);

-- Commit on main
SELECT * FROM vcs_status();
SELECT vcs_commit('New transaction TXN016 + hire EMP011', 'bob_ops');

-- ============================================================
-- STEP 7: VIEW HISTORY, DIFFS, AND BLAME
-- ============================================================
SELECT '========================================' AS "STEP 7: History & Diffs";

-- 7a. Full commit log on main
SELECT '--- Commit Log (main) ---' AS info;
SELECT * FROM vcs_log('main');

-- 7b. Full commit log across ALL branches
SELECT '--- Commit Log (all branches) ---' AS info;
SELECT * FROM vcs_log_all();

-- 7c. Show details of a specific commit (the latest on main)
SELECT '--- Show Latest Commit ---' AS info;
SELECT * FROM vcs_show(vcs_get_head_commit('main'));

-- 7d. Diff between two commits (v1.0 baseline -> HEAD)
SELECT '--- Diff: Baseline → Current ---' AS info;
SELECT * FROM vcs_diff(
    (SELECT commit_id FROM vcs_tag WHERE tag_name = 'v1.0'),
    vcs_get_head_commit('main')
);

-- 7e. Diff between branches
SELECT '--- Branch Diff: feature vs main ---' AS info;
SELECT * FROM vcs_diff_branch('feature/new-loan-product', 'main');

-- 7f. Blame: who last changed each customer row
SELECT '--- Blame: customer table ---' AS info;
SELECT * FROM vcs_blame('customer');

-- 7g. Row history: track changes to CUST001 financials
SELECT '--- Row History: CUST001 financials ---' AS info;
SELECT * FROM vcs_row_history('customer_financials', 'CUST001');

-- 7h. List all tags
SELECT '--- Tags ---' AS info;
SELECT * FROM vcs_tag_list();

-- ============================================================
-- STEP 8: MERGE FEATURE BRANCH INTO MAIN
-- ============================================================
SELECT '========================================' AS "STEP 8: Merge";

-- First, verify we're on main
SELECT vcs_get_active_branch() AS current_branch;

-- Check for conflicts before merge
SELECT '--- Conflict Check ---' AS info;
SELECT * FROM vcs_merge_conflicts('feature/new-loan-product', 'main');

-- Perform the merge
SELECT vcs_merge('feature/new-loan-product');

-- View the merge commit in the log
SELECT * FROM vcs_log('main', 5);

-- Tag the merge as v1.1
SELECT vcs_tag_create('v1.1', NULL, 'Merged premium loan feature');

-- ============================================================
-- STEP 9: SIMULATE A BAD CHANGE & ROLLBACK
-- ============================================================
SELECT '========================================' AS "STEP 9: Rollback Demo";

-- Record HEAD before the bad change
SELECT '--- HEAD before bad change ---' AS info;
SELECT vcs_get_head_commit() AS safe_commit_id;

-- 9a. Oops! Someone accidentally corrupts customer data
UPDATE customer SET full_name = 'WRONG NAME' WHERE customer_id = 'CUST003';

-- 9b. And accidentally sets a phone number incorrectly
UPDATE customer SET phone = '000-0000', email = 'error@error.com' WHERE customer_id = 'CUST008';

-- Commit the bad changes
SELECT vcs_commit('Accidental data corruption', 'intern_oops');

-- 9c. See what happened
SELECT '--- Log after bad commit ---' AS info;
SELECT * FROM vcs_log('main', 5);

-- 9d. DRY RUN rollback first (see what would happen)
-- We rollback to the commit BEFORE the bad one
-- (The safe commit is the one just before the latest)
SELECT '--- Dry Run Rollback ---' AS info;
SELECT vcs_rollback(
    (SELECT commit_id FROM vcs_commit 
     WHERE branch_name = 'main' 
     ORDER BY committed_at DESC OFFSET 1 LIMIT 1),
    NULL, TRUE  -- dry_run = TRUE
);

-- 9e. Actually perform the rollback
SELECT '--- Performing Rollback ---' AS info;
SELECT vcs_rollback(
    (SELECT commit_id FROM vcs_commit 
     WHERE branch_name = 'main' 
     ORDER BY committed_at DESC OFFSET 1 LIMIT 1)
);

-- 9f. Verify the data is restored
SELECT '--- Verify: CUST003 name restored ---' AS info;
SELECT customer_id, full_name FROM customer WHERE customer_id = 'CUST003';

SELECT '--- Verify: CUST008 contact restored ---' AS info;
SELECT customer_id, full_name, phone, email FROM customer WHERE customer_id = 'CUST008';

-- Tag the recovery
SELECT vcs_tag_create('v1.1.1-recovery', NULL, 'Rolled back accidental changes');

-- ============================================================
-- STEP 10: TIME TRAVEL - VIEW DATA AT ANY POINT IN HISTORY
-- ============================================================
SELECT '========================================' AS "STEP 10: Time Travel";

-- 10a. What did the customer table look like at v1.0?
SELECT '--- Customer table at v1.0 baseline ---' AS info;
SELECT * FROM vcs_time_travel('customer', 
    (SELECT commit_id FROM vcs_tag WHERE tag_name = 'v1.0')
);

-- 10b. Reconstruct a specific row at a specific commit
SELECT '--- CUST001 financials at baseline ---' AS info;
SELECT vcs_reconstruct_at('customer_financials', 'CUST001',
    (SELECT commit_id FROM vcs_tag WHERE tag_name = 'v1.0')
) AS state_at_v1;

-- ============================================================
-- STEP 11: FINAL SUMMARY
-- ============================================================
SELECT '========================================' AS "STEP 11: Final Summary";

-- All branches
SELECT '--- All Branches ---' AS info;
SELECT * FROM vcs_branch_list();

-- Complete commit history
SELECT '--- Full Commit History ---' AS info;
SELECT * FROM vcs_log_all();

-- All tags
SELECT '--- All Tags ---' AS info;
SELECT * FROM vcs_tag_list();

-- Tracked tables
SELECT '--- Tracked Tables ---' AS info;
SELECT table_name, primary_key_column, tracked_since FROM vcs_repository;

-- Statistics
SELECT '--- VCS Statistics ---' AS info;
SELECT 
    (SELECT COUNT(*) FROM vcs_commit) AS total_commits,
    (SELECT COUNT(*) FROM vcs_change) AS total_changes,
    (SELECT COUNT(*) FROM vcs_branch WHERE is_active) AS active_branches,
    (SELECT COUNT(*) FROM vcs_tag) AS tags,
    (SELECT COUNT(*) FROM vcs_repository WHERE is_active) AS tracked_tables;

SELECT '✅ Demo walkthrough complete! All Git-like versioning features demonstrated.' AS status;
