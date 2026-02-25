-- ============================================================
-- BANKING & AI VERSIONING SYSTEM - POSTGRESQL VERSION
-- ============================================================

-- 1. CLEANUP (Using CASCADE to handle dependencies automatically)
-- ============================================================
DROP TABLE IF EXISTS governance_decisions CASCADE;
DROP TABLE IF EXISTS ai_model_features CASCADE;
DROP TABLE IF EXISTS ai_predictions CASCADE;
DROP TABLE IF EXISTS ai_models CASCADE;
DROP TABLE IF EXISTS dataset_versions CASCADE;
DROP TABLE IF EXISTS loan_payment CASCADE;
DROP TABLE IF EXISTS loan_history CASCADE;
DROP TABLE IF EXISTS loan_current CASCADE;
DROP TABLE IF EXISTS transaction CASCADE;
DROP TABLE IF EXISTS account CASCADE;
DROP TABLE IF EXISTS customer_financials_history CASCADE;
DROP TABLE IF EXISTS customer_financials CASCADE;
DROP TABLE IF EXISTS customer CASCADE;
DROP TABLE IF EXISTS employee CASCADE;
DROP TABLE IF EXISTS branch CASCADE;

-- ============================================================
-- 2. SCHEMA CREATION (DDL)
-- ============================================================

-- A. CORE BANKING ENTITIES
CREATE TABLE branch (
    branch_id VARCHAR(10) PRIMARY KEY,
    branch_name VARCHAR(50),
    location VARCHAR(100),
    ifsc_code VARCHAR(20)
);

CREATE TABLE employee (
    emp_id VARCHAR(10) PRIMARY KEY,
    branch_id VARCHAR(10),
    name VARCHAR(50),
    role VARCHAR(30),
    salary DECIMAL(10, 2),
    hire_date DATE,
    FOREIGN KEY (branch_id) REFERENCES branch(branch_id)
);

-- B. CUSTOMER & VERSIONING
CREATE TABLE customer (
    customer_id VARCHAR(10) PRIMARY KEY,
    full_name VARCHAR(50),
    dob DATE,
    gender VARCHAR(10),
    phone VARCHAR(15),
    email VARCHAR(50),
    address VARCHAR(100),
    created_at TIMESTAMP
);

-- Changed AUTO_INCREMENT to SERIAL
CREATE TABLE customer_financials (
    fin_id SERIAL PRIMARY KEY, 
    customer_id VARCHAR(10),
    credit_score INT,
    annual_income DECIMAL(15, 2),
    employment_status VARCHAR(20),
    total_debt DECIMAL(15, 2),
    last_updated TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id)
);

-- Changed AUTO_INCREMENT to SERIAL
CREATE TABLE customer_financials_history (
    history_id SERIAL PRIMARY KEY,
    customer_id VARCHAR(10),
    credit_score INT,
    annual_income DECIMAL(15, 2),
    employment_status VARCHAR(20),
    total_debt DECIMAL(15, 2),
    valid_from TIMESTAMP,
    valid_to TIMESTAMP, 
    change_reason VARCHAR(100),
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id)
);

CREATE TABLE account (
    account_id VARCHAR(10) PRIMARY KEY,
    customer_id VARCHAR(10),
    account_type VARCHAR(20),
    balance DECIMAL(15, 2),
    opened_date DATE,
    status VARCHAR(15), 
    branch_id VARCHAR(10),
    opened_by_emp_id VARCHAR(10),
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
    FOREIGN KEY (branch_id) REFERENCES branch(branch_id),
    FOREIGN KEY (opened_by_emp_id) REFERENCES employee(emp_id)
);

CREATE TABLE transaction (
    txn_id VARCHAR(10) PRIMARY KEY,
    txn_type VARCHAR(20), 
    amount DECIMAL(15, 2),
    txn_time TIMESTAMP,
    account_id VARCHAR(10),
    related_account_id VARCHAR(10), 
    FOREIGN KEY (account_id) REFERENCES account(account_id)
);

