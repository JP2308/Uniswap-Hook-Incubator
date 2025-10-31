// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PointsHook} from "../src/PointsHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract DeployHook is Script {
    // Foundry's default Create2Deployer address
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Uniswap v4 PoolManager on Base Sepolia
        IPoolManager poolManager = IPoolManager(0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD);

        // Your hook only uses AFTER_SWAP
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);

        // Encode constructor arguments
        bytes memory constructorArgs = abi.encode(poolManager);

        // 🔍 Mine for a valid salt/address combination using CREATE2_DEPLOYER
        (address predicted, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,  // Use the Create2Deployer address instead of deployer
            flags,
            type(PointsHook).creationCode,
            constructorArgs
        );

        console.log("Valid hook address found:", predicted);
        console.log("Salt:");
        console.logBytes32(salt);

        // ✅ Deploy using CREATE2 with the valid salt
        PointsHook hook = new PointsHook{salt: salt}(poolManager);
        
        require(address(hook) == predicted, "Hook address mismatch!");

        console.log("PointsHook deployed to:", address(hook));
        console.log("Deployment successful!");

        vm.stopBroadcast();
    }
}