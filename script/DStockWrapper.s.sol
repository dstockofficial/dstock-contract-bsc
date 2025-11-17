// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {DStockWrapper} from "../src/DStockWrapper.sol";
import "forge-std/console2.sol";

contract DStockWrapperScript is Script {
    DStockWrapper public dStockWrapper;

    function setUp() public {}

    function run() public {
        uint256 ADMIN_PK = vm.envUint("ADMIN_PK");
        vm.startBroadcast(ADMIN_PK);

        dStockWrapper = new DStockWrapper();

        vm.stopBroadcast();
        console2.log("DStockWrapper deployed", address(dStockWrapper));
    }
}
