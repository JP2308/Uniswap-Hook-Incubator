// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

/// @title DSCRDynamicFeesHook
/// @notice A hook that adjusts swap fees based on Debt Service Coverage Ratio (DSCR) health
/// @dev Fees change based on three states: BREACH, NO_BREACH, and GOOD_BUFFER
contract DSCRDynamicFeesHook is BaseHook {
    using LPFeeLibrary for uint24;

    // DSCR Health States
    enum DSCRStatus {
        GOOD_BUFFER,  // DSCR > 1.5 - Low risk, lowest fees
        NO_BREACH,    // 1.2 < DSCR <= 1.5 - Normal risk, normal fees
        BREACH        // DSCR <= 1.2 - High risk, highest fees
    }

    // Fee levels (denominated in pips - one-hundredth bps)
    uint24 public constant GOOD_BUFFER_FEE = 2500;  // 0.25%
    uint24 public constant NO_BREACH_FEE = 5000;     // 0.5%
    uint24 public constant BREACH_FEE = 10000;       // 1.0%

    // Current DSCR status
    DSCRStatus public currentStatus;

    // Authorized sentinel address that can update DSCR status
    address public sentinel;

    // Tracking
    uint256 public lastUpdateTimestamp;
    uint256 public totalStatusChanges;

    // Events
    event DSCRStatusUpdated(
        DSCRStatus indexed oldStatus,
        DSCRStatus indexed newStatus,
        uint256 timestamp,
        address indexed updatedBy
    );

    event SentinelUpdated(
        address indexed oldSentinel,
        address indexed newSentinel
    );

    event FeeApplied(
        address indexed swapper,
        DSCRStatus indexed status,
        uint24 fee
    );

    // Errors
    error MustUseDynamicFee();
    error OnlySentinel();
    error InvalidSentinel();

    // Modifiers
    modifier onlySentinel() {
        if (msg.sender != sentinel) revert OnlySentinel();
        _;
    }

    constructor(IPoolManager _poolManager, address _sentinel) BaseHook(_poolManager) {
        if (_sentinel == address(0)) revert InvalidSentinel();
        sentinel = _sentinel;
        currentStatus = DSCRStatus.GOOD_BUFFER; // Start optimistic
        lastUpdateTimestamp = block.timestamp;
    }

    // Required override function for BaseHook
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _beforeInitialize(
        address,
        PoolKey calldata key,
        uint160
    ) internal pure override returns (bytes4) {
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        uint24 fee = getCurrentFee();
        
        emit FeeApplied(sender, currentStatus, fee);
        
        // Set the OVERRIDE_FEE_FLAG to use our custom fee for this swap
        uint24 feeWithFlag = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        
        return (
            this.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            feeWithFlag
        );
    }

    /// @notice Update the DSCR status - called by the sentinel
    /// @param newStatus The new DSCR health status
    function updateDSCRStatus(DSCRStatus newStatus) external onlySentinel {
        DSCRStatus oldStatus = currentStatus;
        
        if (oldStatus != newStatus) {
            currentStatus = newStatus;
            lastUpdateTimestamp = block.timestamp;
            totalStatusChanges++;
            
            emit DSCRStatusUpdated(oldStatus, newStatus, block.timestamp, msg.sender);
        }
    }

    /// @notice Update the sentinel address
    /// @param newSentinel The new sentinel address
    function updateSentinel(address newSentinel) external onlySentinel {
        if (newSentinel == address(0)) revert InvalidSentinel();
        address oldSentinel = sentinel;
        sentinel = newSentinel;
        emit SentinelUpdated(oldSentinel, newSentinel);
    }

    /// @notice Get the current fee based on DSCR status
    /// @return The current fee in pips
    function getCurrentFee() public view returns (uint24) {
        if (currentStatus == DSCRStatus.GOOD_BUFFER) {
            return GOOD_BUFFER_FEE;
        } else if (currentStatus == DSCRStatus.NO_BREACH) {
            return NO_BREACH_FEE;
        } else {
            return BREACH_FEE;
        }
    }

    /// @notice Get detailed status information
    /// @return status Current DSCR status
    /// @return fee Current fee in pips
    /// @return lastUpdate Timestamp of last status update
    /// @return changes Total number of status changes
    function getStatusInfo() external view returns (
        DSCRStatus status,
        uint24 fee,
        uint256 lastUpdate,
        uint256 changes
    ) {
        return (
            currentStatus,
            getCurrentFee(),
            lastUpdateTimestamp,
            totalStatusChanges
        );
    }
}