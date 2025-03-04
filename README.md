# Chamber Protocol: Liquid Staking Protocol

A Sui Move implementation of a liquid staking protocol for the Sui network.

## Overview

Chamber Finance allows users to stake their SUI tokens and receive liquid stSUI tokens in return. These stSUI tokens automatically appreciate in value as staking rewards accrue, without requiring any manual claiming or management.

## Key Features

- **Liquid Staking**: Stake SUI and receive stSUI tokens
- **Auto-compounding Rewards**: stSUI value increases automatically as rewards accrue
- **No Lockups**: Maintain liquidity while earning staking rewards
- **Multi-validator Support**: Distribute stake across multiple validators
- **Configurable Protocol Fees**: Adjustable fee structure for protocol sustainability

## Architecture

The protocol consists of several interconnected modules:

- **Core Modules**
  - `stake`: Manages staking operations
  - `treasury`: Handles SUI token custody
  - `config`: Stores protocol configuration

- **Token Modules**
  - `csui`: Implements the stSUI token
  - `rewards`: Manages reward distribution

- **Logic Modules**
  - `exchange`: Calculates exchange rates
  - `math`: Library for precise calculations
  - `validation`: Input validation

## Getting Started

### Prerequisites

- Sui CLI
- Move compiler

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/chamber-finance.git
cd chamber-finance

# Build the package
sui move build

# Run tests
sui move test
```

## Testing

The protocol includes comprehensive end-to-end tests that simulate:

1. Protocol initialization
2. Validator configuration
3. User staking
4. Rewards distribution
5. Exchange rate updates

Run the tests with:

```bash
sui move test -u end_to_end_test
```

## License

[MIT](LICENSE)
