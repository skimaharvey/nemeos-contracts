# NEM 1

- Added a `MIN_VESTING_TIME` of two days to prevent this issue

# NEM 2

The key modification involves dynamically calculating the `nextPaymentTime` based on the remaining duration of the loan at the time of payment, rather than adding a fixed interval. This ensures that the extension granted for repayment does not exceed the original loan duration, maintaining the integrity of the loan's terms and conditions.

# Nem 3

Overrided `transferFrom` and applied the vesting logic there

# NEM 4

Overrided `transfer` and applied the vesting logic there

# NEM 5

Removed `collectionAddress_` and usig `msg.sender` instead

# NEM 6

Made `NFT` a `non-transferable` token

# NEM 7

See `Nemeos_floor.pdf`for the floor calculation

# Nem 8

Aknowledged. Extremely unlikely considering a `SLOAD`cost 5k and max block limit is over 30M.

# Nem 9

Added however we are following the check-effect pattern so we were fine before.

# Nem 10

Transfered the excess amount back to the sender

# Nem 11

Not valid anymore as we are now passing `msg.sender` to the signature

# Nem 12

We can not do that as we needed to turn some variables from `private` to `internal`.

# Nem 13

Aknowledged.

# Nem 14

Aknowledged.