-- C. LENDING & LOAN VERSIONING
CREATE TABLE loan_current (
    loan_id VARCHAR(10) PRIMARY KEY,
    borrower_id VARCHAR(10),
    loan_amount DECIMAL(15, 2),
    interest_rate DECIMAL(5, 2),
    application_income DECIMAL(15, 2), 
    employment_length INT,
    approved_by_emp_id VARCHAR(10),
    loan_status VARCHAR(20), 
    updated_at TIMESTAMP,
    FOREIGN KEY (borrower_id) REFERENCES customer(customer_id),
    FOREIGN KEY (approved_by_emp_id) REFERENCES employee(emp_id)
);

CREATE TABLE loan_history (
    history_id VARCHAR(10) PRIMARY KEY,
    loan_id VARCHAR(10),
    loan_amount DECIMAL(15, 2),
    loan_status VARCHAR(20),
    valid_from TIMESTAMP,
    valid_to TIMESTAMP,
    FOREIGN KEY (loan_id) REFERENCES loan_current(loan_id)
);

CREATE TABLE loan_payment (
    payment_id VARCHAR(10) PRIMARY KEY,
    loan_id VARCHAR(10),
    amount_paid DECIMAL(15, 2),
    payment_date DATE,
    remaining_balance DECIMAL(15, 2),
    FOREIGN KEY (loan_id) REFERENCES loan_current(loan_id)
);

-- D. AI MODELS & AUDITABILITY
CREATE TABLE dataset_versions (
    dataset_version_id VARCHAR(10) PRIMARY KEY,
    created_at TIMESTAMP,
    description VARCHAR(100),
    drift_score DECIMAL(5, 4),
    approved BOOLEAN
);

CREATE TABLE ai_models (
    model_id VARCHAR(10) PRIMARY KEY,
    dataset_version_id VARCHAR(10),
    algorithm VARCHAR(50),
    accuracy DECIMAL(5, 4),
    auc DECIMAL(5, 4),
    trained_at TIMESTAMP,
    FOREIGN KEY (dataset_version_id) REFERENCES dataset_versions(dataset_version_id)
);

CREATE TABLE ai_predictions (
    prediction_id VARCHAR(10) PRIMARY KEY,
    loan_id VARCHAR(10),
    model_id VARCHAR(10),
    predicted_score DECIMAL(5, 4), 
    decision_reason VARCHAR(150),
    FOREIGN KEY (loan_id) REFERENCES loan_current(loan_id),
    FOREIGN KEY (model_id) REFERENCES ai_models(model_id)
);

-- Changed AUTO_INCREMENT to SERIAL
CREATE TABLE ai_model_features (
    feature_id SERIAL PRIMARY KEY,
    prediction_id VARCHAR(10),
    feature_name VARCHAR(50),
    feature_value VARCHAR(50),
    FOREIGN KEY (prediction_id) REFERENCES ai_predictions(prediction_id)
);

CREATE TABLE governance_decisions (
    decision_id VARCHAR(10) PRIMARY KEY,
    model_id VARCHAR(10),
    reviewed_by_emp_id VARCHAR(10),
    performance_ok BOOLEAN,
    fairness_ok BOOLEAN,
    drift_ok BOOLEAN,
    final_decision VARCHAR(20),
    decision_time TIMESTAMP,
    FOREIGN KEY (model_id) REFERENCES ai_models(model_id),
    FOREIGN KEY (reviewed_by_emp_id) REFERENCES employee(emp_id)
);

-- ============================================================
-- 3. SEED DATA INSERTION (DML)
-- ============================================================

-- 1. Branch
INSERT INTO branch VALUES
('BR001', 'Downtown Central', 'New York, NY', 'BANK0BR001'),
('BR002', 'Westside Branch', 'Los Angeles, CA', 'BANK0BR002'),
('BR003', 'North Park Branch', 'Chicago, IL', 'BANK0BR003'),
('BR004', 'East End Branch', 'Houston, TX', 'BANK0BR004'),
('BR005', 'Midtown Branch', 'Phoenix, AZ', 'BANK0BR005');

