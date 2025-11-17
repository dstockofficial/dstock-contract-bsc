// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/DStockFactoryRegistry.sol";
import "../src/DStockWrapper.sol";
import "forge-std/console2.sol";

contract DeployFactory is Script {
  function run() external {
    address ADMIN = vm.envAddress("ADMIN");
    address WRAPPER_IMPL = vm.envOr("WRAPPER_IMPL", address(0));
    address GLOBAL_COMPLIANCE = vm.envOr("COMPLIANCE", address(0));

    uint256 ADMIN_PK = vm.envUint("ADMIN_PK");
    vm.startBroadcast(ADMIN_PK);

    if (WRAPPER_IMPL == address(0)) {
      DStockWrapper impl = new DStockWrapper();
      WRAPPER_IMPL = address(impl);
    }

    DStockFactoryRegistry factory = new DStockFactoryRegistry(
      ADMIN,
      WRAPPER_IMPL,
      GLOBAL_COMPLIANCE
    );

    vm.stopBroadcast();

    console2.log("DStockWrapper impl:", WRAPPER_IMPL);
    console2.log("DStockFactoryRegistry:", address(factory));
    console2.log("Beacon (from factory):", address(factory.beacon()));
  }
}
