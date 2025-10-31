// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {ERC1155TokenReceiver} from "solmate/src/tokens/ERC1155.sol";

import "forge-std/console.sol";
import {PointsHook} from "../src/PointsHook.sol";

contract TestPointsHook is Test, Deployers, ERC1155TokenReceiver {
    MockERC20 token;

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    PointsHook hook;

    function setUp() public {
        // Step 1 + 2
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();

        // Deploy our TOKEN contract
        token = new MockERC20("Test Token", "TEST", 18);
        tokenCurrency = Currency.wrap(address(token));

        // Mint a bunch of TOKEN to ourselves and to address(1)
        token.mint(address(this), 1000 ether);
        token.mint(address(1), 1000 ether);

        // Deploy hook to an address that has the proper flags set
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        deployCodeTo("PointsHook.sol", abi.encode(manager), address(flags));

        // Deploy our hook
        hook = PointsHook(address(flags));

        // Approve our TOKEN for spending on the swap router and modify liquidity router
        // These variables are coming from the `Deployers` contract
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Initialize a pool
        (key, ) = initPool(
            ethCurrency, // Currency 0 = ETH
            tokenCurrency, // Currency 1 = TOKEN
            hook, // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1 // Initial Sqrt(P) value = 1
        );

        // Add some liquidity to the pool
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint256 ethToAdd = 0.1 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            SQRT_PRICE_1_1,
            sqrtPriceAtTickUpper,
            ethToAdd
        );
        uint256 tokenToAdd = LiquidityAmounts.getAmount1ForLiquidity(
            sqrtPriceAtTickLower,
            SQRT_PRICE_1_1,
            liquidityDelta
        );

        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_swap() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        uint256 pointsBalanceOriginal = hook.balanceOf(
            address(this),
            poolIdUint
        );

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        // Now we swap
        // We will swap 0.001 ether for tokens
        // We should get 20% of 0.001 * 10**18 points
        // = 2 * 10**14
        swapRouter.swap{value: 0.001 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );
        uint256 pointsBalanceAfterSwap = hook.balanceOf(
            address(this),
            poolIdUint
        );
        assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 2 * 10 ** 14);
    }

    // Test: Multiple swaps accumulate points correctly
    function test_multipleSwapsAccumulatePoints() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        bytes memory hookData = abi.encode(address(this));

        uint256 pointsBalanceOriginal = hook.balanceOf(address(this), poolIdUint);

        // Perform first swap: 0.001 ETH
        swapRouter.swap{value: 0.001 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        // Perform second swap: 0.002 ETH
        swapRouter.swap{value: 0.002 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.002 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        uint256 pointsBalanceAfter = hook.balanceOf(address(this), poolIdUint);
        
        // Total ETH spent = 0.003 ether
        // Expected points = 0.003 ether / 5 = 6 * 10**14
        uint256 expectedPoints = (0.001 ether + 0.002 ether) / 5;
        assertEq(pointsBalanceAfter - pointsBalanceOriginal, expectedPoints);
    }

    // Test: Different users get their own points
    function test_differentUsersGetSeparatePoints() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        
        address user1 = address(0x1234);
        address user2 = address(0x5678);

        // Give users some ETH
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);

        // User 1 swaps 0.001 ETH
        vm.prank(user1);
        swapRouter.swap{value: 0.001 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(user1)
        );

        // User 2 swaps 0.002 ETH
        vm.prank(user2);
        swapRouter.swap{value: 0.002 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.002 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(user2)
        );

        // Check user1 has correct points
        uint256 user1Points = hook.balanceOf(user1, poolIdUint);
        assertEq(user1Points, 0.001 ether / 5);

        // Check user2 has correct points
        uint256 user2Points = hook.balanceOf(user2, poolIdUint);
        assertEq(user2Points, 0.002 ether / 5);
    }

    // Test: Reverse swap (token for ETH) doesn't give points
    function test_reverseSwapNoPoints() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        bytes memory hookData = abi.encode(address(this));

        uint256 pointsBalanceBefore = hook.balanceOf(address(this), poolIdUint);

        // Swap TOKEN for ETH (zeroForOne = false)
        // This should NOT give any points
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: false,
                amountSpecified: -1 ether, // Sell 1 TOKEN
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        uint256 pointsBalanceAfter = hook.balanceOf(address(this), poolIdUint);
        
        // No points should be awarded
        assertEq(pointsBalanceAfter, pointsBalanceBefore);
    }

    // Test: No hookData means no points awarded
    function test_noHookDataNoPoints() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));

        uint256 pointsBalanceBefore = hook.balanceOf(address(this), poolIdUint);

        // Swap without passing hookData
        swapRouter.swap{value: 0.001 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            "" // Empty hookData
        );

        uint256 pointsBalanceAfter = hook.balanceOf(address(this), poolIdUint);
        
        // No points should be awarded
        assertEq(pointsBalanceAfter, pointsBalanceBefore);
    }

    // Test: Zero address in hookData means no points awarded
    function test_zeroAddressInHookDataNoPoints() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));

        uint256 pointsBalanceBefore = hook.balanceOf(address(this), poolIdUint);

        // Swap with zero address in hookData
        bytes memory hookData = abi.encode(address(0));
        swapRouter.swap{value: 0.001 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        uint256 pointsBalanceAfter = hook.balanceOf(address(this), poolIdUint);
        
        // No points should be awarded
        assertEq(pointsBalanceAfter, pointsBalanceBefore);
    }

    // Test: Large swap awards correct points
    function test_largeSwapCorrectPoints() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        bytes memory hookData = abi.encode(address(this));

        uint256 pointsBalanceBefore = hook.balanceOf(address(this), poolIdUint);

        // Swap 0.05 ETH (larger amount)
        swapRouter.swap{value: 0.05 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.05 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        uint256 pointsBalanceAfter = hook.balanceOf(address(this), poolIdUint);
        
        // Expected points = 0.05 ether / 5 = 0.01 ether = 1 * 10**16
        uint256 expectedPoints = 0.05 ether / 5;
        assertEq(pointsBalanceAfter - pointsBalanceBefore, expectedPoints);
    }

    // Test: Points calculation is exact (no rounding errors for small amounts)
    function test_pointsCalculationExact() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        bytes memory hookData = abi.encode(address(this));

        uint256 pointsBalanceBefore = hook.balanceOf(address(this), poolIdUint);

        // Swap very small amount: 5 wei (should give 1 point)
        swapRouter.swap{value: 5}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -5, // 5 wei
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        uint256 pointsBalanceAfter = hook.balanceOf(address(this), poolIdUint);
        
        // 5 wei / 5 = 1 point
        assertEq(pointsBalanceAfter - pointsBalanceBefore, 1);
    }

    // Test: URI function returns correct string
    function test_uriFunction() public {
        string memory uri = hook.uri(0);
        assertEq(uri, "https://api.example.com/token/{id}");
    }
}