-- 2. Employee
INSERT INTO employee VALUES
('EMP001', 'BR001', 'Alice Johnson', 'Branch Manager', 95000.00, '2018-03-15'),
('EMP002', 'BR001', 'Bob Martinez', 'Loan Officer', 72000.00, '2019-07-22'),
('EMP003', 'BR002', 'Carol Williams', 'Branch Manager', 93000.00, '2017-11-01'),
('EMP004', 'BR002', 'David Lee', 'Loan Officer', 70000.00, '2020-02-14'),
('EMP005', 'BR003', 'Eva Brown', 'Branch Manager', 91000.00, '2016-05-30'),
('EMP006', 'BR003', 'Frank Davis', 'Teller', 48000.00, '2021-08-10'),
('EMP007', 'BR004', 'Grace Wilson', 'Loan Officer', 71000.00, '2019-12-05'),
('EMP008', 'BR004', 'Henry Moore', 'Branch Manager', 90000.00, '2015-09-20'),
('EMP009', 'BR005', 'Irene Taylor', 'Teller', 47000.00, '2022-01-17'),
('EMP010', 'BR005', 'James Anderson', 'Branch Manager', 92000.00, '2018-06-25');

-- 3. Customer (Static)
INSERT INTO customer VALUES
('CUST001', 'Liam Harris', '1990-04-12', 'Male', '555-1001', 'liam.h@email.com', '12 Maple St, NY', '2020-01-10 09:00:00'),
('CUST002', 'Olivia Martin', '1985-09-23', 'Female', '555-1002', 'olivia.m@email.com', '34 Oak Ave, CA', '2020-03-15 10:30:00'),
('CUST003', 'Noah Thompson', '1992-07-07', 'Male', '555-1003', 'noah.t@email.com', '56 Pine Rd, IL', '2019-11-20 14:00:00'),
('CUST004', 'Emma Garcia', '1988-12-30', 'Female', '555-1004', 'emma.g@email.com', '78 Birch Blvd, TX', '2021-06-05 08:45:00'),
('CUST005', 'William Martinez', '1995-03-18', 'Male', '555-1005', 'william.m@email.com', '90 Cedar Ln, AZ', '2021-02-28 11:15:00'),
('CUST006', 'Sophia Robinson', '1993-08-25', 'Female', '555-1006', 'sophia.r@email.com', '22 Elm St, NY', '2018-07-14 13:00:00'),
('CUST007', 'James Clark', '1980-01-05', 'Male', '555-1007', 'james.c@email.com', '44 Walnut Dr, CA', '2017-09-09 09:30:00'),
('CUST008', 'Ava Lewis', '1997-05-14', 'Female', '555-1008', 'ava.l@email.com', '66 Spruce Ave, IL', '2022-04-01 15:20:00'),
('CUST009', 'Benjamin Walker', '1983-11-11', 'Male', '555-1009', 'ben.w@email.com', '88 Chestnut St, TX', '2019-08-22 10:00:00'),
('CUST010', 'Mia Hall', '1991-06-29', 'Female', '555-1010', 'mia.h@email.com', '100 Poplar Rd, AZ', '2020-10-30 16:45:00');

-- 4. Customer Financials (Current State)
-- Note: We specify columns to allow the SERIAL 'fin_id' to auto-generate
INSERT INTO customer_financials (customer_id, credit_score, annual_income, employment_status, total_debt, last_updated) VALUES
('CUST001', 750, 68000.00, 'Employed', 4500.00, '2024-02-20 10:00:00'),
('CUST002', 680, 47000.00, 'Self-Employed', 12000.00, '2024-02-15 09:00:00'),
('CUST003', 710, 82000.00, 'Employed', 15000.00, '2024-01-10 14:00:00'),
('CUST004', 620, 58000.00, 'Employed', 25000.00, '2023-12-05 11:30:00'),
('CUST005', 580, 42000.00, 'Unemployed', 8000.00, '2024-01-20 08:15:00');

