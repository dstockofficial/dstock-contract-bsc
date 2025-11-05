// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {DStockFactoryRegistry} from "../src/DStockFactoryRegistry.sol";
import {DStockWrapper} from "../src/DStockWrapper.sol";
import {IDStockWrapper} from "../src/interfaces/IDStockWrapper.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// minimal beacon interface to read implementation
interface IBeacon {
  function implementation() external view returns (address);
}

// ERC20 mock used as real underlying tokens
contract MockERC20 is ERC20 {
  constructor(string memory n, string memory s) ERC20(n, s) {}
}

// a dummy wrapper used to test migrate new binding (if you later add migrate tests)
contract DummyWrapper { }

contract FactoryTest is Test {
  // ---------- actors ----------
  address ADMIN    = address(0xA11CE);
  address OP       = address(0x0101);
  address PAUSER   = address(0x1122);
  address STRANGER = address(0xBEEF);

  // ---------- contracts ----------
  DStockFactoryRegistry factory;
  DStockWrapper implV1;
  DStockWrapper implV2;

  // ---------- roles ----------
  bytes32 OPERATOR_ROLE;
  bytes32 PAUSER_ROLE;
  bytes32 DEFAULT_ADMIN_ROLE;

  // ---------- real ERC20 underlyings (deployed in setUp) ----------
  MockERC20 token1;
  MockERC20 token2;
  MockERC20 token3;
  address   U1;
  address   U2;
  address   U3;

  address GLOBAL_COMPLIANCE = address(0); // not needed in these tests

  // created wrapper
  address W;

  function setUp() public {
    // deploy initial implementation
    implV1 = new DStockWrapper();

    // deploy factory (beacon owner = factory itself)
    vm.prank(ADMIN);
    factory = new DStockFactoryRegistry(
      ADMIN,
      address(implV1),
      GLOBAL_COMPLIANCE
    );

    // cache roles
    OPERATOR_ROLE      = factory.OPERATOR_ROLE();
    PAUSER_ROLE        = factory.PAUSER_ROLE();
    DEFAULT_ADMIN_ROLE = factory.DEFAULT_ADMIN_ROLE();

    // grant OPERATOR/PAUSER
    vm.prank(ADMIN);
    factory.grantRole(OPERATOR_ROLE, OP);

    vm.prank(ADMIN);
    factory.grantRole(PAUSER_ROLE, PAUSER);

    // ---- deploy real ERC20 tokens as underlyings ----
    token1 = new MockERC20("U1", "U1");
    token2 = new MockERC20("U2", "U2");
    token3 = new MockERC20("U3", "U3");
    U1 = address(token1);
    U2 = address(token2);
    U3 = address(token3);
  }

  // ------------------------------------------------
  // Create wrapper with MULTIPLE underlyings: authorized (OPERATOR_ROLE)
  // ------------------------------------------------
  function test_CreateWrapper_MultiUnderlyings_Authorized() public {
    address[] memory initU = new address[](2);
    initU[0] = U1;
    initU[1] = U2;

    vm.prank(OP);
    W = factory.createWrapper(
      IDStockWrapper.InitParams({
        // roles / pointers
        admin: ADMIN,
        factoryRegistry: address(0),

        // token meta
        initialUnderlyings: initU,
        name: "dASSET",
        symbol: "dAST",
        decimalsOverride: 0,

        // compliance / fees / limits
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "https://terms",

        // accounting params
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );

    // for each underlying -> wrapper mapping exists
    assertEq(factory.getWrapper(U1), W, "wrapperOf(U1) not set");
    assertEq(factory.getWrapper(U2), W, "wrapperOf(U2) not set");

    // wrapper exposes its underlyings
    address[] memory listed = DStockWrapper(W).listUnderlyings();

    // order not strictly guaranteed; check membership
    bool hasU1; bool hasU2;
    for (uint256 i = 0; i < listed.length; i++) {
      if (listed[i] == U1) hasU1 = true;
      if (listed[i] == U2) hasU2 = true;
    }
    assertTrue(hasU1 && hasU2, "listUnderlyings() should include U1 & U2");

    // registry counters
    assertEq(factory.countWrappers(), 1, "countWrappers should be 1");
  }

  // ------------------------------------------------
  // Create wrapper: unauthorized (no OPERATOR_ROLE)
  // ------------------------------------------------
  function test_CreateWrapper_Unauthorized_Revert() public {
    address[] memory initU = new address[](1);
    initU[0] = U1;

    vm.prank(STRANGER);
    vm.expectRevert();
    factory.createWrapper(
      IDStockWrapper.InitParams({
        admin: ADMIN,
        factoryRegistry: address(0),
        initialUnderlyings: initU,
        name: "dX",
        symbol: "dX",
        decimalsOverride: 0,
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "https://terms",
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );
  }

  // ------------------------------------------------
  // Create wrapper: duplicate underlying allowed across different wrappers (multi-wrapper support)
  // ------------------------------------------------
  function test_CreateWrapper_DuplicateUnderlying_AllowsMultiple() public {
    // first wrapper uses U1
    address[] memory initU1 = new address[](1);
    initU1[0] = U1;

    vm.prank(OP);
    factory.createWrapper(
      IDStockWrapper.InitParams({
        admin: ADMIN,
        factoryRegistry: address(0),
        initialUnderlyings: initU1,
        name: "dU1",
        symbol: "dU1",
        decimalsOverride: 0,
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "https://terms",
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );

    // second wrapper tries to reuse U1 -> revert
    address[] memory initU2 = new address[](2);
    initU2[0] = U1;      // duplicate
    initU2[1] = U2;

    vm.prank(OP);
    address w2 = factory.createWrapper(
      IDStockWrapper.InitParams({
        admin: ADMIN,
        factoryRegistry: address(0),
        initialUnderlyings: initU2,
        name: "dU1_bis",
        symbol: "dU1_bis",
        decimalsOverride: 0,
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "https://terms",
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );
    assertTrue(w2 != address(0), "second wrapper not created");

    // Ensure underlying U1 maps to both wrappers
    address[] memory ws = factory.getWrappers(U1);
    bool hasFirst;
    bool hasSecond;
    for (uint256 i = 0; i < ws.length; i++) {
      if (ws[i] != address(0)) {
        if (ws[i] == factory.getWrapper(U1)) hasFirst = true; // first in list for compat
        if (ws[i] == w2) hasSecond = true;
      }
    }
    assertTrue(hasSecond, "U1 should map to the second wrapper as well");
  }

  // ------------------------------------------------
  // Role grant/revoke affects permissions (createWrapper)
  // ------------------------------------------------
  function test_GrantRevoke_Role_Effect() public {
    // revoke OPERATOR
    vm.prank(ADMIN);
    factory.revokeRole(OPERATOR_ROLE, OP);

    address[] memory initU = new address[](1);
    initU[0] = U3;

    vm.prank(OP);
    vm.expectRevert();
    factory.createWrapper(
      IDStockWrapper.InitParams({
        admin: ADMIN,
        factoryRegistry: address(0),
        initialUnderlyings: initU,
        name: "dNew",
        symbol: "dNew",
        decimalsOverride: 0,
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "https://terms",
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );

    // grant back -> should succeed
    vm.prank(ADMIN);
    factory.grantRole(OPERATOR_ROLE, OP);

    vm.prank(OP);
    address w = factory.createWrapper(
      IDStockWrapper.InitParams({
        admin: ADMIN,
        factoryRegistry: address(0),
        initialUnderlyings: initU,
        name: "dNew",
        symbol: "dNew",
        decimalsOverride: 0,
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "https://terms",
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );
    assertTrue(w != address(0));
  }

  // ------------------------------------------------
  // Upgrade beacon: authorized (DEFAULT_ADMIN_ROLE)
  // ------------------------------------------------
  function test_SetWrapperImplementation_Authorized() public {
    implV2 = new DStockWrapper();

    address beaconAddr = address(factory.beacon());
    address oldImpl = IBeacon(beaconAddr).implementation();

    vm.expectEmit(true, true, true, true);
    emit DStockFactoryRegistry.WrapperImplementationUpgraded(oldImpl, address(implV2));

    vm.prank(ADMIN);
    factory.setWrapperImplementation(address(implV2));

    assertEq(IBeacon(beaconAddr).implementation(), address(implV2), "impl not updated");
  }

  // ------------------------------------------------
  // Upgrade beacon: unauthorized
  // ------------------------------------------------
  function test_SetWrapperImplementation_Unauthorized_Revert() public {
    implV2 = new DStockWrapper();

    vm.prank(STRANGER);
    vm.expectRevert();
    factory.setWrapperImplementation(address(implV2));
  }

  // ------------------------------------------------
  // Pause wrapper by factory: authorized (PAUSER_ROLE)
  // ------------------------------------------------
  function test_PauseWrapper_ByFactory_Authorized() public {
    address[] memory initU = new address[](1);
    initU[0] = U1;

    vm.prank(OP);
    W = factory.createWrapper(
      IDStockWrapper.InitParams({
        admin: ADMIN,
        factoryRegistry: address(0),
        initialUnderlyings: initU,
        name: "dU1",
        symbol: "dU1",
        decimalsOverride: 0,
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "https://terms",
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );

    vm.expectEmit(true, true, false, true);
    emit DStockFactoryRegistry.WrapperPausedByFactory(W, true);

    vm.prank(PAUSER);
    factory.pauseWrapper(W, true);

    // unpause
    vm.prank(PAUSER);
    factory.pauseWrapper(W, false);
  }

  // ------------------------------------------------
  // Pause wrapper: unauthorized MUST hit onlyRole
  // ------------------------------------------------
  function test_PauseWrapper_Unauthorized_Revert() public {
    address[] memory initU = new address[](1);
    initU[0] = U1;

    vm.prank(OP);
    W = factory.createWrapper(
      IDStockWrapper.InitParams({
        admin: ADMIN,
        factoryRegistry: address(0),
        initialUnderlyings: initU,
        name: "dU1",
        symbol: "dU1",
        decimalsOverride: 0,
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "https://terms",
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );

    vm.prank(STRANGER);
    vm.expectRevert();
    factory.pauseWrapper(W, true);
  }

  // ------------------------------------------------
  // Pause wrapper: NotRegistered
  // ------------------------------------------------
  function test_PauseWrapper_NotRegistered_Revert() public {
    vm.prank(PAUSER);
    vm.expectRevert(DStockFactoryRegistry.NotRegistered.selector);
    factory.pauseWrapper(address(0xDEAD), true);
  }

  // ------------------------------------------------
  // Helper: read beacon implementation
  // ------------------------------------------------
  function _beaconImpl() internal view returns (address) {
    return IBeacon(address(factory.beacon())).implementation();
  }
}
