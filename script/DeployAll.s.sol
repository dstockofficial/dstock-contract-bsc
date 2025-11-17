// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/DStockCompliance.sol";
import "../src/DStockFactoryRegistry.sol";
import "../src/DStockWrapper.sol";
import {IDStockWrapper} from "../src/interfaces/IDStockWrapper.sol";
import "forge-std/console2.sol";

contract DeployAll is Script {
  // -------- data structs --------
  struct FlagsCfg {
    bool set;
    bool enforceSanctions;
    bool transferRestricted;
    bool wrapToCustodyOnly;
    bool unwrapFromCustodyOnly;
    bool kycOnWrap;
    bool kycOnUnwrap;
  }

  struct GlobalCfg {
    address admin;
    address compliance;     // may be 0 -> deploy a new compliance contract
    address wrapperImpl;    // may be 0 -> deploy a new wrapper implementation
    uint256 wrapperCount;
    FlagsCfg flags;
  }

  // -------- entry --------
  function run() external {
    GlobalCfg memory g = _readGlobal();

    uint256 ADMIN_PK = vm.envUint("ADMIN_PK"); // provided via env
    vm.startBroadcast(ADMIN_PK);

    // 1) Compliance module
    if (g.compliance == address(0)) {
      g.compliance = _deployCompliance(g.admin, g.flags);
    }

    // 2) Wrapper implementation
    if (g.wrapperImpl == address(0)) {
      g.wrapperImpl = address(new DStockWrapper());
    }

    // 3) Factory (internally deploys Beacon, owner = factory)
    address factory = address(
      new DStockFactoryRegistry(
        g.admin,
        g.wrapperImpl,
        g.compliance  // globalCompliance
      )
    );

    // 4) Batch-create wrappers (multi-underlyings)
    for (uint256 i = 0; i < g.wrapperCount; ++i) {
      string memory idx = vm.toString(i);

      // read underlyings for this index
      address[] memory initU = _readUnderlyingsForIndex(idx);
      if (initU.length == 0) {
        console2.log("skip index %s (UNDERLYING_COUNT_%s == 0)", idx, idx);
        continue;
      }

      IDStockWrapper.InitParams memory p = _readParamsForIndex(idx, g.admin, initU);
      address w = DStockFactoryRegistry(factory).createWrapper(p);
      console2.log("Wrapper[%s]: %s", idx, w);
    }

    vm.stopBroadcast();

    console2.log("Compliance", g.compliance);
    console2.log("Wrapper Impl", g.wrapperImpl);
    console2.log("Factory", factory);
  }

  // -------- helpers: global --------
  function _readGlobal() internal returns (GlobalCfg memory g) {
    g.admin        = vm.envAddress("ADMIN");
    g.compliance   = _envAddrOrZero("COMPLIANCE");
    g.wrapperImpl  = _envAddrOrZero("WRAPPER_IMPL");
    g.wrapperCount = vm.envOr("WRAPPER_COUNT", uint256(0));

    g.flags = FlagsCfg({
      set: true,
      enforceSanctions:      vm.envOr("ENFORCE_SANCTIONS",       true),
      transferRestricted:    vm.envOr("TRANSFER_RESTRICTED",     false),
      wrapToCustodyOnly:     vm.envOr("WRAP_TO_CUSTODY_ONLY",    false),
      unwrapFromCustodyOnly: vm.envOr("UNWRAP_FROM_CUSTODY_ONLY",false),
      kycOnWrap:             vm.envOr("KYC_ON_WRAP",             true),
      kycOnUnwrap:           vm.envOr("KYC_ON_UNWRAP",           true)
    });
  }

  function _deployCompliance(address admin, FlagsCfg memory fl) internal returns (address) {
    DStockCompliance c = new DStockCompliance(admin);
    c.grantRole(c.OPERATOR_ROLE(), admin);

    DStockCompliance.Flags memory gf = DStockCompliance.Flags({
      set: fl.set,
      enforceSanctions:      fl.enforceSanctions,
      transferRestricted:    fl.transferRestricted,
      wrapToCustodyOnly:     fl.wrapToCustodyOnly,
      unwrapFromCustodyOnly: fl.unwrapFromCustodyOnly,
      kycOnWrap:             fl.kycOnWrap,
      kycOnUnwrap:           fl.kycOnUnwrap
    });
    c.setFlagsGlobal(gf);
    return address(c);
  }

  // -------- helpers: per-index param packing --------
  function _readParamsForIndex(
    string memory idx,
    address admin,
    address[] memory initialUnderlyings
  ) internal returns (IDStockWrapper.InitParams memory p) {
    // New multi-underlying InitParams (no single `underlying` field)
    p.admin            = admin;
    p.factoryRegistry  = address(0); // factory will override
    p.initialUnderlyings = initialUnderlyings;

    p.name             = vm.envOr(_k("NAME_", idx),   string("dTOKEN"));
    p.symbol           = vm.envOr(_k("SYMBOL_", idx), string("dTKN"));
    p.decimalsOverride = uint8(vm.envOr(_k("DECIMALS_OVERRIDE_", idx), uint256(0)));
    p.compliance       = _envAddrOrZero(_k("CUSTOM_COMPLIANCE_", idx));
    p.treasury         = _envAddrOrZero(_k("TREASURY_", idx));
    p.wrapFeeBps       = uint16(vm.envOr(_k("WRAP_FEE_BPS_", idx),   uint256(0)));
    p.unwrapFeeBps     = uint16(vm.envOr(_k("UNWRAP_FEE_BPS_", idx), uint256(0)));
    p.cap              = vm.envOr(_k("CAP_", idx), uint256(0));
    p.termsURI         = vm.envOr(_k("TERMS_URI_", idx), string("https://terms"));
    p.initialMultiplierRay = vm.envOr(_k("INITIAL_MULTIPLIER_RAY_", idx), uint256(1e18));
    p.feePerPeriodRay      = vm.envOr(_k("FEE_PER_PERIOD_RAY_", idx),    uint256(0));
    p.periodLength         = uint32(vm.envOr(_k("PERIOD_LENGTH_", idx),  uint256(0)));
    p.feeModel             = uint8(vm.envOr(_k("FEE_MODEL_", idx),       uint256(0)));
  }

  // Read address[] for index i from ENV:
  // - UNDERLYING_COUNT_<i> = N
  // - UNDERLYING_<i>_0 ... UNDERLYING_<i>_(N-1)
  function _readUnderlyingsForIndex(string memory idx) internal returns (address[] memory arr) {
    string memory countKey = _k("UNDERLYING_COUNT_", idx);
    uint256 n = vm.envOr(countKey, uint256(0));
    if (n == 0) return new address[](0);

    arr = new address[](n);
    for (uint256 j = 0; j < n; ++j) {
      string memory key = string.concat("UNDERLYING_", idx, "_", vm.toString(j));
      address a = _envAddrOrZero(key);
      require(a != address(0), "missing underlying entry");
      arr[j] = a;
    }
  }

  // -------- tiny utils --------
  function _k(string memory prefix, string memory idx) internal pure returns (string memory) {
    return string.concat(prefix, idx);
  }

  function _envAddrOrZero(string memory key) internal returns (address a) {
    a = vm.envOr(key, address(0));
  }
}
