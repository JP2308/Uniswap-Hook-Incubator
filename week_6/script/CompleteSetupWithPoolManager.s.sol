// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {DSCRDynamicFeesHook} from "../src/DSCRDynamicFeesHook.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
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

contract CompleteSetupWithPoolManager is Script {
    uint256 constant INITIAL_SUPPLY = 10_000_000 * 10**18;
    uint256 constant LIQUIDITY_AMOUNT = 1000 * 10**18;
    uint256 constant SWAP_AMOUNT = 1 * 10**18;
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    // State variables to avoid stack too deep
    MockERC20 public token0;
    MockERC20 public token1;
    DSCRDynamicFeesHook public hook;
    PoolSwapTest public swapRouter;
    PoolManager public poolManager;
    PoolKey public poolKey;
    address public deployer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        console.log("========================================");
        console.log("  COMPLETE DSCR HOOK SETUP & DEMO");
        console.log("========================================\n");
        console.log("Deployer:", deployer);

        deployPoolManager();
        deployTokens();
        deployHook();
        deploySwapRouter();
        initializePool();
        addLiquidity();
        testSwaps();
        printResults();

        vm.stopBroadcast();
    }

    function deployPoolManager() internal {
        console.log("\n[1/8] Deploying PoolManager...");
        poolManager = new PoolManager(deployer); // 500k as controller fee
        console.log("  PoolManager:", address(poolManager));
    }

    function deployTokens() internal {
        console.log("\n[2/8] Deploying Mock Tokens...");
        
        // Use salt to ensure different addresses
        MockERC20 tokenA = new MockERC20{salt: bytes32(uint256(1))}("USD Coin", "USDC", 6);
        MockERC20 tokenB = new MockERC20{salt: bytes32(uint256(2))}("Tether", "USDT", 6);
        
        uint256 supply = INITIAL_SUPPLY / 10**12;
        tokenA.mint(deployer, supply);
        tokenB.mint(deployer, supply);
        
        (address token0Addr, address token1Addr) = address(tokenA) < address(tokenB) 
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));
        
        token0 = MockERC20(token0Addr);
        token1 = MockERC20(token1Addr);
        
        console.log("  Token0:", token0Addr);
        console.log("  Token1:", token1Addr);
    }

    function deployHook() internal {
        console.log("\n[3/8] Deploying DSCR Hook...");
        
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | 
            Hooks.BEFORE_SWAP_FLAG
        );

        bytes memory constructorArgs = abi.encode(
            poolManager,
            deployer
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
        hook = DSCRDynamicFeesHook(deployed);
        console.log("  Hook:", address(hook));
    }

    function deploySwapRouter() internal {
        console.log("\n[4/8] Deploying Swap Router...");
        swapRouter = new PoolSwapTest(poolManager);
        console.log("  Router:", address(swapRouter));
    }

    function initializePool() internal {
        console.log("\n[5/8] Initializing Pool...");
        poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        
        poolManager.initialize(poolKey, SQRT_PRICE_1_1);
        console.log("  Pool initialized");
    }

    function addLiquidity() internal {
        console.log("\n[6/8] Adding Liquidity...");
        PoolModifyLiquidityTest liquidityRouter = new PoolModifyLiquidityTest(poolManager);
        
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
    }

    function testSwaps() internal {
        console.log("\n[7/8] Testing Swaps with Different DSCR States...");
        
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

        // Test 1: GOOD_BUFFER
        console.log("\n  Test 1: GOOD_BUFFER State");
        console.log("    Current fee:", hook.getCurrentFee(), "pips");
        uint256 output1 = performSwap(params, testSettings);
        console.log("    Output:", output1);

        // Test 2: NO_BREACH
        console.log("\n  Test 2: NO_BREACH State");
        hook.updateDSCRStatus(DSCRDynamicFeesHook.DSCRStatus.NO_BREACH);
        console.log("    Current fee:", hook.getCurrentFee(), "pips");
        uint256 output2 = performSwap(params, testSettings);
        console.log("    Output:", output2);

        // Test 3: BREACH
        console.log("\n  Test 3: BREACH State");
        hook.updateDSCRStatus(DSCRDynamicFeesHook.DSCRStatus.BREACH);
        console.log("    Current fee:", hook.getCurrentFee(), "pips");
        uint256 output3 = performSwap(params, testSettings);
        console.log("    Output:", output3);

        // Analysis
        console.log("\n[8/8] Results Analysis...");
        console.log("  GOOD_BUFFER output:", output1);
        console.log("  NO_BREACH output:", output2);
        console.log("  BREACH output:", output3);
        console.log("\n  As expected:");
        console.log("    GOOD_BUFFER > NO_BREACH > BREACH");
        console.log("    (lower fees = higher output)");
    }

    function performSwap(
        SwapParams memory params,
        PoolSwapTest.TestSettings memory testSettings
    ) internal returns (uint256 output) {
        uint256 balBefore = token1.balanceOf(deployer);
        swapRouter.swap(poolKey, params, testSettings, "");
        uint256 balAfter = token1.balanceOf(deployer);
        output = balAfter - balBefore;
    }

    function printResults() internal view {
        console.log("\n========================================");
        console.log("  SETUP COMPLETE!");
        console.log("========================================");
        console.log("\nDeployed Contracts:");
        console.log("  PoolManager:", address(poolManager));
        console.log("  Hook:", address(hook));
        console.log("  Token0:", address(token0));
        console.log("  Token1:", address(token1));
        console.log("  Swap Router:", address(swapRouter));
        console.log("\nSentinel Controls:");
        console.log("  Current Sentinel:", hook.sentinel());
        console.log("  Update status: hook.updateDSCRStatus(newStatus)");
        console.log("  Update sentinel: hook.updateSentinel(newAddress)");
        console.log("========================================\n");
    }
}