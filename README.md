# KipuBankV3 Smart Contract Project

This repository contains the smart contract and deployment files for the **KipuBankV3** project. This is an advanced non-custodial DeFi savings protocol built with **Solidity** and **Foundry**.

The contract accepts user deposits of ETH or any ERC20 token, automatically swaps them to **USDC** via the **Uniswap V2 Router**, and manages all internal balances in USDC. This implementation fulfills all requirements for TP4 and incorporates all corrective feedback from TP2 and TP3.

The contract has been successfully deployed and verified on the **Sepolia Testnet**.

---

## 🚀 Deployment Status

| Network | Contract Name | Contract Address | Status |
| :--- | :--- | :--- | :--- |
| **Sepolia** | `KipuBankV3` | **0x93b9e12bcb9B1F3b112c280C8B08c21c9b9DB2e3** | Verified |

**View the Verified Code on SepoliaScan:**
[https://sepolia.etherscan.io/address/0x93b9e12bcb9B1F3b112c280C8B08c21c9b9DB2e3#code](https://sepolia.etherscan.io/address/0x93b9e12bcb9B1F3b112c280C8B08c21c9b9DB2e3#code)

---

## 📋 Technical Details

### Contract Functions

The KipuBankV3 contract includes the following core functions:

| Function | Visibility | Description |
| :--- | :--- | :--- |
| `depositEth()` | `public payable` | Accepts native ETH, wraps it to WETH, and swaps it for USDC. |
| `depositUsdc(uint256 _amount)` | `external` | The most efficient method. Deposits USDC directly. |
| `depositToken(address _token, uint256 _amount)` | `external` | Accepts any other ERC20 token and swaps it for USDC. |
| `withdrawUsdc(uint256 _amount)` | `external` | Allows users to withdraw their USDC balance, subject to transaction limits. |
| `getBalance(address _user)` | `external view` | Returns the USDC balance for a specific user. |
| `getTotalUsdcInBank()` | `external view` | Returns the total USDC balance held by the contract. |
| `getBankCap()` | `external view` | Returns the maximum USDC capacity of the bank. |
| `emergencyWithdrawEth()` | `external` | (Owner Only) Rescues any native ETH stuck in the contract. |
| `emergencyWithdrawToken(address _token)` | `external` | (Owner Only) Rescues any ERC20 token stuck in the contract. |

### Constructor Arguments

The contract was deployed with the following initial parameters (defined in `script/DeployKipuBankV3.s.sol`):

| Parameter | Value | Description |
| :--- | :--- | :--- |
| `_owner` | `0x1e9d66...6cc6aa` | The address of the contract deployer and owner. |
| `_usdcAddress` | `0x1c7D4B...379C7238` | The address of the USDC token contract on Sepolia. |
| `_wethAddress` | `0xfFf997...2324d6B14` | The address of the WETH contract on Sepolia. |
| `_routerAddress` | `0xC532a7...ad7694008` | The address of the Uniswap V2 Router on Sepolia. |
| `_bankCapUsd` | `1000000000000` | **1,000,000 USDC** (1M * 10^6 decimals). The bank's total capacity. |
| `_maxWithdrawalPerTxUsd` | `1000000000` | **1,000 USDC** (1k * 10^6 decimals). Max withdrawal per transaction. |

---

## ⚙️ Development Environment & Execution

This project was built using the **Foundry** development environment and **Solidity 0.8.26**.

### Installation

1.  Clone the repository:
    ```bash
    git clone YOUR_REPO_URL_HERE
    cd KipuBankV3
    ```

2.  Install dependencies:
    ```bash
    forge install
    ```

3.  Configure the `.env` file with your `SEPOLIA_RPC_URL`, `PRIVATE_KEY`, `DEPLOYER_ADDRESS`, and `ETHERSCAN_API_KEY`.

### Execution Commands

| Task | Command | Description |
| :--- | :--- | :--- |
| **Compile** | `forge build` | Compiles the Solidity contracts. |
| **Test** | `forge test` | Runs the Forge tests defined in the `test/` directory. |
| **Coverage** | `forge coverage` | Runs the test suite and generates a coverage report. |
| **Deploy** | `forge script script/DeployKipuBankV3.s.sol --network sepolia --broadcast` | Deploys the contract to Sepolia. |
| **Verify** | `forge verify-contract ...` | Verifies the code on SepoliaScan. (See below for full cmd). |

**Full Verification Command:**
```bash
# First, get the ABI-encoded args
ABI_ENCODED_ARGS=$(cast abi-encode "constructor(address,address,address,address,uint256,uint256)" $DEPLOYER_ADDRESS 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008 1000000000000 1000000000)

# Then, run verify
forge verify-contract --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY 0x93b9e12bcb9B1F3b112c280C8B08c21c9b9DB2e3 src/KipuBankV3.sol:KipuBankV3 --constructor-args ${ABI_ENCODED_ARGS#0x}
```
**Test Coverage**

The test suite achieves **78.67%** line coverage on the main `src/KipuBankV3.sol` contract, successfully exceeding the 50% requirement for the assignment.

The tests include both unit tests (using a `MockERC20`) and fork tests (using a Sepolia fork to test live swaps with `depositEth`).

**Coverage Report Output:**
|File|% Lines|% Statements|% Branches|% Funcs|
| :--- | :--- | :--- | :--- | :--- |
|script/DeployKipuBankV3.s.sol|0.00% (0/9)|0.00% (0/10)|0.00% (0/1)|0.00% (0/1)|
|src/KipuBankV3.sol|78.67% (59/75)|80.88% (55/68)|60.00% (6/10)|73.33% (11/15)|
|Total|70.24% (59/84)|70.51% (55/78)|54.55% (6/11)|68.75% (11/16)|

**Design Decisions & Trade-offs**
(As required by TP4)

1. **USDC as Base Asset:**
    - **Decision:** All assets are converted to USDC.
    - **Trade-off:** This simplifies `bankCap` and balance logic immensely. However, it forces the user to accept the swap price and exposes the protocol to USDC smart contract risk.
2. **Uniswap V2 Router**:
    - **Decision:** Used the standard V2 router for swaps.
    - Trade-off: V2 is battle-tested and has deep liquidity. We did not use V3, which is more gas-efficient but requires complex liquidity management (range orders) that is overkill for this contract's purpose.
3. **Slippage Protection:**
    - Decision: The `amountOutMin` parameter in `swapExactTokensForTokens` is set to `0`.
    - Trade-off: This was a major simplification for the assignment. In a production environment, this is critically unsafe and exposes users to 100% slippage (front-running / sandwich attacks). A production version must calculate an acceptable `amountOutMin` based on an oracle price feed.

## Threat Analysis & Protocol Maturity
(As required by TP4)

This contract is **NOT production-ready.**

**Identified Weaknesses**
1. **Critical: No Slippage Protection:** As noted above, setting amountOutMin to 0 allows an attacker to steal the full value of a deposit.
2. **No Token Whitelist:** The `depositToken` function accepts any token address. An attacker could create a fake, valueless token and exploit the protocol. A production contract must use a whitelist of known, reputable tokens (e.G., DAI, WETH, WBTC).
3. **Price Impact Risk:** A user depositing a very large amount of an illiquid token could receive a terrible swap rate, resulting in a large loss of funds.
4. **Centralization Risk:** The `owner` (inherited from OpenZeppelin) has the ability to drain all funds from the contract using the emergency functions. This is a single point of failure.

**Steps to Maturity**
1. **Implement Slippage Control:** Integrate a Chainlink oracle to get the "fair" price of TokenA/USDC. Use this price to calculate a realistic `amountOutMin` (e.g., fair price - 0.5% slippage) for the swap.
2. **Implement Token Whitelist:** Add owner-only functions to manage a `mapping(address => bool) public isTokenAllowed`. The `depositToken` function must `revert` if `isTokenAllowed(_token) == false`.
3. **Decentralize Ownership:** Transfer ownership from a single EOA (Externally Owned Account) to a `MultiSig` (like Gnosis Safe) or a full DAO governance contract.