-- 5. Customer Financials History (The "Time Travel" Data)
-- Note: We specify columns to allow the SERIAL 'history_id' to auto-generate
INSERT INTO customer_financials_history (customer_id, credit_score, annual_income, employment_status, total_debt, valid_from, valid_to, change_reason) VALUES
('CUST001', 700, 55000.00, 'Employed', 6000.00, '2020-01-10 09:00:00', '2022-06-01 08:59:59', 'Initial Profile'),
('CUST001', 720, 60000.00, 'Employed', 5500.00, '2022-06-01 09:00:00', '2024-02-20 09:59:59', 'Promotion'),
('CUST004', 700, 58000.00, 'Employed', 5000.00, '2021-06-05 08:45:00', '2023-01-01 10:00:00', 'Initial Profile'),
('CUST004', 650, 58000.00, 'Employed', 18000.00, '2023-01-01 10:00:01', '2023-12-05 11:29:59', 'Took Personal Loan');

-- 6. Account
INSERT INTO account VALUES
('ACC001', 'CUST001', 'Savings', 15000.00, '2020-01-12', 'Active', 'BR001', 'EMP001'),
('ACC002', 'CUST001', 'Checking', 3200.50, '2020-01-12', 'Active', 'BR001', 'EMP001'),
('ACC003', 'CUST002', 'Savings', 42000.00, '2020-03-16', 'Active', 'BR002', 'EMP003'),
('ACC004', 'CUST003', 'Checking', 8750.75, '2019-11-21', 'Active', 'BR003', 'EMP005'),
('ACC005', 'CUST004', 'Savings', 25000.00, '2021-06-06', 'Active', 'BR004', 'EMP008'),
('ACC006', 'CUST005', 'Checking', 1200.00, '2021-03-01', 'Active', 'BR005', 'EMP010'),
('ACC007', 'CUST006', 'Savings', 60000.00, '2018-07-15', 'Active', 'BR001', 'EMP001'),
('ACC008', 'CUST007', 'Checking', 18500.00, '2017-09-10', 'Active', 'BR002', 'EMP003'),
('ACC009', 'CUST008', 'Savings', 5000.00, '2022-04-02', 'Active', 'BR003', 'EMP006'),
('ACC010', 'CUST009', 'Checking', 9300.25, '2019-08-23', 'Active', 'BR004', 'EMP007'),
('ACC011', 'CUST010', 'Savings', 31000.00, '2020-10-31', 'Active', 'BR005', 'EMP010'),
('ACC012', 'CUST002', 'Checking', 2100.00, '2021-01-10', 'Closed', 'BR002', 'EMP004');

-- 7. Transaction
INSERT INTO transaction VALUES
('TXN001', 'Deposit', 5000.00, '2024-01-05 09:10:00', 'ACC001', NULL),
('TXN002', 'Withdrawal', 1000.00, '2024-01-10 11:20:00', 'ACC001', NULL),
('TXN003', 'Transfer', 2000.00, '2024-01-15 14:00:00', 'ACC001', 'ACC002'),
('TXN004', 'Deposit', 10000.00, '2024-01-20 10:00:00', 'ACC003', NULL),
('TXN005', 'Withdrawal', 500.00, '2024-02-01 08:30:00', 'ACC004', NULL),
('TXN006', 'Transfer', 3000.00, '2024-02-05 12:00:00', 'ACC005', 'ACC006'),
('TXN007', 'Deposit', 8000.00, '2024-02-10 15:45:00', 'ACC007', NULL),
('TXN008', 'Withdrawal', 2500.00, '2024-02-14 09:00:00', 'ACC008', NULL),
('TXN009', 'Deposit', 1500.00, '2024-02-20 13:30:00', 'ACC009', NULL),
('TXN010', 'Transfer', 4000.00, '2024-03-01 10:15:00', 'ACC010', 'ACC011'),
('TXN011', 'Withdrawal', 750.00, '2024-03-05 16:00:00', 'ACC002', NULL),
('TXN012', 'Deposit', 6000.00, '2024-03-10 11:00:00', 'ACC011', NULL),
('TXN013', 'Transfer', 1200.00, '2024-03-15 14:30:00', 'ACC003', 'ACC004'),
('TXN014', 'Withdrawal', 3000.00, '2024-03-20 09:45:00', 'ACC007', NULL),
('TXN015', 'Deposit', 2200.00, '2024-04-01 08:00:00', 'ACC005', NULL);

