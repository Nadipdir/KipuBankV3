// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";
// FIX: Added console import
import {console} from "forge-std/console.sol";

contract DeployKipuBankV3 is Script {
    // Sepolia Addresses
    address constant USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant WETH_SEPOLIA = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address constant ROUTER_V2_SEPOLIA = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;

    // Bank Configuration (in 6 decimals for USDC)
    // Example: 1,000,000 USDC Cap
    uint256 constant BANK_CAP_USD = 1_000_000 * (10**6);
    // Example: 1,000 USDC Max Withdrawal
    uint256 constant MAX_WITHDRAWAL_USD = 1_000 * (10**6);

    function run() external returns (KipuBankV3) {
        // Get the owner from your private key
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        if (deployer == address(0)) {
            revert("Missing DEPLOYER_ADDRESS env var");
        }

        vm.startBroadcast(deployer);

        KipuBankV3 kipuBankV3 = new KipuBankV3(
            deployer, // _owner
            USDC_SEPOLIA, // _usdcAddress
            WETH_SEPOLIA, // _wethAddress
            ROUTER_V2_SEPOLIA, // _routerAddress
            BANK_CAP_USD, // _bankCapUSD
            MAX_WITHDRAWAL_USD // _maxWithdrawalPerTxUSD
        );

        vm.stopBroadcast();

        console.log("KipuBankV3 deployed at:", address(kipuBankV3));
        return kipuBankV3;
    }
}