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

# Nem 15

Fixed

# Nem 16

Aknowledged.

# Nem 17

Aknowledged. We are not using `Clone2` so pools should not be deployed at the same addresses. Since the signature includes the pool address, the signature will not be the same.

# Nem 18

Aknowledged.

# Nem 19

Aknowledged.

# Nem 20

Fixed. Change solidity version to 0.8.19

# Nem 21

Aknowledged.

# Nem 22

Fixed

# Nem 23

Our interest rate mechanism intentionally differs from Compound's. We believe it's logical to diverge from Compound's approach due to significant differences in loan characteristics between the two protocols.

Compound operates as a perpetual lending protocol, where loans have no set completion date and interest accrues daily. In such a scenario, an algorithmic interest rate mechanism is necessary to encourage borrowers to repay their loans promptly during liquidity shortages.

In contrast, our loans have a predetermined repayment schedule, typically 90 days. This structure provides liquidity providers (LPs) with visibility into available liquidity. Also, our fixed-rate design aims to enhance user-friendliness. Borrowers know exactly in advance how much they will repay, simplifying the borrowing process. In the event of a liquidity shortage, new LPs may adjust future loan rates upward, thereby restoring equilibrium between supply and demand.
