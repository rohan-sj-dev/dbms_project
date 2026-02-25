-- ============================================================
-- RESET VCS SYSTEM - Clean slate for demo re-runs
-- ============================================================
-- This script clears all VCS tracking data without dropping
-- the banking tables or VCS functions. Use this to reset
-- the demo to initial state.
-- ============================================================

-- Stop tracking all tables (removes triggers)
DO $$
DECLARE
    tbl RECORD;
BEGIN
    FOR tbl IN (SELECT table_name FROM vcs_repository WHERE is_active = TRUE)
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS vcs_track_%I ON %I', tbl.table_name, tbl.table_name);
    END LOOP;
END $$;

-- Clear all VCS data (preserves structure, removes content)
TRUNCATE TABLE vcs_tag CASCADE;
TRUNCATE TABLE vcs_staged_change CASCADE;
TRUNCATE TABLE vcs_change CASCADE;
TRUNCATE TABLE vcs_commit_parent CASCADE;
TRUNCATE TABLE vcs_commit CASCADE;
TRUNCATE TABLE vcs_branch CASCADE;
TRUNCATE TABLE vcs_repository CASCADE;

-- Reset configuration
DELETE FROM vcs_config;
INSERT INTO vcs_config (key, value) VALUES 
    ('active_branch', 'main'),
    ('auto_track', 'true');

-- Recreate default main branch
INSERT INTO vcs_branch (branch_name, description) 
VALUES ('main', 'Default branch - production state');

-- Recreate genesis commit
INSERT INTO vcs_commit (branch_name, commit_hash, message, author)
VALUES ('main', md5('genesis-' || NOW()::TEXT), 'Initial commit - system initialized', CURRENT_USER);

-- Clean up banking data added by the demo
-- Delete demo-inserted rows (FK-safe order)
DELETE FROM ai_predictions WHERE prediction_id = 'PRED009';
DELETE FROM loan_current WHERE loan_id = 'LOAN009';
DELETE FROM account WHERE account_id = 'ACC013';
DELETE FROM transaction WHERE txn_id = 'TXN016';
DELETE FROM customer_financials WHERE customer_id IN ('CUST011', 'CUST006');
DELETE FROM customer WHERE customer_id = 'CUST011';
DELETE FROM employee WHERE emp_id = 'EMP011';

-- Restore demo-modified rows to original seed values
UPDATE customer_financials
SET credit_score = 750, annual_income = 68000.00, last_updated = '2024-02-20 10:00:00'
WHERE customer_id = 'CUST001';

UPDATE customer SET full_name = 'Noah Thompson'
WHERE customer_id = 'CUST003';

UPDATE customer SET phone = '555-1008', email = 'ava.l@email.com'
WHERE customer_id = 'CUST008';

SELECT '✅ VCS system reset complete. All tracking data + demo data cleared.' AS status;
