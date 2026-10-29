-- Banking Management System using PL/SQL
-- Educational demonstration for Oracle SQL Developer (Run Script / F5).
-- Run once in a new, empty Oracle user schema. This script does not drop objects.

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- 1. Sequences
CREATE SEQUENCE bank_customer_seq START WITH 1001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE bank_account_seq START WITH 5001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE bank_transaction_seq START WITH 9001 INCREMENT BY 1 NOCACHE;

-- 2. Tables and integrity constraints
CREATE TABLE bank_customers (
    customer_id NUMBER(10) CONSTRAINT pk_bank_customers PRIMARY KEY,
    full_name   VARCHAR2(100) NOT NULL,
    email       VARCHAR2(120) NOT NULL CONSTRAINT uq_bank_customer_email UNIQUE,
    phone       VARCHAR2(20),
    created_on  DATE DEFAULT SYSDATE NOT NULL
);

CREATE TABLE bank_accounts (
    account_id     NUMBER(10) CONSTRAINT pk_bank_accounts PRIMARY KEY,
    customer_id    NUMBER(10) NOT NULL,
    account_type   VARCHAR2(10) NOT NULL,
    balance        NUMBER(12,2) DEFAULT 0 NOT NULL,
    account_status VARCHAR2(10) DEFAULT 'ACTIVE' NOT NULL,
    opened_on      DATE DEFAULT SYSDATE NOT NULL,
    CONSTRAINT fk_account_customer FOREIGN KEY (customer_id)
        REFERENCES bank_customers(customer_id),
    CONSTRAINT ck_account_type CHECK (account_type IN ('SAVINGS', 'CURRENT')),
    CONSTRAINT ck_account_status CHECK (account_status IN ('ACTIVE', 'INACTIVE')),
    CONSTRAINT ck_account_balance CHECK (balance >= 0)
);

CREATE TABLE bank_transactions (
    transaction_id   NUMBER(10) CONSTRAINT pk_bank_transactions PRIMARY KEY,
    account_id       NUMBER(10) NOT NULL,
    transaction_type VARCHAR2(15) NOT NULL,
    amount           NUMBER(12,2) NOT NULL,
    transaction_date DATE DEFAULT SYSDATE NOT NULL,
    description      VARCHAR2(200),
    CONSTRAINT fk_transaction_account FOREIGN KEY (account_id)
        REFERENCES bank_accounts(account_id),
    CONSTRAINT ck_transaction_type CHECK (
        transaction_type IN ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER_IN', 'TRANSFER_OUT')
    ),
    CONSTRAINT ck_transaction_amount CHECK (amount > 0)
);

CREATE INDEX ix_accounts_customer ON bank_accounts(customer_id);
CREATE INDEX ix_transactions_account_date
    ON bank_transactions(account_id, transaction_date);

-- 3. Validate every ledger entry before it is stored.
CREATE OR REPLACE TRIGGER trg_transaction_validate
BEFORE INSERT ON bank_transactions
FOR EACH ROW
DECLARE
    v_balance NUMBER(12,2);
    v_status  bank_accounts.account_status%TYPE;
BEGIN
    IF :NEW.amount IS NULL OR :NEW.amount <= 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Amount must be greater than zero.');
    END IF;

    SELECT balance, account_status
      INTO v_balance, v_status
      FROM bank_accounts
     WHERE account_id = :NEW.account_id
       FOR UPDATE;

    IF v_status <> 'ACTIVE' THEN
        RAISE_APPLICATION_ERROR(-20003, 'Account is inactive.');
    END IF;

    IF :NEW.transaction_type IN ('WITHDRAWAL', 'TRANSFER_OUT')
       AND v_balance < :NEW.amount THEN
        RAISE_APPLICATION_ERROR(-20002, 'Insufficient funds.');
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20004, 'Account does not exist.');
END;
/

-- 4. Keep the account balance in step with the transaction ledger.
CREATE OR REPLACE TRIGGER trg_transaction_apply_balance
AFTER INSERT ON bank_transactions
FOR EACH ROW
BEGIN
    UPDATE bank_accounts
       SET balance = balance +
           CASE :NEW.transaction_type
               WHEN 'DEPOSIT'      THEN :NEW.amount
               WHEN 'TRANSFER_IN'  THEN :NEW.amount
               WHEN 'WITHDRAWAL'   THEN -:NEW.amount
               WHEN 'TRANSFER_OUT' THEN -:NEW.amount
           END
     WHERE account_id = :NEW.account_id;
END;
/

-- 5. Procedures and function
CREATE OR REPLACE PROCEDURE sp_open_account (
    p_customer_id  IN  NUMBER,
    p_account_type IN  VARCHAR2,
    p_account_id   OUT NUMBER
)
IS
    v_customer_exists NUMBER;
BEGIN
    IF p_account_type IS NULL OR UPPER(p_account_type) NOT IN ('SAVINGS', 'CURRENT') THEN
        RAISE_APPLICATION_ERROR(-20005, 'Type must be SAVINGS or CURRENT.');
    END IF;

    SELECT 1
      INTO v_customer_exists
      FROM bank_customers
     WHERE customer_id = p_customer_id;

    INSERT INTO bank_accounts
        (account_id, customer_id, account_type, balance, account_status, opened_on)
    VALUES
        (bank_account_seq.NEXTVAL, p_customer_id, UPPER(p_account_type), 0, 'ACTIVE', SYSDATE)
    RETURNING account_id INTO p_account_id;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20004, 'Customer does not exist.');
END;
/

