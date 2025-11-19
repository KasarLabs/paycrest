# Paycrest Gateway 🌉

A Cairo smart contract for Paycrest protocol, an escrow bridge for cross-platform payments.

## Key Features

- **Escrow Management**: Users deposit tokens into the contract, which holds them safely in escrow until the order is either settled or refunded.

- **Flexible Settlement**: Orders can be settled partially or fully by liquidity providers.

- **Smart Refund System**: the aggregator can refund your order. The refund fee is capped at the protocol fee.

- **Multi-Token Support**: The contract works with any ERC20 token that's been whitelisted by the protocol.

- **Rate Type Safety**: The `rate` parameter in `create_order` uses `u128` (compatible with Solidity's `uint96`)

- **Dynamic Fee Structure**: Supports both local (same currency) and FX (foreign exchange) transfers with token-specific fee configurations and optional rebates for liquidity providers.

## Key Components

- **Gateway.cairo**: The main contract handling orders, settlements, and refunds
- **GatewaySettingManager.cairo**: Manages protocol settings (fees, supported tokens, treasury address, etc.)
- **IGateway.cairo**: The interface defining how external apps interact with the Gateway

Run `scarb build`

## Security Features

- **Two-Step Ownership Transfer**: Uses OpenZeppelin's `OwnableTwoStep` pattern - the owner proposes a new owner, and the new owner must explicitly accept to prevent accidental transfers
- Owner-controlled settings (only the owner can change fees or whitelist tokens)
- Aggregator-only settlement and refund functions (only trusted aggregators can process orders)
- Emergency pause mechanism 
- Built-in protection against double settlements and double refunds

## Testing

Includes a comprehensive test suite with 49 tests covering using snforge :
- Order creation and escrow mechanics (local and FX transfers)
- Partial and full settlements with precise BPS arithmetic
- Refund flows with fee validation
- Access control and security checks
- Pause/unpause emergency functionality
- Contract upgradeability and access control
- Two-step ownership transfer mechanism
- Rate parameter type validation (u128 enforcement)
- Token-specific fee settings configuration
- Rebate mechanism for liquidity providers
- Fee splitting for local and FX transfers

Run `scarb test`