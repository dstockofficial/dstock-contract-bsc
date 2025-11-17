// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface IERC20Metadata {
  function decimals() external view returns (uint8);
  function balanceOf(address) external view returns (uint256);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 value) external returns (bool);
}

interface IMultiWrapper {
  function wrap(address token, uint256 amount, address to)
    external
    returns (uint256 net, uint256 mintedShares);
  function balanceOf(address) external view returns (uint256);
}

interface ICompliance {
  struct Flags {
    bool set;
    bool enforceSanctions;
    bool transferRestricted;
    bool wrapToCustodyOnly;
    bool unwrapFromCustodyOnly;
    bool kycOnWrap;
    bool kycOnUnwrap;
  }

  function getFlags(address token) external view returns (Flags memory);
  function kyc(address) external view returns (bool);
  function custody(address) external view returns (bool);
  function setKyc(address user, bool ok) external;
  function setCustody(address user, bool ok) external;
}

contract PrepComplianceAndWrap is Script {
  function run() external {
    console2.log("=run() (multi-underlying)");

    // ===== ENV =====
    address WRAPPER    = vm.envAddress("WRAPPER");
    address UNDERLYING = vm.envAddress("UNDERLYING");
    address COMPLIANCE = vm.envAddress("COMPLIANCE");
    uint256 PK         = vm.envUint("ADMIN_PK");
    require(WRAPPER != address(0), "WRAPPER env must be set");
    require(UNDERLYING != address(0), "UNDERLYING env must be set");
    require(COMPLIANCE != address(0), "COMPLIANCE env must be set");
    require(PK != 0, "ADMIN_PK env must be set");
    
    address CALLER     = vm.addr(PK);
    address TO         = vm.envOr("TO", CALLER);

    uint256 amountWei = vm.envOr("AMOUNT_WEI", uint256(0));
    if (amountWei == 0) {
      string memory amountHuman = vm.envOr("AMOUNT", string(""));
      require(bytes(amountHuman).length != 0, "Set AMOUNT or AMOUNT_WEI");
      amountWei = _parseToWei(amountHuman, IERC20Metadata(UNDERLYING).decimals());
    }

    vm.startBroadcast(PK);

    _prepareCompliance(WRAPPER, COMPLIANCE, CALLER, TO);

    _ensureAllowance(UNDERLYING, WRAPPER, CALLER, amountWei);

    (uint256 net, uint256 mintedShares) = IMultiWrapper(WRAPPER).wrap(UNDERLYING, amountWei, TO);

    vm.stopBroadcast();

    console2.log("Underlying:", UNDERLYING);
    console2.log("Wrapper   :", WRAPPER);
    console2.log("To        :", TO);
    console2.log("Amount(wei):", amountWei);
    console2.log("Wrap -> net          :", net);
    console2.log("Wrap -> mintedShares :", mintedShares);
    console2.log("Wrapper balance(To)  :", IMultiWrapper(WRAPPER).balanceOf(TO));
  }

  // ========= helpers =========

  function _prepareCompliance(
    address wrapper,
    address compliance,
    address caller,
    address to
  ) internal {
    ICompliance c = ICompliance(compliance);
    ICompliance.Flags memory f = c.getFlags(wrapper);
    console2.log("wrapToCustodyOnly:", f.wrapToCustodyOnly);
    console2.log("kycOnWrap:", f.kycOnWrap);

    if (f.wrapToCustodyOnly && !c.custody(to)) {
      c.setCustody(to, true);
      console2.log("Compliance: setCustody(TO) = true");
    }
    if (f.kycOnWrap && !c.kyc(caller)) {
      c.setKyc(caller, true);
      console2.log("Compliance: setKyc(CALLER) = true");
    }
  }

  function _ensureAllowance(
    address underlying,
    address wrapper,
    address owner,
    uint256 amountWei
  ) internal {
    IERC20Metadata u = IERC20Metadata(underlying);
    uint256 bal = u.balanceOf(owner);
    console2.log("Caller underlying balance:", bal);
    require(bal >= amountWei, "INSUFFICIENT_UNDERLYING_BALANCE");

    uint256 curAllow = u.allowance(owner, wrapper);
    console2.log("Current allowance:", curAllow);
    if (curAllow < amountWei) {
      require(u.approve(wrapper, type(uint256).max), "approve failed");
      console2.log("Approved underlying to wrapper (max).");
    }
  }

  /// Convert "123.456" to raw units using token decimals
  function _parseToWei(string memory s, uint8 decimals_) internal pure returns (uint256) {
    bytes memory b = bytes(s);
    uint256 intPart; uint256 fracPart; uint8 fracLen; bool dot;
    for (uint256 i = 0; i < b.length; i++) {
      bytes1 ch = b[i];
      if (ch == 0x2e) { require(!dot, "bad num"); dot = true; continue; }
      require(ch >= 0x30 && ch <= 0x39, "bad char");
      if (!dot) { intPart = intPart * 10 + (uint8(ch) - 48); }
      else if (fracLen < decimals_) { fracPart = fracPart * 10 + (uint8(ch) - 48); fracLen++; }
    }
    uint256 factor = 10 ** decimals_;
    uint256 weiInt = intPart * factor;
    uint256 weiFrac = (fracLen == 0) ? 0 : (fracPart * (factor / (10 ** fracLen)));
    return weiInt + weiFrac;
  }
}
