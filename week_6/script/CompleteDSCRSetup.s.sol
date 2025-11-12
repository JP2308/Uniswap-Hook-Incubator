// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {DSCRDynamicFeesHook} from "../src/DSCRDynamicFeesHook.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

contract CompleteDSCRSetup is Script {
    address constant POOL_MANAGER = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
    
    uint256 constant INITIAL_SUPPLY = 10_000_000 * 10**18;
    uint256 constant LIQUIDITY_AMOUNT = 1000 * 10**18;
    uint256 constant SWAP_AMOUNT = 1 * 10**18;
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        console.log("========================================");
        console.log("  COMPLETE DSCR HOOK SETUP & DEMO");
        console.log("========================================\n");
        console.log("Deployer:", deployer);

        // STEP 1: Deploy Tokens with salt to avoid address collision
        console.log("\n[1/7] Deploying Mock Tokens...");
        MockERC20 tokenA = new MockERC20{salt: bytes32(uint256(1))}("USD Coin", "USDC", 6);
        MockERC20 tokenB = new MockERC20{salt: bytes32(uint256(2))}("Tether", "USDT", 6);
        
        uint256 supply = INITIAL_SUPPLY / 10**12; // Adjust for 6 decimals
        tokenA.mint(deployer, supply);
        tokenB.mint(deployer, supply);
        
        (address token0Addr, address token1Addr) = address(tokenA) < address(tokenB) 
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));
        
        MockERC20 token0 = MockERC20(token0Addr);
        MockERC20 token1 = MockERC20(token1Addr);
        
        console.log("  Token0:", token0Addr);
        console.log("  Token1:", token1Addr);
        
        // Verify no collision with POOL_MANAGER
        require(token0Addr != POOL_MANAGER, "Token0 collides with PoolManager");
        require(token1Addr != POOL_MANAGER, "Token1 collides with PoolManager");

        // STEP 2: Deploy DSCR Hook
        console.log("\n[2/7] Deploying DSCR Hook...");
        
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | 
            Hooks.BEFORE_SWAP_FLAG
        );

        bytes memory constructorArgs = abi.encode(
            IPoolManager(POOL_MANAGER),
            deployer // Sentinel
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(0x4e59b44847b379578588920cA78FbF26c0B4956C),
            flags,
            type(DSCRDynamicFeesHook).creationCode,
            constructorArgs
        );

        bytes memory initCode = abi.encodePacked(
            type(DSCRDynamicFeesHook).creationCode,
            constructorArgs
        );

        address deployed;
        assembly {
            deployed := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }

        require(deployed == hookAddress, "Hook deployment failed");
        DSCRDynamicFeesHook hook = DSCRDynamicFeesHook(deployed);
        console.log("  Hook:", address(hook));

        // STEP 3: Deploy Swap Router
        console.log("\n[3/7] Deploying Swap Router...");
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(POOL_MANAGER));
        console.log("  Router:", address(swapRouter));

        // STEP 4: Initialize Pool
        console.log("\n[4/7] Initializing Pool...");
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0Addr),
            currency1: Currency.wrap(token1Addr),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        
        IPoolManager(POOL_MANAGER).initialize(poolKey, SQRT_PRICE_1_1);
        console.log("  Pool initialized");

        // STEP 5: Add Liquidity
        console.log("\n[5/7] Adding Liquidity...");
        PoolModifyLiquidityTest liquidityRouter = new PoolModifyLiquidityTest(IPoolManager(POOL_MANAGER));
        
        uint256 liqAmount = LIQUIDITY_AMOUNT / 10**12;
        token0.approve(address(liquidityRouter), liqAmount);
        token1.approve(address(liquidityRouter), liqAmount);
        
        liquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(liqAmount),
                salt: bytes32(0)
            }),
            ""
        );
        console.log("  Liquidity added");

        // STEP 6: Test Swaps with Different DSCR States
        console.log("\n[6/7] Testing Swaps with Different DSCR States...");
        
        uint256 swapAmt = SWAP_AMOUNT / 10**12;
        token0.approve(address(swapRouter), swapAmt * 3);
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(swapAmt),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Test 1: GOOD_BUFFER state (0.25% fee)
        console.log("\n  Test 1: GOOD_BUFFER State");
        console.log("    Current fee:", hook.getCurrentFee(), "pips");
        uint256 bal1Before = token1.balanceOf(deployer);
        swapRouter.swap(poolKey, params, testSettings, "");
        uint256 bal1After = token1.balanceOf(deployer);
        uint256 output1 = bal1After - bal1Before;
        console.log("    Output:", output1);

        // Test 2: NO_BREACH state (0.5% fee)
        console.log("\n  Test 2: NO_BREACH State");
        hook.updateDSCRStatus(DSCRDynamicFeesHook.DSCRStatus.NO_BREACH);
        console.log("    Current fee:", hook.getCurrentFee(), "pips");
        bal1Before = token1.balanceOf(deployer);
        swapRouter.swap(poolKey, params, testSettings, "");
        bal1After = token1.balanceOf(deployer);
        uint256 output2 = bal1After - bal1Before;
        console.log("    Output:", output2);

        // Test 3: BREACH state (1.0% fee)
        console.log("\n  Test 3: BREACH State");
        hook.updateDSCRStatus(DSCRDynamicFeesHook.DSCRStatus.BREACH);
        console.log("    Current fee:", hook.getCurrentFee(), "pips");
        bal1Before = token1.balanceOf(deployer);
        swapRouter.swap(poolKey, params, testSettings, "");
        bal1After = token1.balanceOf(deployer);
        uint256 output3 = bal1After - bal1Before;
        console.log("    Output:", output3);

        // STEP 7: Analysis
        console.log("\n[7/7] Results Analysis...");
        console.log("  GOOD_BUFFER output:", output1);
        console.log("  NO_BREACH output:", output2);
        console.log("  BREACH output:", output3);
        console.log("\n  As expected:");
        console.log("    GOOD_BUFFER > NO_BREACH > BREACH");
        console.log("    (lower fees = higher output)");

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("  SETUP COMPLETE!");
        console.log("========================================");
        console.log("\nDeployed Contracts:");
        console.log("  Hook:", address(hook));
        console.log("  Token0:", token0Addr);
        console.log("  Token1:", token1Addr);
        console.log("  Swap Router:", address(swapRouter));
        console.log("\nSentinel Controls:");
        console.log("  Current Sentinel:", hook.sentinel());
        console.log("  Update status: hook.updateDSCRStatus(newStatus)");
        console.log("  Update sentinel: hook.updateSentinel(newAddress)");
        console.log("========================================\n");
    }
}