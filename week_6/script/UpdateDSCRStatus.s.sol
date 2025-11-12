// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {DSCRDynamicFeesHook} from "../src/DSCRDynamicFeesHook.sol";

/// @title UpdateDSCRStatus
/// @notice Script to update the DSCR status of a deployed hook
/// @dev This simulates what your sentinel would do in production
contract UpdateDSCRStatus is Script {
    // Update this with your deployed hook address
    address constant HOOK_ADDRESS = address(0); // UPDATE THIS
    
    function run() external {
        require(HOOK_ADDRESS != address(0), "Set HOOK_ADDRESS first!");
        
        uint256 sentinelPrivateKey = vm.envUint("PRIVATE_KEY");
        address sentinel = vm.addr(sentinelPrivateKey);
        
        DSCRDynamicFeesHook hook = DSCRDynamicFeesHook(HOOK_ADDRESS);
        
        console.log("========================================");
        console.log("  UPDATE DSCR STATUS");
        console.log("========================================\n");
        console.log("Hook:", HOOK_ADDRESS);
        console.log("Sentinel:", sentinel);
        
        // Get current status
        (
            DSCRDynamicFeesHook.DSCRStatus currentStatus,
            uint24 currentFee,
            uint256 lastUpdate,
            uint256 changes
        ) = hook.getStatusInfo();
        
        console.log("\nCurrent State:");
        console.log("  Status:", uint256(currentStatus));
        console.log("  Fee:", currentFee, "pips");
        console.log("  Last Update:", lastUpdate);
        console.log("  Total Changes:", changes);
        
        // Choose new status (you can modify this)
        // 0 = GOOD_BUFFER, 1 = NO_BREACH, 2 = BREACH
        DSCRDynamicFeesHook.DSCRStatus newStatus = DSCRDynamicFeesHook.DSCRStatus.BREACH;
        
        console.log("\nUpdating to new status:", uint256(newStatus));
        
        vm.startBroadcast(sentinelPrivateKey);
        
        // Update the status
        hook.updateDSCRStatus(newStatus);
        
        vm.stopBroadcast();
        
        // Verify update
        (currentStatus, currentFee, lastUpdate, changes) = hook.getStatusInfo();
        
        console.log("\nNew State:");
        console.log("  Status:", uint256(currentStatus));
        console.log("  Fee:", currentFee, "pips");
        console.log("  Last Update:", lastUpdate);
        console.log("  Total Changes:", changes);
        console.log("\n========================================");
        console.log("  STATUS UPDATED SUCCESSFULLY!");
        console.log("========================================\n");
    }
}

/// @title UpdateToGoodBuffer
/// @notice Quick script to set status to GOOD_BUFFER
contract UpdateToGoodBuffer is Script {
    address constant HOOK_ADDRESS = address(0); // UPDATE THIS
    
    function run() external {
        require(HOOK_ADDRESS != address(0), "Set HOOK_ADDRESS first!");
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        DSCRDynamicFeesHook(HOOK_ADDRESS).updateDSCRStatus(
            DSCRDynamicFeesHook.DSCRStatus.GOOD_BUFFER
        );
        vm.stopBroadcast();
        console.log("Updated to GOOD_BUFFER (0.25% fee)");
    }
}

/// @title UpdateToNoBreach
/// @notice Quick script to set status to NO_BREACH
contract UpdateToNoBreach is Script {
    address constant HOOK_ADDRESS = address(0); // UPDATE THIS
    
    function run() external {
        require(HOOK_ADDRESS != address(0), "Set HOOK_ADDRESS first!");
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        DSCRDynamicFeesHook(HOOK_ADDRESS).updateDSCRStatus(
            DSCRDynamicFeesHook.DSCRStatus.NO_BREACH
        );
        vm.stopBroadcast();
        console.log("Updated to NO_BREACH (0.5% fee)");
    }
}

/// @title UpdateToBreach
/// @notice Quick script to set status to BREACH
contract UpdateToBreach is Script {
    address constant HOOK_ADDRESS = address(0); // UPDATE THIS
    
    function run() external {
        require(HOOK_ADDRESS != address(0), "Set HOOK_ADDRESS first!");
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        DSCRDynamicFeesHook(HOOK_ADDRESS).updateDSCRStatus(
            DSCRDynamicFeesHook.DSCRStatus.BREACH
        );
        vm.stopBroadcast();
        console.log("Updated to BREACH (1.0% fee)");
    }
}