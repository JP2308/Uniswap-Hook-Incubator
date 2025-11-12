// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {CSMM} from "../src/InternalSwapPool.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract DeployInternalSwapPool is Script {
    // Foundry's default Create2Deployer address
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Replace this with your already deployed PoolManager address
    address constant EXISTING_POOL_MANAGER = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get the deployer address
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        IPoolManager poolManager = IPoolManager(EXISTING_POOL_MANAGER);

        // Get the correct flags for CSMM based on getHookPermissions()
        // CSMM needs: beforeAddLiquidity, beforeSwap, beforeSwapReturnDelta
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | 
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        console.log("Mining for valid hook address with flags:", flags);

        // Encode constructor arguments
        bytes memory constructorArgs = abi.encode(poolManager);

        // Mine for a valid salt that produces an address matching the required flags
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(CSMM).creationCode,
            constructorArgs
        );

        console.log("Valid hook address found:", hookAddress);
        console.log("Salt:");
        console.logBytes32(salt);

        // Deploy the CSMM hook using CREATE2 via the Create2Deployer
        // The Create2Deployer expects: deployCreate2(bytes32 salt, bytes memory initCode)
        bytes memory initCode = abi.encodePacked(
            type(CSMM).creationCode,
            constructorArgs
        );

        // Deploy via CREATE2
        address deployed;
        assembly {
            deployed := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }

        require(deployed != address(0), "Deployment failed");
        require(deployed == hookAddress, "Hook address mismatch!");
        
        console.log("CSMM deployed to:", deployed);
        console.log("Deployment successful!");
        
        // Verify the hook permissions
        CSMM hook = CSMM(deployed);
        Hooks.Permissions memory perms = hook.getHookPermissions();
        console.log("beforeSwap:", perms.beforeSwap);
        console.log("beforeAddLiquidity:", perms.beforeAddLiquidity);
        console.log("beforeSwapReturnDelta:", perms.beforeSwapReturnDelta);

        vm.stopBroadcast();
    }
}