-- 8. Loan Current
INSERT INTO loan_current VALUES
('LOAN001', 'CUST001', 20000.00, 7.50, 65000.00, 5, 'EMP002', 'Current', '2023-01-15 10:00:00'),
('LOAN002', 'CUST003', 35000.00, 8.00, 80000.00, 8, 'EMP004', 'Current', '2023-03-20 11:00:00'),
('LOAN003', 'CUST005', 10000.00, 9.50, 42000.00, 2, 'EMP007', 'Default', '2023-06-01 09:30:00'),
('LOAN004', 'CUST006', 50000.00, 6.75, 95000.00, 12, 'EMP002', 'Current', '2022-11-05 14:00:00'),
('LOAN005', 'CUST009', 15000.00, 8.25, 55000.00, 4, 'EMP007', 'Paid Off', '2024-01-30 16:00:00'),
('LOAN006', 'CUST002', 25000.00, 7.00, 72000.00, 7, 'EMP004', 'Current', '2023-09-10 10:30:00'),
('LOAN007', 'CUST004', 40000.00, 9.00, 60000.00, 3, 'EMP002', 'Default', '2023-07-22 13:00:00'),
('LOAN008', 'CUST007', 30000.00, 7.25, 85000.00, 10, 'EMP007', 'Current', '2022-05-18 09:00:00');

-- 9. Loan History
INSERT INTO loan_history VALUES
('HIST001', 'LOAN001', 20000.00, 'Pending', '2023-01-01 00:00:00', '2023-01-15 09:59:59'),
('HIST002', 'LOAN001', 20000.00, 'Current', '2023-01-15 10:00:00', NULL),
('HIST003', 'LOAN002', 35000.00, 'Pending', '2023-03-10 00:00:00', '2023-03-20 10:59:59'),
('HIST004', 'LOAN002', 35000.00, 'Current', '2023-03-20 11:00:00', NULL),
('HIST005', 'LOAN003', 10000.00, 'Pending', '2023-05-20 00:00:00', '2023-06-01 09:29:59'),
('HIST006', 'LOAN003', 10000.00, 'Current', '2023-06-01 09:30:00', '2023-09-01 00:00:00'),
('HIST007', 'LOAN003', 10000.00, 'Default', '2023-09-01 00:00:00', NULL),
('HIST008', 'LOAN004', 50000.00, 'Current', '2022-11-05 14:00:00', NULL),
('HIST009', 'LOAN005', 15000.00, 'Current', '2023-06-01 00:00:00', '2024-01-30 15:59:59'),
('HIST010', 'LOAN005', 15000.00, 'Paid Off', '2024-01-30 16:00:00', NULL);

-- 10. Loan Payment
INSERT INTO loan_payment VALUES
('PAY001', 'LOAN001', 500.00, '2023-02-15', 19500.00),
('PAY002', 'LOAN001', 500.00, '2023-03-15', 19000.00),
('PAY003', 'LOAN001', 500.00, '2023-04-15', 18500.00),
('PAY004', 'LOAN002', 800.00, '2023-04-20', 34200.00),
('PAY005', 'LOAN002', 800.00, '2023-05-20', 33400.00),
('PAY006', 'LOAN003', 300.00, '2023-07-01', 9700.00),
('PAY007', 'LOAN004', 1200.00, '2022-12-05', 48800.00),
('PAY008', 'LOAN004', 1200.00, '2023-01-05', 47600.00),
('PAY009', 'LOAN004', 1200.00, '2023-02-05', 46400.00),
('PAY010', 'LOAN005', 800.00, '2023-09-30', 14200.00),
('PAY011', 'LOAN005', 800.00, '2023-10-30', 13400.00),
('PAY012', 'LOAN005', 800.00, '2023-11-30', 12600.00),
('PAY013', 'LOAN006', 700.00, '2023-10-10', 24300.00),
('PAY014', 'LOAN006', 700.00, '2023-11-10', 23600.00),
('PAY015', 'LOAN008', 900.00, '2022-06-18', 29100.00);

