// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/DStockCompliance.sol";

contract DeployCompliance is Script {
  function run() external {
    // 1) Read admin address (ENV var ADMIN must be set)
    address ADMIN = vm.envAddress("ADMIN");

    // 2) Three lists — start empty; customize with fixed-length arrays and assignments if needed
    // KYC: example users
    address[] memory kycUsers = new address[](0);
    // Custody: example accounts
    address[] memory custodies = new address[](0);
    // Sanctions: example blocked addresses
    address[] memory sanctions = new address[](0);
    // 3) Global compliance flags (adjust as needed)
    DStockCompliance.Flags memory flags = DStockCompliance.Flags({
      set: true,
      enforceSanctions: true,
      transferRestricted: false,
      wrapToCustodyOnly: false,
      unwrapFromCustodyOnly: false,
      kycOnWrap: true,
      kycOnUnwrap: true
    });

    uint256 ADMIN_PK = vm.envUint("ADMIN_PK");
    vm.startBroadcast(ADMIN_PK);

    DStockCompliance comp = new DStockCompliance(ADMIN);
    comp.grantRole(comp.OPERATOR_ROLE(), ADMIN);
    comp.setFlagsGlobal(flags);

    // 5) Write lists (skip when empty)
    if (kycUsers.length > 0) {
      comp.batchSetKyc(kycUsers, true);
    }
    for (uint256 i = 0; i < custodies.length; i++) {
      comp.setCustody(custodies[i], true);
    }
    for (uint256 j = 0; j < sanctions.length; j++) {
      comp.setSanctioned(sanctions[j], true);
    }

    vm.stopBroadcast();

    console2.log("DStockCompliance:", address(comp));
  }
}
