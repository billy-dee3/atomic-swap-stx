# Atomic Swap STX Contract

A Clarity smart contract implementing Hash Time Locked Contract (HTLC) functionality for atomic swaps on the Stacks blockchain.

## Overview

This contract enables trustless atomic swaps of STX tokens using hashlocks and timelocks. It allows two parties to exchange assets across different chains without requiring trust between participants.

## Features

- Create atomic swaps with STX tokens
- Secure hashlock using SHA256
- Timelock functionality with block height
- Claim mechanism with preimage verification
- Refund capability after timelock expiration
- View functions for swap status and verification

## Functions

### Core Operations

```clarity
(create-swap (recipient principal) (hashlock (buff 32)) (timelock uint))
(claim (id uint) (preimage (buff 32)))
(refund (id uint))
```

### View Functions

```clarity
(get-swap-info (id uint))
(verify-preimage (id uint) (preimage (buff 32)))
(swap-exists? (id uint))
```

## Error Codes

- `ERR-BAD-ARGS (u100)`: Invalid arguments provided
- `ERR-NOT-FOUND (u101)`: Swap not found
- `ERR-UNAUTHORIZED (u102)`: Unauthorized access
- `ERR-ALREADY (u103)`: Swap already claimed/refunded
- `ERR-TOO-EARLY (u104)`: Too early for refund
- `ERR-TOO-LATE (u105)`: Too late for claim
- `ERR-INSUFFICIENT (u106)`: Insufficient funds

## Usage

1. Initiator creates swap with recipient address, hashlock, and timelock
2. Recipient claims STX by providing the correct preimage
3. If unclaimed before timelock, initiator can refund the STX

## Development

- Built with Clarity v3
- Tested with Clarinet
- Follows Stacks best practices
