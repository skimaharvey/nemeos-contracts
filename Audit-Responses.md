# NEM 1

- Added a `MIN_VESTING_TIME` of two days to prevent this issue

# NEM 2

The key modification involves dynamically calculating the `nextPaymentTime` based on the remaining duration of the loan at the time of payment, rather than adding a fixed interval. This ensures that the extension granted for repayment does not exceed the original loan duration, maintaining the integrity of the loan's terms and conditions.

# Nem 3

Overrided `transferFrom` and applied the vesting logic there

# NEM 4
