// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/DStockFactoryRegistry.sol";
import "../src/interfaces/IDStockWrapper.sol";

contract CreateWrapper is Script {
  struct Config {
    address factory;
    address admin;

    // multi-underlying
    address[] initialUnderlyings;

    // token meta
    string  name;
    string  symbol;
    uint8   decimalsOverride;

    // compliance / fees / limits
    address customCompliance;
    address treasury;
    uint16  wrapFeeBps;
    uint16  unwrapFeeBps;
    uint256 cap;
    string  termsURI;

    // accounting
    uint256 initialMultiplierRay;
    uint256 feePerPeriodRay;
    uint32  periodLength;
    uint8   feeModel;
  }

  function run() external {
    Config memory cfg = _load();               // read env -> struct
    uint256 ADMIN_PK = vm.envUint("ADMIN_PK");
    vm.startBroadcast(ADMIN_PK);

    DStockFactoryRegistry factory = DStockFactoryRegistry(cfg.factory);

    IDStockWrapper.InitParams memory p = IDStockWrapper.InitParams({
      // roles / pointers
      admin: cfg.admin,
      factoryRegistry: address(0),             // factory will inject

      // token meta
      initialUnderlyings: cfg.initialUnderlyings,
      name: cfg.name,
      symbol: cfg.symbol,
      decimalsOverride: cfg.decimalsOverride,

      // compliance / fees / limits
      compliance: cfg.customCompliance,        // 0 => falls back to globalCompliance
      treasury: cfg.treasury,
      wrapFeeBps: cfg.wrapFeeBps,
      unwrapFeeBps: cfg.unwrapFeeBps,
      cap: cfg.cap,
      termsURI: cfg.termsURI,

      // accounting
      initialMultiplierRay: cfg.initialMultiplierRay,
      feePerPeriodRay: cfg.feePerPeriodRay,
      periodLength: cfg.periodLength,
      feeModel: cfg.feeModel
    });

    address wrapper = factory.createWrapper(p);

    vm.stopBroadcast();

    console2.log("Factory:", cfg.factory);
    console2.log("New Wrapper:", wrapper);
    console2.log("Underlyings:", cfg.initialUnderlyings.length);
    for (uint256 i = 0; i < cfg.initialUnderlyings.length; i++) {
      console2.log("  -", cfg.initialUnderlyings[i]);
    }
  }

  // ----------------- helpers -----------------

  function _load() internal view returns (Config memory c) {
    c.factory          = vm.envAddress("FACTORY");
    c.admin            = vm.envAddress("ADMIN");

    // multi-underlying
    c.initialUnderlyings = _loadUnderlyings();

    // token meta
    c.name             = vm.envOr("NAME", string("dTOKEN"));
    c.symbol           = vm.envOr("SYMBOL", string("dTKN"));
    c.decimalsOverride = uint8(vm.envOr("DECIMALS_OVERRIDE", uint256(0)));

    // compliance / fees / limits
    c.customCompliance = vm.envOr("CUSTOM_COMPLIANCE", address(0));
    c.treasury         = vm.envOr("TREASURY", address(0));
    c.wrapFeeBps       = uint16(vm.envOr("WRAP_FEE_BPS", uint256(0)));
    c.unwrapFeeBps     = uint16(vm.envOr("UNWRAP_FEE_BPS", uint256(0)));
    c.cap              = vm.envOr("CAP", uint256(0));
    c.termsURI         = vm.envOr("TERMS_URI", string("https://terms"));

    // accounting
    c.initialMultiplierRay = vm.envOr("INITIAL_MULTIPLIER_RAY", uint256(1e18));
    c.feePerPeriodRay      = vm.envOr("FEE_PER_PERIOD_RAY", uint256(0));
    c.periodLength         = uint32(vm.envOr("PERIOD_LENGTH", uint256(0)));
    c.feeModel             = uint8(vm.envOr("FEE_MODEL", uint256(0)));
  }

  /// Read underlyings from env:
  ///   UNDERLYING_COUNT=N
  ///   UNDERLYING_0=0x...
  ///   UNDERLYING_1=0x...
  function _loadUnderlyings() internal view returns (address[] memory arr) {
    uint256 n = vm.envOr("UNDERLYING_COUNT", uint256(0));
    arr = new address[](n);
    for (uint256 i = 0; i < n; i++) {
      // key = string.concat("UNDERLYING_", vm.toString(i))
      string memory key = string.concat("UNDERLYING_", vm.toString(i));
      arr[i] = vm.envAddress(key);
    }
  }
}
