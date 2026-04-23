-- Init all the tables
SELECT vcs_init('branch');
SELECT vcs_init('department');
SELECT vcs_init('employee');
SELECT vcs_init('employee_hr_update');
SELECT vcs_init('customer');
SELECT vcs_init('account');
SELECT vcs_init('transaction');
SELECT vcs_init('fund_transfer');
SELECT vcs_init('loan');

-- Confirm all tables are tracked
SELECT * FROM vcs_repository ORDER BY repo_id;

-- Snapshot all existing data as the baseline commit

SELECT vcs_snapshot_all('v1.0 baseline — Kottayam Branch initial state');

SELECT vcs_tag_create('v1.0', NULL, 'Initial data captured');

SELECT * FROM vcs_log();

-- Add a new customer (Vivek Chandran)

DO $$
DECLARE
    v_cust_id  INT;
    v_acct_id  INT;
BEGIN
    -- Insert customer, capture real customer_id
    INSERT INTO customer (
        branch_id, assigned_rm_id, full_name, dob, gender,
        phone, email, occupation, income_bracket,
        aadhaar_number, pan_number,
        kyc_status, kyc_verified_by, kyc_verified_on,
        customer_since, status
    ) VALUES (
        1, 2, 'Vivek Chandran', '1992-09-27', 'M',
        '9876543220', 'vivek.c@email.com', 'Chartered Accountant', '10L_25L',
        '123456781007', 'PQRVC9012G',
        'verified', 4, CURRENT_DATE,
        CURRENT_DATE, 'active'
    ) RETURNING customer_id INTO v_cust_id;

    -- Insert account using the real customer_id
    INSERT INTO account (
        customer_id, branch_id, opened_by,
        account_number, account_type, min_balance, interest_rate,
        opened_date, current_balance, status
    ) VALUES (
        v_cust_id, 1, 2,
        'SB10000000007', 'savings', 1000, 3.50,
        CURRENT_DATE, 10000.00, 'active'
    ) RETURNING account_id INTO v_acct_id;

    -- Insert initial deposit using the real account_id
    INSERT INTO transaction (
        account_id, txn_type, channel, amount, balance_after,
        reference_number, txn_date, description, initiated_by
    ) VALUES (
        v_acct_id, 'credit', 'branch', 10000, 10000,
        'REF20240120001', NOW(), 'Initial deposit — account opening', 4
    );

    RAISE NOTICE 'Vivek Chandran added: customer_id=%, account_id=%', v_cust_id, v_acct_id;
END $$;

-- Staged changes
SELECT table_name, operation, row_pk, changed_columns FROM vcs_status();

-- Commit the adding

SELECT vcs_commit('Added new customer Vivek Chandran with savings account and initial deposit', 'Priya Menon');

-- Change log
SELECT commit_id, hash, message, change_count FROM vcs_log();

-- BRANCHES DEMO

SELECT vcs_branch_create(
    'feature/loan-restructure',
    'main',
    'Restructure Arjun Pillai home loan, approve Meena personal loan',
    TRUE   -- auto checkout
);

-- All branches
SELECT branch, is_current, created_from, commit_count FROM vcs_branch_list();

-- Work on the feature
UPDATE loan SET
    application_status   = 'disbursed',
    sanctioned_amount    = 300000,
    disbursed_amount     = 300000,
    interest_rate        = 11.50,   -- negotiated rate
    tenure_months        = 36,
    emi_amount           = 9885,
    disbursement_date    = CURRENT_DATE,
    maturity_date        = CURRENT_DATE + INTERVAL '36 months',
    outstanding_principal= 300000,
    collateral_type      = 'none',
    status               = 'active'
WHERE loan_id = 3;


-- Credit to Meena's account
INSERT INTO transaction (
    account_id, txn_type, channel, amount, balance_after,
    reference_number, txn_date, description, initiated_by
) VALUES (
    2, 'credit', 'neft', 300000, 322500,
    'REF20240121001', NOW(), 'Personal loan disbursement — LOAN-3', 3
);

-- Commit the approved loan
SELECT vcs_commit('Approved & disbursed personal loan for Meena Suresh', 'Arun Kumar');