-- 11. Dataset Versions
INSERT INTO dataset_versions VALUES
('DV001', '2022-06-01 08:00:00', 'Initial training dataset v1.0', 0.02, TRUE),
('DV002', '2023-01-15 09:00:00', 'Updated dataset with 2022 loans', 0.05, TRUE),
('DV003', '2023-07-01 10:00:00', 'Mid-year refresh with default cases', 0.08, TRUE),
('DV004', '2024-01-10 11:00:00', 'Annual dataset refresh v4.0', 0.04, TRUE),
('DV005', '2024-06-01 12:00:00', 'Experimental dataset - high drift', 0.18, FALSE);

-- 12. AI Models
INSERT INTO ai_models VALUES
('MODEL001', 'DV001', 'Logistic Regression', 0.82, 0.85, '2022-06-10 14:00:00'),
('MODEL002', 'DV002', 'Random Forest', 0.87, 0.90, '2023-01-25 15:00:00'),
('MODEL003', 'DV003', 'Gradient Boosting', 0.89, 0.92, '2023-07-15 16:00:00'),
('MODEL004', 'DV004', 'XGBoost', 0.91, 0.94, '2024-01-20 10:00:00'),
('MODEL005', 'DV005', 'Neural Network', 0.88, 0.91, '2024-06-10 11:00:00');

-- 13. AI Predictions
INSERT INTO ai_predictions VALUES
('PRED001', 'LOAN001', 'MODEL003', 0.78, 'Good credit history and stable income'),
('PRED002', 'LOAN002', 'MODEL003', 0.82, 'Long employment, strong income'),
('PRED003', 'LOAN003', 'MODEL003', 0.41, 'Short employment, lower income, high DTI'),
('PRED004', 'LOAN004', 'MODEL004', 0.91, 'Excellent income, long employment history'),
('PRED005', 'LOAN005', 'MODEL004', 0.74, 'Moderate income, satisfactory credit history'),
('PRED006', 'LOAN006', 'MODEL004', 0.80, 'Stable employment, moderate debt load'),
('PRED007', 'LOAN007', 'MODEL004', 0.38, 'Low employment length, moderate income risk'),
('PRED008', 'LOAN008', 'MODEL004', 0.85, 'High income, long tenure, low default risk');

-- 14. AI Model Features (SNAPSHOTS for Auditing)
-- We specify columns so the SERIAL feature_id is auto-filled
INSERT INTO ai_model_features (prediction_id, feature_name, feature_value) VALUES
('PRED001', 'Annual_Income', '65000'),
('PRED001', 'Credit_Score', '750'),
('PRED001', 'Employment_Length', '5'),
('PRED003', 'Annual_Income', '42000'),
('PRED003', 'Credit_Score', '580'),
('PRED003', 'Employment_Length', '2');

-- 15. Governance Decisions
INSERT INTO governance_decisions VALUES
('GOV001', 'MODEL001', 'EMP001', TRUE, TRUE, TRUE, 'Approved', '2022-06-15 10:00:00'),
('GOV002', 'MODEL002', 'EMP003', TRUE, TRUE, TRUE, 'Approved', '2023-01-30 11:00:00'),
('GOV003', 'MODEL003', 'EMP005', TRUE, TRUE, TRUE, 'Approved', '2023-07-20 12:00:00'),
('GOV004', 'MODEL004', 'EMP008', TRUE, TRUE, TRUE, 'Approved', '2024-01-25 09:30:00'),
('GOV005', 'MODEL005', 'EMP010', TRUE, FALSE, FALSE, 'Rejected', '2024-06-15 14:00:00')