// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {TakeProfitsHook} from "../src/TakeProfitsHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {PoolManager} from "v4-periphery/lib/v4-core/src/PoolManager.sol";

contract DeployTakeProfitsHook is Script {
    
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
    
    string constant _uri = "https://example.com/api/token/{id}";

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // 1. Deploy PoolManager
        console.log("Deploying PoolManager...");
        IPoolManager manager = IPoolManager(address(new PoolManager(address(0))));
        console.log("PoolManager deployed:", address(manager));

        // 2. Mine for hook address with correct permissions
        console.log("\nMining for hook address...");
        
        // TakeProfitsHook needs AFTER_INITIALIZE and AFTER_SWAP
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG
        );

        // Constructor args should match the actual constructor: (IPoolManager, string)
        bytes memory constructorArgs = abi.encode(manager, _uri);
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(TakeProfitsHook).creationCode,
            constructorArgs
        );

        console.log("Hook address found:", hookAddress);
        console.log("Salt:", vm.toString(salt));

        // 3. Deploy the hook using CREATE2
        console.log("\nDeploying TakeProfitsHook...");
        
        // Prepare the full bytecode for CREATE2 deployment
        bytes memory creationCode = abi.encodePacked(
            type(TakeProfitsHook).creationCode,
            constructorArgs
        );

        // Deploy using CREATE2
        address deployedAddress;
        assembly {
            deployedAddress := create2(
                0,
                add(creationCode, 0x20),
                mload(creationCode),
                salt
            )
        }

        require(deployedAddress != address(0), "Deployment failed!");
        require(deployedAddress == hookAddress, "Hook address mismatch!");

        TakeProfitsHook hook = TakeProfitsHook(deployedAddress);

        console.log("\n=== Deployment Complete ===");
        console.log("PoolManager:", address(manager));
        console.log("TakeProfitsHook:", address(hook));
        console.log("Token URI:", _uri);
        console.log("===========================\n");

        vm.stopBroadcast();
    }

    function getHookPermissions() internal pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}