-- Restructure Arjun's loan

UPDATE loan SET
    tenure_months        = 300,        -- extended from 240 to 300 months
    emi_amount           = 33150,      -- reduced EMI
    interest_rate        = 8.25,       -- revised rate
    outstanding_principal= 4388000,
    status               = 'active'
WHERE loan_id = 1;


-- Commit the change
SELECT vcs_commit('Restructured home loan LOAN-1 for Arjun Pillai', 'Arun Kumar');


-- Parallel work on the main branch
SELECT vcs_checkout('main');

-- HR update
INSERT INTO employee_hr_update (
    emp_id, update_type, effective_date,
    old_designation, old_dept_id, old_salary, old_emp_type,
    new_designation, new_dept_id, new_salary, new_emp_type,
    reason, authorized_by
) VALUES (
    6, 'employment_type_change', CURRENT_DATE,
    'Credit Analyst', 2, 38000, 'contract',
    'Credit Analyst', 2, 43000, 'permanent',
    'Outstanding appraisal: 4.8/5 — converted to permanent with 13% hike', 1
);

-- Update actual employee
UPDATE employee SET
    employment_type = 'permanent',
    salary          = 43000
WHERE emp_id = 6;

-- Commit the changes
SELECT vcs_commit('HR: Manoj Krishnan converted contract to permanent, salary ₹38K to ₹43K', 'Rajesh Nair');

-- Adjust loan rate
UPDATE loan SET interest_rate = 8.75 WHERE loan_id = 1;
SELECT vcs_commit('RBI rate cap compliance: LOAN-1 rate adjusted to 8.75%', 'Rajesh Nair');

-- Increase savings interest rate
UPDATE account
SET interest_rate = 4.00
WHERE account_type = 'savings' AND status = 'active';

-- Commit the changes
SELECT vcs_commit('RBI policy update: savings account interest rate revised 3.50% → 4.00%', 'Rajesh Nair');

-- Block a dormant account
UPDATE customer SET
    kyc_status = 'expired',
    status     = 'blocked'
WHERE customer_id = 5;
UPDATE account SET status = 'frozen' WHERE customer_id = 5;

-- Commit the changes
SELECT vcs_commit('Compliance: Rajan Varma KYC expired, account frozen pending renewal', 'Suresh Pillai');

-- READ COMMANDS

-- See commit history on main
SELECT commit_id, hash, message, change_count FROM vcs_log('main');

-- See complete commit history
SELECT commit_id, hash, branch, message, change_count, committed_at FROM vcs_log_all(20);

-- See git diff
SELECT table_name, row_pk, operation, changed_columns
FROM vcs_diff(2, vcs_get_head_commit('main'))
ORDER BY table_name, row_pk;

-- See who last changed the loan table(git blame)
SELECT row_pk, last_operation, last_author, last_message, modified_at
FROM vcs_blame('loan', 'feature/loan-restructure');

-- Row history of loan of arjun pillai
SELECT commit_id, branch, operation, changed_columns, committed_at
FROM vcs_row_history('loan', '1');


-- Row history of employee HR update of Manoj Krishnan
SELECT commit_id, branch, operation, changed_columns, committed_at
FROM vcs_row_history('employee_hr_update', '6');

-- Diff between branches
SELECT table_name, row_pk, operation, branch, changed_columns
FROM vcs_diff_branch('feature/loan-restructure', 'main')
ORDER BY table_name;

-- MERGE DEMO

-- Tag current state before merging
SELECT vcs_tag_create('v1.3-pre-merge', NULL, 'Main branch state before loan restructure merge');

-- Tag the feature branch head
SELECT vcs_checkout('feature/loan-restructure');
SELECT vcs_tag_create('feature-loan-restructure-ready', NULL, 'Loan restructure feature complete and ready to merge');
SELECT vcs_checkout('main');

-- All tags
SELECT tag, commit_id, commit_branch, message, created_at FROM vcs_tag_list();

-- Detect conflicts before merging
SELECT * FROM vcs_merge_conflicts('feature/loan-restructure', 'main');

