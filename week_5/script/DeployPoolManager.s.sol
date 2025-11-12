contract DeployInternalSwapPool is Script {
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address constant EXISTING_POOL_MANAGER = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;

    function findUnsafe(
        address create2Deployer,
        uint160 flags,
        bytes memory bytecode,
        bytes memory constructorArgs
    ) internal pure returns (address predicted, bytes32 salt) {
        salt = keccak256(abi.encodePacked(flags));
        predicted = address(uint160(uint256(
            keccak256(abi.encodePacked(
                bytes1(0xff),
                create2Deployer,
                salt,
                keccak256(abi.encodePacked(bytecode, constructorArgs))
            ))
        )));
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        IPoolManager poolManager = IPoolManager(EXISTING_POOL_MANAGER);

        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        bytes memory constructorArgs = abi.encode(poolManager);

        // 1️⃣ Precompute CSMM CREATE2 address
        (address predicted, bytes32 salt) = findUnsafe(
            CREATE2_DEPLOYER,
            flags,
            type(CSMM).creationCode,
            constructorArgs
        );

        // 2️⃣ Pre-register predicted address as a valid hook
        poolManager.registerHook(predicted, flags);
        console.log("Pre-registered CSMM hook at:", predicted);

        console.log("Valid hook address found:", predicted);
        console.log("Code at predicted address:", address(predicted).code.length);
        console.log("PoolManager code length:", EXISTING_POOL_MANAGER.code.length);
        console.log("Salt:");
        console.logBytes32(salt);

        // 3️⃣ Deploy CSMM via CREATE2
        CSMM hook = new CSMM{salt: salt}(poolManager);
        console.log("Hook deployed at:", address(hook));
        require(address(hook) == predicted, "Hook address mismatch!");
        console.log("CSMM deployed to:", address(hook));
        console.log("Deployment successful!");

        vm.stopBroadcast();
    }
}
