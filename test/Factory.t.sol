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

  /// @dev Mint helper used only in tests.
  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
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
  // Multi-wrapper getters and per-wrapper ops
  // ------------------------------------------------
  function test_GetWrappers_MultipleAndFirstCompat() public {
    // first wrapper with U1
    address[] memory a = new address[](1); a[0] = U1;
    vm.prank(OP);
    address w1 = factory.createWrapper(IDStockWrapper.InitParams({
      admin: ADMIN, factoryRegistry: address(0), initialUnderlyings: a,
      name: "d1", symbol: "d1", decimalsOverride: 0,
      compliance: address(0), treasury: address(0), wrapFeeBps: 0, unwrapFeeBps: 0, cap: 0, termsURI: "t",
      initialMultiplierRay: 1e18, feePerPeriodRay: 0, periodLength: 0, feeModel: 0
    }));

    // second wrapper reuses U1
    address[] memory b = new address[](1); b[0] = U1;
    vm.prank(OP);
    address w2 = factory.createWrapper(IDStockWrapper.InitParams({
      admin: ADMIN, factoryRegistry: address(0), initialUnderlyings: b,
      name: "d2", symbol: "d2", decimalsOverride: 0,
      compliance: address(0), treasury: address(0), wrapFeeBps: 0, unwrapFeeBps: 0, cap: 0, termsURI: "t",
      initialMultiplierRay: 1e18, feePerPeriodRay: 0, periodLength: 0, feeModel: 0
    }));

    address[] memory ws = factory.getWrappers(U1);
    assertEq(ws.length, 2, "U1 should have 2 wrappers");
    // compat getter returns first in list (w1)
    assertEq(factory.getWrapper(U1), ws[0]);
    // ensure second exists
    bool found;
    for (uint256 i = 0; i < ws.length; i++) if (ws[i] == w2) found = true;
    assertTrue(found, "second wrapper not in list");
  }

  function test_SetUnderlyingStatusForWrapper_AffectsTargetOnly() public {
    // create two wrappers sharing U1
    address[] memory a = new address[](1); a[0] = U1;
    vm.prank(OP);
    address w1 = factory.createWrapper(IDStockWrapper.InitParams({
      admin: ADMIN, factoryRegistry: address(0), initialUnderlyings: a,
      name: "d1", symbol: "d1", decimalsOverride: 0,
      compliance: address(0), treasury: address(0), wrapFeeBps: 0, unwrapFeeBps: 0, cap: 0, termsURI: "t",
      initialMultiplierRay: 1e18, feePerPeriodRay: 0, periodLength: 0, feeModel: 0
    }));
    vm.prank(OP);
    address w2 = factory.createWrapper(IDStockWrapper.InitParams({
      admin: ADMIN, factoryRegistry: address(0), initialUnderlyings: a,
      name: "d2", symbol: "d2", decimalsOverride: 0,
      compliance: address(0), treasury: address(0), wrapFeeBps: 0, unwrapFeeBps: 0, cap: 0, termsURI: "t",
      initialMultiplierRay: 1e18, feePerPeriodRay: 0, periodLength: 0, feeModel: 0
    }));

    // disable on w1 only
    vm.prank(OP);
    factory.setUnderlyingStatusForWrapper(w1, U1, false);
    (bool e1,,) = IDStockWrapper(w1).underlyingInfo(U1);
    (bool e2,,) = IDStockWrapper(w2).underlyingInfo(U1);
    assertTrue(!e1 && e2, "disable should affect only target wrapper");
  }

  function test_RemoveUnderlyingMappingForWrapper_OnlyRemovesOne() public {
    address[] memory a = new address[](1); a[0] = U1;
    vm.prank(OP);
    address w1 = factory.createWrapper(IDStockWrapper.InitParams({
      admin: ADMIN, factoryRegistry: address(0), initialUnderlyings: a,
      name: "d1", symbol: "d1", decimalsOverride: 0,
      compliance: address(0), treasury: address(0), wrapFeeBps: 0, unwrapFeeBps: 0, cap: 0, termsURI: "t",
      initialMultiplierRay: 1e18, feePerPeriodRay: 0, periodLength: 0, feeModel: 0
    }));
    vm.prank(OP);
    address w2 = factory.createWrapper(IDStockWrapper.InitParams({
      admin: ADMIN, factoryRegistry: address(0), initialUnderlyings: a,
      name: "d2", symbol: "d2", decimalsOverride: 0,
      compliance: address(0), treasury: address(0), wrapFeeBps: 0, unwrapFeeBps: 0, cap: 0, termsURI: "t",
      initialMultiplierRay: 1e18, feePerPeriodRay: 0, periodLength: 0, feeModel: 0
    }));

    address[] memory before = factory.getWrappers(U1);
    assertEq(before.length, 2);

    vm.prank(OP);
    factory.removeUnderlyingMappingForWrapper(w1, U1);

    address[] memory afterList = factory.getWrappers(U1);
    assertEq(afterList.length, 1, "should remove only one mapping");
    assertEq(afterList[0], w2, "remaining should be second wrapper");
    (bool enabled,,) = IDStockWrapper(w1).underlyingInfo(U1);
    assertTrue(!enabled, "underlying should be disabled on removed wrapper");
  }

  function test_AddUnderlyings_NoDuplicateMapping() public {
    // create wrapper with no underlyings then add same token twice
    address[] memory empty = new address[](0);
    vm.prank(OP);
    address w = factory.createWrapper(IDStockWrapper.InitParams({
      admin: ADMIN, factoryRegistry: address(0), initialUnderlyings: empty,
      name: "dZ", symbol: "dZ", decimalsOverride: 0,
      compliance: address(0), treasury: address(0), wrapFeeBps: 0, unwrapFeeBps: 0, cap: 0, termsURI: "t",
      initialMultiplierRay: 1e18, feePerPeriodRay: 0, periodLength: 0, feeModel: 0
    }));

    address[] memory tok = new address[](1); tok[0] = U3;
    vm.prank(OP);
    factory.addUnderlyings(w, tok);
    // add same again
    vm.prank(OP);
    factory.addUnderlyings(w, tok);

    address[] memory ws = factory.getWrappers(U3);
    assertEq(ws.length, 1, "no duplicate mapping expected");
    assertEq(ws[0], w);
  }

  // Re-add previously removed underlying and wrap again (audit Issue‑10 suggested testcase)
  function test_ReAddUnderlyingAfterRemove_CanWrapAgain() public {
    // 1) Create a wrapper with U1 as initial underlying
    address[] memory initU = new address[](1);
    initU[0] = U1;
    vm.prank(OP);
    address w = factory.createWrapper(IDStockWrapper.InitParams({
      admin: ADMIN, factoryRegistry: address(0), initialUnderlyings: initU,
      name: "d1", symbol: "d1", decimalsOverride: 0,
      compliance: address(0), treasury: address(0), wrapFeeBps: 0, unwrapFeeBps: 0, cap: 0, termsURI: "t",
      initialMultiplierRay: 1e18, feePerPeriodRay: 0, periodLength: 0, feeModel: 0
    }));

    DStockWrapper dw = DStockWrapper(w);

    // 2) First wrap by ADMIN (OPERATOR_ROLE) to bootstrap initial shares
    token1.mint(ADMIN, 10 ether);
    vm.startPrank(ADMIN);
    token1.approve(w, type(uint256).max);
    dw.wrap(U1, 1 ether, ADMIN);
    vm.stopPrank();

    // 3) Remove the mapping between U1 and the wrapper via the factory (also disables it on the wrapper)
    vm.prank(OP);
    factory.removeUnderlyingMappingForWrapper(w, U1);
    (bool enabled,,) = dw.underlyingInfo(U1);
    assertFalse(enabled, "underlying should be disabled after remove");

    // 4) Add U1 again via the factory and re‑enable it
    address[] memory tok = new address[](1);
    tok[0] = U1;
    vm.prank(OP);
    factory.addUnderlyings(w, tok);

    (enabled,,) = dw.underlyingInfo(U1);
    assertTrue(enabled, "underlying should be re-enabled after addUnderlyings");

    // 5) Wrap again to ensure the "remove → re‑add → reuse" flow works
    vm.startPrank(ADMIN);
    dw.wrap(U1, 1 ether, ADMIN);
    vm.stopPrank();
  }

  function test_Deprecate_MarksFlag() public {
    address[] memory a = new address[](1); a[0] = U1;
    vm.prank(OP);
    address w = factory.createWrapper(IDStockWrapper.InitParams({
      admin: ADMIN, factoryRegistry: address(0), initialUnderlyings: a,
      name: "d1", symbol: "d1", decimalsOverride: 0,
      compliance: address(0), treasury: address(0), wrapFeeBps: 0, unwrapFeeBps: 0, cap: 0, termsURI: "t",
      initialMultiplierRay: 1e18, feePerPeriodRay: 0, periodLength: 0, feeModel: 0
    }));
    vm.prank(ADMIN);
    factory.deprecate(w, "old");
    assertTrue(factory.deprecated(w));
    assertEq(factory.deprecateReason(w), "old");
  }

  // addUnderlyings on a deprecated wrapper should revert (audit Issue‑13 suggested testcase)
  function test_AddUnderlyings_OnDeprecatedWrapper_Revert() public {
    address[] memory a = new address[](0);
    vm.prank(OP);
    address w = factory.createWrapper(IDStockWrapper.InitParams({
      admin: ADMIN, factoryRegistry: address(0), initialUnderlyings: a,
      name: "dD", symbol: "dD", decimalsOverride: 0,
      compliance: address(0), treasury: address(0), wrapFeeBps: 0, unwrapFeeBps: 0, cap: 0, termsURI: "t",
      initialMultiplierRay: 1e18, feePerPeriodRay: 0, periodLength: 0, feeModel: 0
    }));

    vm.prank(ADMIN);
    factory.deprecate(w, "deprecated");

    address[] memory tok = new address[](1);
    tok[0] = U1;

    vm.prank(OP);
    // Expect InvalidParams("deprecated wrapper"); here we only assert revert, not the full encoded error.
    vm.expectRevert();
    factory.addUnderlyings(w, tok);
  }

  // Multi-wrapper + deprecation scenario: deprecate one wrapper, keep historical mapping, but forbid adding new underlyings to it
  function test_Deprecate_OneOfMultipleWrappers_Behavior() public {
    // 1) Create two wrappers that both include U1
    address[] memory a = new address[](1);
    a[0] = U1;

    vm.prank(OP);
    address w1 = factory.createWrapper(IDStockWrapper.InitParams({
      admin: ADMIN, factoryRegistry: address(0), initialUnderlyings: a,
      name: "d1", symbol: "d1", decimalsOverride: 0,
      compliance: address(0), treasury: address(0), wrapFeeBps: 0, unwrapFeeBps: 0, cap: 0, termsURI: "t",
      initialMultiplierRay: 1e18, feePerPeriodRay: 0, periodLength: 0, feeModel: 0
    }));

    vm.prank(OP);
    address w2 = factory.createWrapper(IDStockWrapper.InitParams({
      admin: ADMIN, factoryRegistry: address(0), initialUnderlyings: a,
      name: "d2", symbol: "d2", decimalsOverride: 0,
      compliance: address(0), treasury: address(0), wrapFeeBps: 0, unwrapFeeBps: 0, cap: 0, termsURI: "t",
      initialMultiplierRay: 1e18, feePerPeriodRay: 0, periodLength: 0, feeModel: 0
    }));

    // 2) Deprecate w1
    vm.prank(ADMIN);
    factory.deprecate(w1, "deprecated");
    assertTrue(factory.deprecated(w1));

    // 3) U1 should still map to both wrappers (historical record)
    address[] memory ws = factory.getWrappers(U1);
    assertEq(ws.length, 2, "U1 should still map to two wrappers");

    bool foundW1;
    bool foundW2;
    for (uint256 i = 0; i < ws.length; i++) {
      if (ws[i] == w1) foundW1 = true;
      if (ws[i] == w2) foundW2 = true;
    }
    assertTrue(foundW1 && foundW2, "both wrappers should appear in mapping");

    // 4) Calling addUnderlyings on deprecated w1 must fail
    address[] memory tok = new address[](1);
    tok[0] = U2;
    vm.prank(OP);
    // Expect InvalidParams("deprecated wrapper"); here we only assert revert, not the full encoded error.
    vm.expectRevert();
    factory.addUnderlyings(w1, tok);

    // 5) Calling addUnderlyings on non‑deprecated w2 must succeed
    vm.prank(OP);
    factory.addUnderlyings(w2, tok);

    address[] memory wrappersForU2 = factory.getWrappers(U2);
    assertEq(wrappersForU2.length, 1);
    assertEq(wrappersForU2[0], w2);
  }

  function test_SetUnderlyingStatusForWrapper_NotRegistered_Revert() public {
    address[] memory a = new address[](1); a[0] = U1;
    vm.prank(OP);
    address w = factory.createWrapper(IDStockWrapper.InitParams({
      admin: ADMIN, factoryRegistry: address(0), initialUnderlyings: a,
      name: "d1", symbol: "d1", decimalsOverride: 0,
      compliance: address(0), treasury: address(0), wrapFeeBps: 0, unwrapFeeBps: 0, cap: 0, termsURI: "t",
      initialMultiplierRay: 1e18, feePerPeriodRay: 0, periodLength: 0, feeModel: 0
    }));
    vm.prank(OP);
    vm.expectRevert(DStockFactoryRegistry.NotRegistered.selector);
    factory.setUnderlyingStatusForWrapper(w, U2, false);
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
  // Global compliance setter
  // ------------------------------------------------
  function test_SetGlobalCompliance_Update_And_SameAddress_Revert() public {
    // initial is GLOBAL_COMPLIANCE (0); set to non-zero
    address newC = address(0x1234);

    vm.prank(OP);
    factory.setGlobalCompliance(newC);
    assertEq(factory.globalCompliance(), newC, "globalCompliance not updated");

    // setting to same address should revert with SameAddress
    vm.prank(OP);
    vm.expectRevert(DStockFactoryRegistry.SameAddress.selector);
    factory.setGlobalCompliance(newC);
  }

  // ------------------------------------------------
  // Pagination: getAllWrappers(offset, limit)
  // ------------------------------------------------
  function test_GetAllWrappers_Pagination() public {
    // create three wrappers so that allWrappers has deterministic order
    address[] memory a = new address[](1);
    a[0] = U1;
    vm.prank(OP);
    address w1 = factory.createWrapper(
      IDStockWrapper.InitParams({
        admin: ADMIN,
        factoryRegistry: address(0),
        initialUnderlyings: a,
        name: "d1",
        symbol: "d1",
        decimalsOverride: 0,
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "t1",
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );

    address[] memory b = new address[](1);
    b[0] = U2;
    vm.prank(OP);
    address w2 = factory.createWrapper(
      IDStockWrapper.InitParams({
        admin: ADMIN,
        factoryRegistry: address(0),
        initialUnderlyings: b,
        name: "d2",
        symbol: "d2",
        decimalsOverride: 0,
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "t2",
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );

    address[] memory c = new address[](1);
    c[0] = U3;
    vm.prank(OP);
    address w3 = factory.createWrapper(
      IDStockWrapper.InitParams({
        admin: ADMIN,
        factoryRegistry: address(0),
        initialUnderlyings: c,
        name: "d3",
        symbol: "d3",
        decimalsOverride: 0,
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "t3",
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );

    assertEq(factory.countWrappers(), 3, "countWrappers should be 3");

    // page 0..2 (limit 2) -> [w1, w2]
    address[] memory page = factory.getAllWrappers(0, 2);
    assertEq(page.length, 2);
    assertEq(page[0], w1);
    assertEq(page[1], w2);

    // page 1..3 (limit 2) -> [w2, w3]
    page = factory.getAllWrappers(1, 2);
    assertEq(page.length, 2);
    assertEq(page[0], w2);
    assertEq(page[1], w3);

    // page near end; limit larger than remaining -> truncated to 1
    page = factory.getAllWrappers(2, 10);
    assertEq(page.length, 1);
    assertEq(page[0], w3);

    // offset >= countWrappers -> empty
    page = factory.getAllWrappers(3, 1);
    assertEq(page.length, 0);
  }

  // ------------------------------------------------
  // addUnderlyings edge cases (deprecated wrapper, empty tokens)
  // ------------------------------------------------
  function test_AddUnderlyings_RevertOnDeprecatedOrEmptyTokens() public {
    // create wrapper with a single underlying
    address[] memory a = new address[](1);
    a[0] = U1;
    vm.prank(OP);
    address w = factory.createWrapper(
      IDStockWrapper.InitParams({
        admin: ADMIN,
        factoryRegistry: address(0),
        initialUnderlyings: a,
        name: "dA",
        symbol: "dA",
        decimalsOverride: 0,
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "tA",
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );

    // empty tokens array -> InvalidParams("empty tokens")
    address[] memory empty = new address[](0);
    vm.prank(OP);
    vm.expectRevert(
      abi.encodeWithSelector(
        DStockFactoryRegistry.InvalidParams.selector,
        "empty tokens"
      )
    );
    factory.addUnderlyings(w, empty);

    // deprecate wrapper -> addUnderlyings should revert with InvalidParams("deprecated wrapper")
    vm.prank(OP);
    factory.deprecate(w, "deprecated");

    address[] memory tok = new address[](1);
    tok[0] = U2;
    vm.prank(OP);
    vm.expectRevert(
      abi.encodeWithSelector(
        DStockFactoryRegistry.InvalidParams.selector,
        "deprecated wrapper"
      )
    );
    factory.addUnderlyings(w, tok);
  }

  // ------------------------------------------------
  // removeUnderlyingMappingForWrapper: NotRegistered path
  // ------------------------------------------------
  function test_RemoveUnderlyingMappingForWrapper_NotRegistered_Revert() public {
    address[] memory a = new address[](1);
    a[0] = U1;
    vm.prank(OP);
    address w = factory.createWrapper(
      IDStockWrapper.InitParams({
        admin: ADMIN,
        factoryRegistry: address(0),
        initialUnderlyings: a,
        name: "d1",
        symbol: "d1",
        decimalsOverride: 0,
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "t",
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );

    // U2 was never mapped to w -> NotRegistered
    vm.prank(OP);
    vm.expectRevert(DStockFactoryRegistry.NotRegistered.selector);
    factory.removeUnderlyingMappingForWrapper(w, U2);
  }

  // ------------------------------------------------
  // createWrapper: invalid inputs (zero address in initialUnderlyings)
  // ------------------------------------------------
  function test_CreateWrapper_InitialUnderlyings_ZeroAddress_Revert() public {
    address[] memory initU = new address[](2);
    initU[0] = U1;
    initU[1] = address(0);

    vm.prank(OP);
    vm.expectRevert(DStockFactoryRegistry.ZeroAddress.selector);
    factory.createWrapper(
      IDStockWrapper.InitParams({
        admin: ADMIN,
        factoryRegistry: address(0),
        initialUnderlyings: initU,
        name: "dBad",
        symbol: "dBad",
        decimalsOverride: 0,
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "tBad",
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );
  }

  // ------------------------------------------------
  // createWrapper: caller-supplied factoryRegistry is ignored and overwritten to factory address
  // ------------------------------------------------
  function test_CreateWrapper_OverridesFactoryRegistryToSelf() public {
    address[] memory initU = new address[](1);
    initU[0] = U1;

    vm.prank(OP);
    address w = factory.createWrapper(
      IDStockWrapper.InitParams({
        admin: ADMIN,
        factoryRegistry: address(0xDEAD), // will be overridden inside createWrapper
        initialUnderlyings: initU,
        name: "dF",
        symbol: "dF",
        decimalsOverride: 0,
        compliance: address(0),
        treasury: address(0),
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "tF",
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      })
    );

    assertEq(IDStockWrapper(w).factoryRegistry(), address(factory), "factoryRegistry should be factory");
  }

  // ------------------------------------------------
  // Helper: read beacon implementation
  // ------------------------------------------------
  function _beaconImpl() internal view returns (address) {
    return IBeacon(address(factory.beacon())).implementation();
  }
}
