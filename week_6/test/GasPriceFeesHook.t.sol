// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {DSCRDynamicFeesHook} from "../src/DSCRDynamicFeesHook.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {console} from "forge-std/console.sol";

contract TestDSCRHook is Test, Deployers {
    DSCRDynamicFeesHook hook;
    address sentinel;

    function setUp() public {
        // Deploy v4-core
        deployFreshManagerAndRouters();

        // Deploy and mint tokens
        deployMintAndApprove2Currencies();

        // Set sentinel to the test contract
        sentinel = address(this);

        // Deploy our hook with proper flags
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG
            )
        );

        deployCodeTo(
            "DSCRDynamicFeesHook.sol",
            abi.encode(manager, sentinel),
            hookAddress
        );
        hook = DSCRDynamicFeesHook(hookAddress);

        // Initialize pool with dynamic fees
        (key, ) = initPool(
            currency0,
            currency1,
            hook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1
        );

        // Add liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 100 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_InitialState() public {
        assertEq(uint256(hook.currentStatus()), uint256(DSCRDynamicFeesHook.DSCRStatus.GOOD_BUFFER));
        assertEq(hook.getCurrentFee(), hook.GOOD_BUFFER_FEE());
        assertEq(hook.sentinel(), sentinel);
    }

    function test_FeeChangesWithDSCRStatus() public {
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -0.001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        // Test GOOD_BUFFER (lowest fee)
        uint256 balBefore = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        uint256 balAfter = currency1.balanceOfSelf();
        uint256 outputGoodBuffer = balAfter - balBefore;

        // Change to NO_BREACH (medium fee)
        hook.updateDSCRStatus(DSCRDynamicFeesHook.DSCRStatus.NO_BREACH);
        assertEq(hook.getCurrentFee(), hook.NO_BREACH_FEE());

        balBefore = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        balAfter = currency1.balanceOfSelf();
        uint256 outputNoBreach = balAfter - balBefore;

        // Change to BREACH (highest fee)
        hook.updateDSCRStatus(DSCRDynamicFeesHook.DSCRStatus.BREACH);
        assertEq(hook.getCurrentFee(), hook.BREACH_FEE());

        balBefore = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        balAfter = currency1.balanceOfSelf();
        uint256 outputBreach = balAfter - balBefore;

        // Verify fee impact: lower fees = higher output
        assertGt(outputGoodBuffer, outputNoBreach);
        assertGt(outputNoBreach, outputBreach);

        console.log("GOOD_BUFFER output:", outputGoodBuffer);
        console.log("NO_BREACH output:", outputNoBreach);
        console.log("BREACH output:", outputBreach);
    }

    function test_OnlySentinelCanUpdate() public {
        vm.prank(address(0xdead));
        vm.expectRevert(DSCRDynamicFeesHook.OnlySentinel.selector);
        hook.updateDSCRStatus(DSCRDynamicFeesHook.DSCRStatus.BREACH);
    }

    function test_SentinelCanBeUpdated() public {
        address newSentinel = address(0x1234);
        
        hook.updateSentinel(newSentinel);
        assertEq(hook.sentinel(), newSentinel);

        // Old sentinel can't update anymore
        vm.expectRevert(DSCRDynamicFeesHook.OnlySentinel.selector);
        hook.updateDSCRStatus(DSCRDynamicFeesHook.DSCRStatus.BREACH);

        // New sentinel can update
        vm.prank(newSentinel);
        hook.updateDSCRStatus(DSCRDynamicFeesHook.DSCRStatus.BREACH);
        assertEq(uint256(hook.currentStatus()), uint256(DSCRDynamicFeesHook.DSCRStatus.BREACH));
    }

    function test_StatusTracking() public {
        assertEq(hook.totalStatusChanges(), 0);

        hook.updateDSCRStatus(DSCRDynamicFeesHook.DSCRStatus.NO_BREACH);
        assertEq(hook.totalStatusChanges(), 1);

        hook.updateDSCRStatus(DSCRDynamicFeesHook.DSCRStatus.BREACH);
        assertEq(hook.totalStatusChanges(), 2);

        // Same status shouldn't increment
        hook.updateDSCRStatus(DSCRDynamicFeesHook.DSCRStatus.BREACH);
        assertEq(hook.totalStatusChanges(), 2);
    }

    function test_GetStatusInfo() public {
        (
            DSCRDynamicFeesHook.DSCRStatus status,
            uint24 fee,
            uint256 lastUpdate,
            uint256 changes
        ) = hook.getStatusInfo();

        assertEq(uint256(status), uint256(DSCRDynamicFeesHook.DSCRStatus.GOOD_BUFFER));
        assertEq(fee, hook.GOOD_BUFFER_FEE());
        assertGt(lastUpdate, 0);
        assertEq(changes, 0);
    }
}