CREATE OR REPLACE PROCEDURE sp_deposit (
    p_account_id IN NUMBER,
    p_amount     IN NUMBER,
    p_note       IN VARCHAR2 DEFAULT 'Cash deposit'
)
IS
BEGIN
    INSERT INTO bank_transactions
        (transaction_id, account_id, transaction_type, amount, description)
    VALUES
        (bank_transaction_seq.NEXTVAL, p_account_id, 'DEPOSIT', p_amount, p_note);
END;
/

CREATE OR REPLACE PROCEDURE sp_withdraw (
    p_account_id IN NUMBER,
    p_amount     IN NUMBER,
    p_note       IN VARCHAR2 DEFAULT 'Cash withdrawal'
)
IS
BEGIN
    INSERT INTO bank_transactions
        (transaction_id, account_id, transaction_type, amount, description)
    VALUES
        (bank_transaction_seq.NEXTVAL, p_account_id, 'WITHDRAWAL', p_amount, p_note);
END;
/

CREATE OR REPLACE PROCEDURE sp_transfer (
    p_from_account IN NUMBER,
    p_to_account   IN NUMBER,
    p_amount       IN NUMBER,
    p_note         IN VARCHAR2 DEFAULT 'Account transfer'
)
IS
    v_from_status bank_accounts.account_status%TYPE;
    v_to_status   bank_accounts.account_status%TYPE;
BEGIN
    IF p_from_account IS NULL OR p_to_account IS NULL THEN
        RAISE_APPLICATION_ERROR(-20004, 'Both account numbers are required.');
    END IF;

    IF p_from_account = p_to_account THEN
        RAISE_APPLICATION_ERROR(-20006, 'Source and destination must differ.');
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Amount must be greater than zero.');
    END IF;

    SAVEPOINT transfer_start;
    BEGIN
        -- Lock both accounts in numeric order to reduce transfer deadlocks.
        IF p_from_account < p_to_account THEN
            SELECT account_status INTO v_from_status FROM bank_accounts
             WHERE account_id = p_from_account FOR UPDATE;
            SELECT account_status INTO v_to_status FROM bank_accounts
             WHERE account_id = p_to_account FOR UPDATE;
        ELSE
            SELECT account_status INTO v_to_status FROM bank_accounts
             WHERE account_id = p_to_account FOR UPDATE;
            SELECT account_status INTO v_from_status FROM bank_accounts
             WHERE account_id = p_from_account FOR UPDATE;
        END IF;

        IF v_from_status <> 'ACTIVE' OR v_to_status <> 'ACTIVE' THEN
            RAISE_APPLICATION_ERROR(-20003, 'Both accounts must be active.');
        END IF;

        INSERT INTO bank_transactions
            (transaction_id, account_id, transaction_type, amount, description)
        VALUES
            (bank_transaction_seq.NEXTVAL, p_from_account, 'TRANSFER_OUT', p_amount, p_note);

        INSERT INTO bank_transactions
            (transaction_id, account_id, transaction_type, amount, description)
        VALUES
            (bank_transaction_seq.NEXTVAL, p_to_account, 'TRANSFER_IN', p_amount, p_note);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK TO transfer_start;
            RAISE_APPLICATION_ERROR(-20004, 'Source or destination account does not exist.');
        WHEN OTHERS THEN
            ROLLBACK TO transfer_start;
            RAISE;
    END;
END;
/

CREATE OR REPLACE FUNCTION fn_get_balance (
    p_account_id IN NUMBER
)
RETURN NUMBER
IS
    v_balance NUMBER(12,2);
BEGIN
    SELECT balance
      INTO v_balance
      FROM bank_accounts
     WHERE account_id = p_account_id;

    RETURN v_balance;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20004, 'Account does not exist.');
END;
/

-- 6. Fictional sample data. Phone values are omitted for the public-ready copy.
INSERT INTO bank_customers (customer_id, full_name, email, phone)
VALUES (bank_customer_seq.NEXTVAL, 'Arjun Mehta', 'arjun@example.com', NULL);
INSERT INTO bank_customers (customer_id, full_name, email, phone)
VALUES (bank_customer_seq.NEXTVAL, 'Neha Verma', 'neha@example.com', NULL);

INSERT INTO bank_accounts (account_id, customer_id, account_type, balance, account_status)
VALUES (bank_account_seq.NEXTVAL, 1001, 'SAVINGS', 0, 'ACTIVE');
INSERT INTO bank_accounts (account_id, customer_id, account_type, balance, account_status)
VALUES (bank_account_seq.NEXTVAL, 1002, 'SAVINGS', 0, 'ACTIVE');

-- 7. Demonstration: deposit 5,000; withdraw 1,200; transfer 700; then commit.
BEGIN
    sp_deposit(5001, 5000, 'Opening deposit');
    sp_withdraw(5001, 1200, 'ATM withdrawal');
    sp_transfer(5001, 5002, 700, 'Transfer to Neha');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Demo transactions committed successfully.');
END;
/

-- 8. A failed withdrawal is caught and printed; it must not change either balance.
BEGIN
    sp_withdraw(5002, 10000, 'Insufficient-funds demonstration');
    DBMS_OUTPUT.PUT_LINE('Unexpected: withdrawal succeeded.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Expected rejection: ' || SQLERRM);
        ROLLBACK;
END;
/

-- 9. Review the results. Expected balances: account 5001 = 3,100; account 5002 = 700.
SELECT account_id, customer_id, account_type, balance, account_status
  FROM bank_accounts
 ORDER BY account_id;

SELECT transaction_id, account_id, transaction_type, amount, description
  FROM bank_transactions
 ORDER BY transaction_id;

-- Function example: SELECT fn_get_balance(5001) AS balance FROM dual;
