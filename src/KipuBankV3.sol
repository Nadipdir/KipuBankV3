// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// =================================================================================
//                                     IMPORTS
// =================================================================================

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";

// =================================================================================
//                                KipuBankV3 Contract
// =================================================================================

/**
 * @title KipuBankV3
 * @author (Tu Nombre/Usuario Aquí)
 * @notice A decentralized bank (DeFi) that accepts deposits of ETH or any ERC20 token,
 * automatically swaps them to USDC via Uniswap V2, and manages user balances in USDC.
 * It enforces a global bank cap and per-transaction withdrawal limits.
 * @custom:security Educational contract. All feedback from TP2 and TP3 has been implemented.
 * @custom:tp-challenge Implements Uniswap V2 integration and token swaps.
 */
contract KipuBankV3 is Ownable {
    // =============================================================================
    //                                  LIBRARIES
    // =============================================================================

    using SafeERC20 for IERC20;

    // =============================================================================
    //                                CUSTOM ERRORS
    // =============================================================================

    error KipuBankV3__ZeroAmount();
    error KipuBankV3__WithdrawalExceedsLimit(uint256 limit, uint256 attempted);
    error KipuBankV3__InsufficientFunds(uint256 balance, uint256 attempted);
    error KipuBankV3__DepositExceedsBankCap(uint256 bankCap, uint256 currentTotal, uint256 depositAmount);
    error KipuBankV3__WrongDepositFunction();
    error KipuBankV3__SwapFailedToReturnUSDC();
    error KipuBankV3__NativeTransferFailed();

    // =============================================================================
    //                                   EVENTS
    // =============================================================================

    event DepositSuccessful(
        address indexed user,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOutUsdc,
        uint256 newBalanceUsdc
    );

    event WithdrawalSuccessful(address indexed user, uint256 amountUsdc, uint256 newBalanceUsdc);

    // =============================================================================
    //                          STATE VARIABLES (STORAGE)
    // =============================================================================

    /// @notice Tracks the USDC balance of each user.
    /// @dev mapping: userAddress => amount (in USDC, 6 decimals).
    mapping(address => uint256) private s_balancesUsdc;

    /// @notice The total value of USDC held by the bank.
    uint256 private s_totalUsdcInBank;

    // =============================================================================
    //                          IMMUTABLE AND CONSTANT VARIABLES
    // =============================================================================

    /// @notice The ERC20 contract address for USDC.
    IERC20 public immutable I_USDC_TOKEN;
    /// @notice The contract address for WETH (Wrapped ETH).
    IWETH public immutable I_WETH_TOKEN;
    /// @notice The contract address for the Uniswap V2 Router.
    IUniswapV2Router02 public immutable I_UNISWAP_ROUTER;

    /// @notice The maximum total USDC the bank can hold globally.
    uint256 public immutable I_BANK_CAP_USD;
    /// @notice The maximum USDC a user can withdraw in a single transaction.
    uint256 public immutable I_MAX_WITHDRAWAL_PER_TX_USD;

    /// @notice The number of decimals for USDC (standard is 6).
    uint256 public constant DECIMALS_USDC = 6;
    /// @notice The number of decimals for ETH/WETH (standard is 18).
    uint256 public constant DECIMALS_ETH = 18;
    /// @notice The address used to represent native ETH deposits.
    address public constant ETH_ADDRESS = address(0);

    // =============================================================================
    //                                  MODIFIERS
    // =============================================================================

    /// @dev Reverts if the provided amount is zero.
    modifier nonZeroAmount(uint256 _amount) {
        _nonZeroAmount(_amount);
        _;
    }

    // =============================================================================
    //                                  CONSTRUCTOR
    // =============================================================================

    constructor(
        address _owner,
        address _usdcAddress,
        address _wethAddress,
        address _routerAddress,
        uint256 _bankCapUsd,
        uint256 _maxWithdrawalPerTxUsd
    ) Ownable(_owner) {
        // Protocol Addresses
        I_USDC_TOKEN = IERC20(_usdcAddress);
        I_WETH_TOKEN = IWETH(_wethAddress);
        I_UNISWAP_ROUTER = IUniswapV2Router02(_routerAddress);

        // Bank Configuration
        I_BANK_CAP_USD = _bankCapUsd;
        I_MAX_WITHDRAWAL_PER_TX_USD = _maxWithdrawalPerTxUsd;
    }

    // =============================================================================
    //                                DEPOSIT FUNCTIONS
    // =============================================================================

    function depositEth() public payable nonZeroAmount(msg.value) {
        // 1. Wrap ETH into WETH
        I_WETH_TOKEN.deposit{value: msg.value}();
        uint256 wethAmount = msg.value; // 1:1 wrapping

        // 2. Swap WETH for USDC
        _swapToUsdc(address(I_WETH_TOKEN), wethAmount, msg.sender, ETH_ADDRESS, wethAmount);
    }

    function depositUsdc(uint256 _amount) external nonZeroAmount(_amount) {
        // 1. Pull USDC from user
        I_USDC_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);

        // 2. Credit the user's balance
        _creditUsdc(msg.sender, _amount, address(I_USDC_TOKEN), _amount);
    }

    function depositToken(address _token, uint256 _amount) external nonZeroAmount(_amount) {
        if (_token == address(I_USDC_TOKEN)) {
            revert KipuBankV3__WrongDepositFunction(); // Tell user to use depositUsdc
        }

        // 1. Pull Token from user
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // 2. Swap Token for USDC
        _swapToUsdc(_token, _amount, msg.sender, _token, _amount);
    }

    // =============================================================================
    //                                WITHDRAW FUNCTION
    // =============================================================================

    function withdrawUsdc(uint256 _amount) external nonZeroAmount(_amount) {
        // --- CHECKS ---
        if (_amount > I_MAX_WITHDRAWAL_PER_TX_USD) {
            revert KipuBankV3__WithdrawalExceedsLimit(I_MAX_WITHDRAWAL_PER_TX_USD, _amount);
        }

        // (Gas Optimization: Read from storage ONCE)
        uint256 userBalance = s_balancesUsdc[msg.sender];
        if (_amount > userBalance) {
            revert KipuBankV3__InsufficientFunds(userBalance, _amount);
        }

        // --- CORRECCIÓN CRÍTICA ---
        // Calculate new balance in memory FIRST.
        uint256 newBalance = userBalance - _amount;

        // --- EFFECTS (Update state BEFORE interaction) ---
        // (Gas Optimization: Use unchecked as underflow is impossible)
        unchecked {
            s_balancesUsdc[msg.sender] = newBalance; // Write to storage ONCE
            s_totalUsdcInBank -= _amount;
        }

        // --- INTERACTIONS (Transfer USDC) ---
        I_USDC_TOKEN.safeTransfer(msg.sender, _amount);

        // Use the memory variable 'newBalance' for the emit.
        // This avoids a second read from storage.
        emit WithdrawalSuccessful(msg.sender, _amount, newBalance);
    }

    // =============================================================================
    //                                OWNER FUNCTIONS
    // =============================================================================

    function emergencyWithdrawEth() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success,) = owner().call{value: balance}("");
            if (!success) {
                revert KipuBankV3__NativeTransferFailed();
            }
        }
    }

    function emergencyWithdrawToken(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance > 0) {
            if (_token == address(I_USDC_TOKEN)) {
                unchecked {
                    s_totalUsdcInBank -= balance;
                }
            }
            IERC20(_token).safeTransfer(owner(), balance);
        } 
    } 

    // =============================================================================
    //                                VIEW FUNCTIONS
    // =============================================================================

    function getBalance(address _user) external view returns (uint256 balance) {
        return s_balancesUsdc[_user];
    }

    function getTotalUsdcInBank() external view returns (uint256 total) {
        return s_totalUsdcInBank;
    }

    function getBankCap() external view returns (uint256 cap) {
        return I_BANK_CAP_USD;
    }

    // =============================================================================
    //                                INTERNAL FUNCTIONS
    // =============================================================================

    // LINT FIX: Internal function for nonZeroAmount modifier
    function _nonZeroAmount(uint256 _amount) internal pure {
        if (_amount == 0) {
            revert KipuBankV3__ZeroAmount();
        }
    }

    function _swapToUsdc(
        address _tokenIn,
        uint256 _amountIn,
        address _user,
        address _originalTokenIn,
        uint256 _originalAmountIn
    ) private {
        // 1. Approve the Uniswap Router to spend our new token
        IERC20(_tokenIn).approve(address(I_UNISWAP_ROUTER), _amountIn);

        // 2. Define the swap path: [_tokenIn] -> [USDC]
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = address(I_USDC_TOKEN);

        // 3. Execute the swap
        I_UNISWAP_ROUTER.swapExactTokensForTokens(
            _amountIn, // amountIn
            0, // amountOutMin
            path, // path
            address(this), // to (send the USDC to this contract)
            block.timestamp // deadline
        );

        // 4. Get the amount of USDC we *actually* received
        uint256 usdcReceived = I_USDC_TOKEN.balanceOf(address(this)) - s_totalUsdcInBank;
        if (usdcReceived == 0) {
            revert KipuBankV3__SwapFailedToReturnUSDC();
        }

        // (Security) Clean up the allowance to the router
        IERC20(_tokenIn).approve(address(I_UNISWAP_ROUTER), 0);

        // 5. Credit the user's balance with the received USDC
        _creditUsdc(_user, usdcReceived, _originalTokenIn, _originalAmountIn);
    }

    function _creditUsdc(address _user, uint256 _usdcAmount, address _tokenIn, uint256 _amountIn) private {
        // --- CHECKS ---
        uint256 currentTotal = s_totalUsdcInBank;
        uint256 potentialTotal = currentTotal + _usdcAmount;

        if (potentialTotal > I_BANK_CAP_USD) {
            revert KipuBankV3__DepositExceedsBankCap(I_BANK_CAP_USD, currentTotal, _usdcAmount);
        }

        // --- EFFECTS ---
        uint256 currentBalance = s_balancesUsdc[_user];

        unchecked {
            uint256 newBalance = currentBalance + _usdcAmount;
            s_balancesUsdc[_user] = newBalance; // Write to storage ONCE
            s_totalUsdcInBank = potentialTotal; // Write to storage ONCE

            // --- INTERACTIONS (Event) ---
            // (Correct) Use the memory variable 'newBalance' for the emit.
            emit DepositSuccessful(_user, _tokenIn, _amountIn, _usdcAmount, newBalance);
        }
    }

    // =============================================================================
    //                                RECEIVE FUNCTION
    // =============================================================================

    receive() external payable {
        depositEth();
    }
}