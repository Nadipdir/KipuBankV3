// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "custom-mocks/MockERC20.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title KipuBankV3 Test Suite
 * @notice This suite performs unit tests on the core non-swap functionalities (deposit/withdraw USDC).
 * This unit test uses a MockUSDC token to isolate the contract.
 */
contract KipuBankV3Test is Test {
    // =============================================================================
    //                                  STATE
    // =============================================================================

    KipuBankV3 internal bank;
    MockERC20 internal usdc;

    // We only need these addresses for the constructor, they don't have to be real.
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
        // 1. Deploy the MockUSDC token
        // (Name, Symbol, Decimals)
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);

        // 2. Deploy the bank (KipuBankV3) as OWNER
        vm.prank(OWNER);
        bank = new KipuBankV3(
            OWNER,
            address(usdc), // Use the mock token's address
            WETH_ADDRESS,  // This address is just stored, not used
            ROUTER_ADDRESS, // This address is just stored, not used
            BANK_CAP,
            MAX_WITHDRAWAL
        );

        // 3. Give 1,000 mock USDC to USER_A to play with
        uint256 initialUserBalance = 1_000 * (10**6); // 1k USDC
        // We use the mock token's .mint() function
        usdc.mint(USER_A, initialUserBalance);
    }

    // =============================================================================
    //                                  EXISTING TESTS
    // =============================================================================

    /**
     * @notice Tests if the owner is set correctly.
     */
    function test_OwnerIsDeployer() public view {
        assertEq(bank.owner(), OWNER);
    }

    /**
     * @notice Tests if the contract reverts when a zero amount is deposited.
     */
    function test_Fail_RevertsOnZeroDeposit() public {
        vm.prank(USER_A);
        // Expect a revert with the specific error
        vm.expectRevert(KipuBankV3.KipuBankV3__ZeroAmount.selector);
        bank.depositUsdc(0);
    }

    /**
     * @notice Tests a successful USDC deposit.
     */
    function test_DepositUSDC_Success() public {
        // Arrange
        uint256 depositAmount = 500 * (10**6); // 500 USDC
        uint256 expectedBankTotal = depositAmount;
        uint256 expectedUserBalance = depositAmount;
        uint256 expectedUserTokenBalance = (1_000 * (10**6)) - depositAmount; // 500 USDC

        // Act
        // 1. USER_A must approve the bank to spend their USDC
        vm.prank(USER_A);
        usdc.approve(address(bank), depositAmount);

        // 2. USER_A deposits the USDC
        vm.prank(USER_A);
        bank.depositUsdc(depositAmount);

        // Assert
        assertEq(bank.getBalance(USER_A), expectedUserBalance, "Bank internal balance mismatch");
        assertEq(bank.getTotalUsdcInBank(), expectedBankTotal, "Bank total balance mismatch");
        assertEq(usdc.balanceOf(USER_A), expectedUserTokenBalance, "User token balance mismatch");
        assertEq(usdc.balanceOf(address(bank)), expectedBankTotal, "Contract token balance mismatch");
    }

    /**
     * @notice Tests a successful USDC withdrawal.
     */
    function test_WithdrawUSDC_Success() public {
        // Arrange: First, deposit 500 USDC as in the previous test
        uint256 depositAmount = 500 * (10**6);
        vm.prank(USER_A);
        usdc.approve(address(bank), depositAmount);
        vm.prank(USER_A);
        bank.depositUsdc(depositAmount);

        // Now, set up the withdrawal
        uint256 withdrawAmount = 200 * (10**6); // 200 USDC
        uint256 expectedBankTotal = depositAmount - withdrawAmount; // 300 USDC
        uint256 expectedUserBalance = depositAmount - withdrawAmount; // 300 USDC
        // User started with 1000, deposited 500 (has 500), now withdraws 200
        uint256 expectedUserTokenBalance = (1_000 * (10**6)) - depositAmount + withdrawAmount; // 700 USDC

        // Act
        vm.prank(USER_A);
        bank.withdrawUsdc(withdrawAmount);

        // Assert
        assertEq(bank.getBalance(USER_A), expectedUserBalance, "Bank internal balance mismatch");
        assertEq(bank.getTotalUsdcInBank(), expectedBankTotal, "Bank total balance mismatch");
        assertEq(usdc.balanceOf(USER_A), expectedUserTokenBalance, "User token balance mismatch");
        assertEq(usdc.balanceOf(address(bank)), expectedBankTotal, "Contract token balance mismatch");
    }

    /**
     * @notice Tests that a user cannot withdraw more than they have.
     */
    function test_Fail_WithdrawInsufficientFunds() public {
        // Arrange: Deposit 500 USDC
        uint256 depositAmount = 500 * (10**6);
        vm.prank(USER_A);
        usdc.approve(address(bank), depositAmount);
        vm.prank(USER_A);
        bank.depositUsdc(depositAmount);

        // Act: Try to withdraw 501 USDC
        uint256 withdrawAmount = 501 * (10**6);
        uint256 currentBalance = bank.getBalance(USER_A);

        // Assert: Expect the revert
        vm.prank(USER_A);
        vm.expectRevert(
            abi.encodeWithSelector(KipuBankV3.KipuBankV3__InsufficientFunds.selector, currentBalance, withdrawAmount)
        );
        bank.withdrawUsdc(withdrawAmount);
    }

    // =============================================================================
    //                           --- NEW TESTS ---
    // =============================================================================

    /**
     * @notice NEW TEST
     * @notice Tests that a deposit reverts if it exceeds the bank cap.
     */
    function test_Fail_DepositExceedsBankCap() public {
        // Arrange
        // Bank cap is 1,000,000 USDC. We mint 1,000,001.
        uint256 depositAmount = 1_000_001 * (10**6);
        usdc.mint(USER_A, depositAmount); // Mint the large amount for the user

        vm.prank(USER_A);
        usdc.approve(address(bank), depositAmount);

        // Act & Assert
        vm.prank(USER_A);
        vm.expectRevert(
            abi.encodeWithSelector(
                KipuBankV3.KipuBankV3__DepositExceedsBankCap.selector,
                BANK_CAP, // bankCap
                0, // currentTotal
                depositAmount // depositAmount
            )
        );
        bank.depositUsdc(depositAmount);
    }

    /**
     * @notice NEW TEST
     * @notice Tests that a withdrawal reverts if it exceeds the per-tx limit.
     */
    function test_Fail_WithdrawExceedsLimit() public {
        // Arrange: Deposit 2,000 USDC (more than the limit)
        uint256 depositAmount = 2_000 * (10**6);
        usdc.mint(USER_A, depositAmount); // Mint extra funds for this test
        vm.prank(USER_A);
        usdc.approve(address(bank), depositAmount);
        vm.prank(USER_A);
        bank.depositUsdc(depositAmount);

        uint256 withdrawAmount = 1_001 * (10**6); // Limit is 1,000

        // Act & Assert
        vm.prank(USER_A);
        vm.expectRevert(
            abi.encodeWithSelector(
                KipuBankV3.KipuBankV3__WithdrawalExceedsLimit.selector,
                MAX_WITHDRAWAL, // limit
                withdrawAmount // attempted
            )
        );
        bank.withdrawUsdc(withdrawAmount);
    }

    /**
     * @notice NEW TEST
     * @notice Tests that the owner can successfully use emergencyWithdrawToken.
     */
    function test_EmergencyWithdrawToken_Success() public {
        // Arrange: Deposit 500 USDC
        uint256 depositAmount = 500 * (10**6);
        vm.prank(USER_A);
        usdc.approve(address(bank), depositAmount);
        vm.prank(USER_A);
        bank.depositUsdc(depositAmount);

        // Assert balances before
        assertEq(usdc.balanceOf(address(bank)), depositAmount);
        assertEq(usdc.balanceOf(OWNER), 0);
        assertEq(bank.getTotalUsdcInBank(), depositAmount);

        // Act: Owner withdraws
        vm.prank(OWNER);
        bank.emergencyWithdrawToken(address(usdc));

        // Assert balances after
        assertEq(usdc.balanceOf(address(bank)), 0);
        assertEq(usdc.balanceOf(OWNER), depositAmount);
        // Check that the total balance was also updated
        assertEq(bank.getTotalUsdcInBank(), 0);
    }
}