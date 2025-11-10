// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// We must import the specific test file we want to fork
import {Test, console} from "forge-std/Test.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";

/**
 * @title KipuBankV3 Fork Test Suite
 * @notice This suite tests the swap-related functionalities (depositEth)
 * by forking the Sepolia testnet.
 */
contract KipuBankV3ForkTest is Test {
    // =============================================================================
    //                                  STATE
    // =============================================================================

    KipuBankV3 internal bank;
    IERC20 internal usdc;
    IWETH internal weth;

    // These are the REAL Sepolia addresses
    address internal constant USDC_ADDRESS = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address internal constant WETH_ADDRESS = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address internal constant ROUTER_ADDRESS = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;

    // Bank configuration
    uint256 internal constant BANK_CAP = 1_000_000 * (10**6); // 1M USDC
    uint256 internal constant MAX_WITHDRAWAL = 1_000 * (10**6); // 1k USDC

    // Test users
    address internal constant OWNER = address(0x1); // The test contract
    address internal constant USER_A = address(0xA); // A random user

    // =============================================================================
    //                                  SETUP
    // =============================================================================

    function setUp() public {
        // --- This is a Fork Test ---
        // We are on a fork of Sepolia. The contracts (USDC, WETH, Router)
        // already exist. We just need to deploy our *own* contract.

        // 1. Deploy our bank (KipuBankV3) as OWNER
        vm.prank(OWNER);
        bank = new KipuBankV3(
            OWNER,
            USDC_ADDRESS,
            WETH_ADDRESS,
            ROUTER_ADDRESS,
            BANK_CAP,
            MAX_WITHDRAWAL
        );

        // 2. Get interfaces to the *existing* tokens on the fork
        usdc = IERC20(USDC_ADDRESS);
        weth = IWETH(WETH_ADDRESS);

        // 3. Give USER_A 10 "test" ETH to deposit
        // We use the 'deal' cheatcode for native ETH
        vm.deal(USER_A, 10 ether);
    }

    // =============================================================================
    //                                  FORK TEST
    // =============================================================================

    /**
     * @notice Tests a successful deposit of 1 native ETH.
     * This test will wrap the ETH to WETH, call the real Uniswap router,
     * swap WETH for USDC, and credit the user's balance.
     */
    function test_Fork_DepositETH_Success() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        uint256 userUsdcBalance_Before = bank.getBalance(USER_A);
        uint256 userEthBalance_Before = USER_A.balance;

        // Act
        // Simulate the user calling the function
        vm.prank(USER_A);
        bank.depositEth{value: depositAmount}();

        // Assert
        uint256 userUsdcBalance_After = bank.getBalance(USER_A);
        uint256 bankUsdcBalance_After = bank.getTotalUsdcInBank();
        uint256 userEthBalance_After = USER_A.balance;

        // 1. Check that the user's USDC balance in the bank increased.
        // We use `assertGt` (Greater Than) because the exact swap amount is dynamic.
        assertGt(userUsdcBalance_After, userUsdcBalance_Before, "User USDC balance should have increased");

        // 2. Check that the bank's total USDC matches the user's balance.
        assertEq(userUsdcBalance_After, bankUsdcBalance_After, "Bank total USDC mismatch");

        // 3. Check that the user's ETH balance decreased by 1 ETH.
        assertEq(userEthBalance_After, userEthBalance_Before - depositAmount, "User ETH balance did not decrease correctly");

        // 4. (Sanity Check) Check that the bank has no leftover WETH.
        // FIX: The IWETH interface does not include `balanceOf`.
        // We must cast the WETH_ADDRESS to the IERC20 interface to call balanceOf.
        assertEq(IERC20(WETH_ADDRESS).balanceOf(address(bank)), 0, "Bank should not hold any WETH after swap");
    }
}