-- Resolve the conflicts
UPDATE loan SET
    tenure_months        = 300,
    emi_amount           = 33150,
    interest_rate        = 8.25
WHERE loan_id = 1;

SELECT vcs_commit('Conflict resolution: align main loan-1 terms with restructure branch before merge', 'Rajesh Nair');

-- Merge the branches
SELECT vcs_merge(
    'feature/loan-restructure',
    'main',
    'Merge feature/loan-restructure: Meena loan approved + Arjun loan restructured'
);

-- Log of main after merge
SELECT commit_id, hash, message, is_merge, change_count FROM vcs_log('main');

-- Tagging post merge change
SELECT vcs_tag_create('v1.2', NULL, 'Post-merge: loan restructure and new customer fully integrated');

-- ROLLBACK DEMO

-- Set Wrong Salary
UPDATE employee SET salary = 999999 WHERE emp_id = 2;
INSERT INTO employee_hr_update (emp_id, update_type, effective_date,old_designation, old_dept_id, old_salary, old_emp_type,new_designation,
 new_dept_id, new_salary, new_emp_type,reason, authorized_by) VALUES (2, 'salary_revision', CURRENT_DATE,'Senior Relationship Manager', 1, 65000, 
    'permanent','Senior Relationship Manager', 1, 999999, 'permanent', 'Wrong amount entered', 1);

-- Commit the wrong changes
SELECT vcs_commit('WRONG: Salary entry error for Priya Menon — ₹999999 (should be ₹68000)', 'Suresh Pillai');

-- The current, wrong salary
SELECT emp_id, full_name, designation, salary FROM employee WHERE emp_id = 2;

SELECT vcs_rollback(vcs_get_head_commit('main') - 1, NULL, TRUE);

-- Get the commit id just before the wrong entry, perform rollback

DO $$
DECLARE
    v_rollback_to INT;
BEGIN
    SELECT commit_id INTO v_rollback_to
    FROM vcs_commit
    WHERE branch_name = 'main'
    ORDER BY commit_id DESC
    OFFSET 1 LIMIT 1;
    RAISE NOTICE 'Rolling back to commit #%', v_rollback_to;
    PERFORM vcs_rollback(v_rollback_to);
END $$;


-- Salary after rollback
SELECT emp_id, full_name, designation, salary FROM employee WHERE emp_id = 2;

-- Commit logs from main
SELECT commit_id, hash, message, change_count FROM vcs_log('main') LIMIT 5;

-- Reconstruct the table as it was in the v1.0
SELECT row_pk, row_state->>'full_name' AS name,
       row_state->>'kyc_status'        AS kyc_status,
       row_state->>'status'            AS status
FROM vcs_time_travel('customer',
    (SELECT commit_id FROM vcs_tag WHERE tag_name = 'v1.0'))
ORDER BY row_pk::INT;

-- Current customer table for comparison
SELECT customer_id, full_name, kyc_status, status FROM customer ORDER BY customer_id;


-- Reconstruct at reconructs just one row
SELECT vcs_reconstruct_at('loan', '1',
    (SELECT commit_id FROM vcs_tag WHERE tag_name = 'v1.0'));

-- Arjun Pillai home loan after restructure
SELECT loan_id, loan_type, interest_rate, tenure_months, emi_amount, status
FROM loan WHERE loan_id = 1;


-- Account interest rate history
SELECT row_pk, row_state->>'account_number' AS account_no,
       row_state->>'account_type'           AS type,
       row_state->>'interest_rate'          AS interest_rate
FROM vcs_time_travel('account',
    (SELECT commit_id FROM vcs_tag WHERE tag_name = 'v1.0'))
ORDER BY row_pk::INT;


-- Current account interest rates
SELECT account_id, account_number, account_type, interest_rate
FROM account ORDER BY account_id;

-- Final states

-- Commits acrros all branches
SELECT commit_id, hash, branch, message, is_merge, change_count, committed_at
FROM vcs_log_all(30);


-- All tags
SELECT tag, commit_id, commit_branch, message FROM vcs_tag_list();

-- All branches
SELECT branch, is_current, created_from, commit_count FROM vcs_branch_list();

--Branch summary
SELECT * FROM branch_summary;


	














