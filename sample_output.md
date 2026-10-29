# Expected sample output

> These values are illustrative expectations from the supplied report and script. They are not captured from a live Oracle SQL Developer session. Run the SQL script in a clean Oracle schema to confirm actual output.

## DBMS_OUTPUT

```text
Demo transactions committed successfully.
Expected rejection: ORA-20002: Insufficient funds.
```

## Final accounts

| ACCOUNT_ID | CUSTOMER_ID | ACCOUNT_TYPE | BALANCE | STATUS |
| ---: | ---: | --- | ---: | --- |
| 5001 | 1001 | SAVINGS | 3100.00 | ACTIVE |
| 5002 | 1002 | SAVINGS | 700.00 | ACTIVE |

## Successful ledger entries

| TRANSACTION_ID | ACCOUNT_ID | TYPE | AMOUNT | DESCRIPTION |
| ---: | ---: | --- | ---: | --- |
| 9001 | 5001 | DEPOSIT | 5000.00 | Opening deposit |
| 9002 | 5001 | WITHDRAWAL | 1200.00 | ATM withdrawal |
| 9003 | 5001 | TRANSFER_OUT | 700.00 | Transfer to Neha |
| 9004 | 5002 | TRANSFER_IN | 700.00 | Transfer to Neha |

IDs assume the script is run once with its initial sequence values in a clean schema. The rejected 10,000 withdrawal is not stored and does not change either balance.
