// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DStockWrapper} from "../src/DStockWrapper.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {DStockCompliance} from "../src/DStockCompliance.sol";
import {IDStockWrapper} from "../src/interfaces/IDStockWrapper.sol"; 

contract MockERC20 is ERC20 {
  constructor(string memory n, string memory s) ERC20(n, s) {}
  function mint(address to, uint256 a) external { _mint(to, a); }
}

/// @dev Rebase-style ERC20 used for audit scenarios: can mint/burn arbitrarily to simulate positive/negative rebases.
contract MockRebaseERC20 is ERC20 {
  constructor(string memory n, string memory s) ERC20(n, s) {}

  function mint(address to, uint256 a) external { _mint(to, a); }

  function burn(address from, uint256 a) external { _burn(from, a); }
}

contract WrapperTest is Test {
  // ---- actors ----
  address ADMIN  = address(0xA11CE);
  address ALICE  = address(0xA1);
  address BOB    = address(0xB2);
  address CUST   = address(0xC3);
  address STRANG = address(0xBEEF);
  address TREAS  = address(0xFEE);

  // ---- contracts ----
  MockERC20        usdc;
  DStockCompliance comp;
  DStockWrapper    wrapper;

  /// @dev Deploy a new DStockWrapper (via BeaconProxy) for a given underlying, reusing the existing compliance module and role setup.
  function _deployWrapperForUnderlying(address token) internal returns (DStockWrapper) {
    DStockWrapper impl = new DStockWrapper();
    UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));

    address[] memory initialU = new address[](1);
    initialU[0] = token;

    IDStockWrapper.InitParams memory p = IDStockWrapper.InitParams({
      // roles / pointers
      admin: ADMIN,
      factoryRegistry: ADMIN,

      // token meta
      initialUnderlyings: initialU,
      name: "dREB",
      symbol: "dREB",
      decimalsOverride: 0,

      // compliance / fees / limits
      compliance: address(comp),
      treasury: TREAS,
      wrapFeeBps: 0,
      unwrapFeeBps: 0,
      cap: 0,
      termsURI: "https://terms",

      // accounting params (currently unused in implementation, kept for struct completeness)
      initialMultiplierRay: 1e18,
      feePerPeriodRay: 0,
      periodLength: 0,
      feeModel: 0
    });

    bytes memory initData = abi.encodeWithSelector(DStockWrapper.initialize.selector, p);
    return DStockWrapper(address(new BeaconProxy(address(beacon), initData)));
  }

  function setUp() public {
    // 1) underlying + compliance
    usdc = new MockERC20("USDC", "USDC");
    comp = new DStockCompliance(ADMIN);

    // grant operator to ADMIN and set global flags explicitly
    vm.startPrank(ADMIN);
    comp.grantRole(comp.OPERATOR_ROLE(), ADMIN);
    DStockCompliance.Flags memory g = DStockCompliance.Flags({
      set: true,
      enforceSanctions: true,
      transferRestricted: false,
      wrapToCustodyOnly: false,
      unwrapFromCustodyOnly: false,
      kycOnWrap: true,
      kycOnUnwrap: true
    });
    comp.setFlagsGlobal(g);

    // give KYC to ALICE and ADMIN (BOB no KYC initially)
    comp.setKyc(ALICE, true);
    comp.setKyc(ADMIN, true);
    vm.stopPrank();

    // 2) wrapper via BeaconProxy: use initialUnderlyings
    DStockWrapper impl = new DStockWrapper();
    UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
    address[] memory initialU = new address[](1);
    initialU[0] = address(usdc);
    IDStockWrapper.InitParams memory p = IDStockWrapper.InitParams({
        // roles / pointers
        admin: ADMIN,
        factoryRegistry: ADMIN,

        // token meta
        initialUnderlyings: initialU,
        name: "dUSDC",
        symbol: "dUSDC",
        decimalsOverride: 0,

        // compliance / fees / limits
        compliance: address(comp),
        treasury: TREAS,
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "https://terms",

        // accounting params (ignored by current impl)
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      });
    bytes memory initData = abi.encodeWithSelector(DStockWrapper.initialize.selector, p);
    wrapper = DStockWrapper(address(new BeaconProxy(address(beacon), initData)));

    // 3) funds + approvals for ALICE by default
    usdc.mint(ALICE, 1_000_000 ether);
    vm.startPrank(ALICE);
    usdc.approve(address(wrapper), type(uint256).max);
    vm.stopPrank();
  }

  // wrap basic
  function test_Wrap_Success() public {
    // First wrap must be done by OPERATOR_ROLE with minimum 1e18
    usdc.mint(ADMIN, 1000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 100 ether, ADMIN); // initial wrap by operator
    vm.stopPrank();

    // Now regular users can wrap
    uint256 beforeU = usdc.balanceOf(ALICE);
    vm.prank(ALICE);
    (uint256 net, uint256 s) = wrapper.wrap(address(usdc), 100 ether, ALICE);
    assertEq(usdc.balanceOf(ALICE), beforeU - 100 ether, "underlying not moved");
    assertEq(net, 100 ether, "net mismatch");
    assertEq(s, 100 ether, "shares minted mismatch");
    assertEq(wrapper.balanceOf(ALICE), 100 ether, "wrapper balance mismatch");
  }

  function test_Wrap_Fail_KycOnWrap_From() public {
    usdc.mint(BOB, 100 ether);
    vm.startPrank(BOB);
    usdc.approve(address(wrapper), type(uint256).max);
    vm.expectRevert(DStockWrapper.NotAllowed.selector);
    wrapper.wrap(address(usdc), 1 ether, BOB);
    vm.stopPrank();
  }

  function test_Wrap_Fail_ToMustBeCustody_WhenFlagOn() public {
    // First wrap by operator
    usdc.mint(ADMIN, 100 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    DStockCompliance.Flags memory t = comp.getFlags(address(wrapper));
    t.wrapToCustodyOnly = true;
    comp.setFlagsForToken(address(wrapper), t);
    vm.stopPrank();

    vm.prank(ALICE);
    vm.expectRevert(DStockWrapper.NotAllowed.selector);
    wrapper.wrap(address(usdc), 1 ether, ALICE);

    vm.prank(ADMIN);
    comp.setCustody(CUST, true);
    vm.prank(ALICE);
    (uint256 net, uint256 s) = wrapper.wrap(address(usdc), 2 ether, CUST);
    assertEq(net, 2 ether);
    assertEq(s, 2 ether);
    assertEq(wrapper.balanceOf(CUST), 2 ether);
  }

  function test_Wrap_Fail_InsufficientAllowance() public {
    // First wrap by operator
    usdc.mint(ADMIN, 100 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    vm.stopPrank();

    vm.prank(ALICE);
    usdc.approve(address(wrapper), 0);
    vm.prank(ALICE);
    vm.expectRevert();
    wrapper.wrap(address(usdc), 1 ether, ALICE);
  }

  function test_Wrap_Fail_Paused() public {
    // First wrap by operator
    usdc.mint(ADMIN, 100 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    vm.stopPrank();

    vm.prank(ADMIN);
    wrapper.pause();
    vm.prank(ALICE);
    vm.expectRevert();
    wrapper.wrap(address(usdc), 1 ether, ALICE);
    vm.prank(ADMIN);
    wrapper.unpause();
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 1 ether, ALICE);
    assertEq(wrapper.balanceOf(ALICE), 1 ether);
  }

  // First wrap restrictions
  function test_FirstWrap_RequiresOperatorRole() public {
    usdc.mint(ALICE, 100 ether);
    vm.prank(ALICE);
    vm.expectRevert(DStockWrapper.NotAllowed.selector);
    wrapper.wrap(address(usdc), 1e18, ALICE); // ALICE doesn't have OPERATOR_ROLE
  }

  function test_FirstWrap_RequiresMinimumAmount() public {
    usdc.mint(ADMIN, 100 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    // Try with amount less than 1e18 (after fee)
    vm.expectRevert(DStockWrapper.TooSmall.selector);
    wrapper.wrap(address(usdc), 0.5 ether, ADMIN); // less than 1e18
    vm.stopPrank();
  }

  function test_FirstWrap_OperatorWithMinimumAmount_Success() public {
    usdc.mint(ADMIN, 100 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    (uint256 net, uint256 s) = wrapper.wrap(address(usdc), 10 ether, ADMIN); // >= 1e18
    assertEq(net, 10 ether, "net should be 10 ether");
    assertEq(s, 10 ether, "shares should be 10 ether");
    assertEq(wrapper.balanceOf(ADMIN), 10 ether, "ADMIN should have 10 ether shares");
    vm.stopPrank();
  }

  function test_AfterFirstWrap_RegularUsersCanWrap() public {
    // First wrap by operator
    usdc.mint(ADMIN, 100 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    vm.stopPrank();

    // Now regular user can wrap
    uint256 beforeU = usdc.balanceOf(ALICE);
    vm.prank(ALICE);
    (uint256 net, uint256 s) = wrapper.wrap(address(usdc), 5 ether, ALICE);
    assertEq(usdc.balanceOf(ALICE), beforeU - 5 ether, "underlying not moved");
    assertEq(net, 5 ether, "net mismatch");
    assertEq(s, 5 ether, "shares minted mismatch");
    assertEq(wrapper.balanceOf(ALICE), 5 ether, "wrapper balance mismatch");
  }

  function test_WrapUnwrapPause_TransferStillWorks() public {
    // First wrap by operator
    usdc.mint(ADMIN, 100 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    vm.stopPrank();

    // mint some to ALICE first
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 5 ether, ALICE);
    // pause only wrap/unwrap
    vm.prank(ADMIN);
    wrapper.setWrapUnwrapPaused(true);
    // wrap should revert with WrapUnwrapPaused
    vm.prank(ALICE);
    vm.expectRevert(DStockWrapper.WrapUnwrapPaused.selector);
    wrapper.wrap(address(usdc), 1 ether, ALICE);
    // transfer should still work
    vm.prank(ALICE);
    wrapper.transfer(BOB, 1 ether);
    assertEq(wrapper.balanceOf(BOB), 1 ether);
    // unpause restores wrap
    vm.prank(ADMIN);
    wrapper.setWrapUnwrapPaused(false);
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 1 ether, ALICE);
  }

  // unwrap basic
  function test_Unwrap_Success() public {
    // First wrap by operator
    usdc.mint(ADMIN, 100 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    vm.stopPrank();
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 10 ether, ALICE);
    uint256 beforeU = usdc.balanceOf(ALICE);
    vm.prank(ALICE);
    wrapper.unwrap(address(usdc), 4 ether, ALICE);
    assertEq(usdc.balanceOf(ALICE), beforeU + 4 ether, "underlying not returned");
    assertEq(wrapper.balanceOf(ALICE), 6 ether, "wrapper balance not reduced");
  }

  function test_Unwrap_Fail_KycOnUnwrap_From() public {
    // First wrap by operator
    usdc.mint(ADMIN, 100 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    comp.setKyc(BOB, true);
    vm.stopPrank();
    usdc.mint(BOB, 10 ether);
    vm.startPrank(BOB);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 5 ether, BOB);
    vm.stopPrank();
    vm.prank(ADMIN);
    comp.setKyc(BOB, false);
    vm.prank(BOB);
    vm.expectRevert(DStockWrapper.NotAllowed.selector);
    wrapper.unwrap(address(usdc), 1 ether, BOB);
  }

  function test_Unwrap_Fail_FromMustBeCustody_WhenFlagOn() public {
    // First wrap by operator
    usdc.mint(ADMIN, 100 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    vm.stopPrank();
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 3 ether, ALICE);
    vm.startPrank(ADMIN);
    DStockCompliance.Flags memory t = comp.getFlags(address(wrapper));
    t.unwrapFromCustodyOnly = true;
    comp.setFlagsForToken(address(wrapper), t);
    vm.stopPrank();
    vm.prank(ALICE);
    vm.expectRevert(DStockWrapper.NotAllowed.selector);
    wrapper.unwrap(address(usdc), 1 ether, ALICE);
    vm.prank(ADMIN);
    comp.setCustody(ALICE, true);
    uint256 beforeU = usdc.balanceOf(ALICE);
    vm.prank(ALICE);
    wrapper.unwrap(address(usdc), 1 ether, ALICE);
    assertEq(usdc.balanceOf(ALICE), beforeU + 1 ether);
  }

  function test_Unwrap_Fail_InsufficientShares() public {
    vm.prank(ALICE);
    // With zero supply/liquidity, unwrap fails on liquidity guard first
    vm.expectRevert(DStockWrapper.InsufficientLiquidity.selector);
    wrapper.unwrap(address(usdc), 1 ether, ALICE);
  }

  // metadata
  function test_SetTokenMetadata_Success() public {
    vm.prank(ADMIN);
    wrapper.setTokenName("dUSDCx");
    vm.prank(ADMIN);
    wrapper.setTokenSymbol("dUSDCX");
    assertEq(wrapper.name(), "dUSDCx");
    assertEq(wrapper.symbol(), "dUSDCX");
  }

  function test_SetTokenMetadata_Unauthorized() public {
    vm.prank(STRANG);
    vm.expectRevert();
    wrapper.setTokenName("X");
    vm.prank(STRANG);
    vm.expectRevert();
    wrapper.setTokenSymbol("Y");
  }

  // per-underlying rebase params + harvest
  function test_UnderlyingRebaseParams_And_HarvestAll() public {
    // First wrap by operator
    usdc.mint(ADMIN, 1000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    // Operator sets per-underlying rebase params: feeMode=0 (wrapper-applied), 1%/day
    wrapper.setUnderlyingRebaseParams(address(usdc), 0, 1e16, 1 days);
    vm.stopPrank();

    // Have some state
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 100 ether, ALICE);

    // Accrue 2 days
    vm.warp(block.timestamp + 2 days);

    // Harvest and skim should move surplus to treasury (observable by token balance drop in wrapper or increase in TREAS)
    uint256 treBefore = usdc.balanceOf(TREAS);
    vm.prank(ADMIN);
    wrapper.harvestAll();
    uint256 treAfter = usdc.balanceOf(TREAS);
    assertGt(treAfter, treBefore, "treasury should receive skimmed tokens");
  }

  function test_UnderlyingFeeMode1_NoSkimOnHarvest() public {
    // First wrap by operator
    usdc.mint(ADMIN, 1000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    // feeMode = 1 means underlying self-rebases; wrapper should not skim
    wrapper.setUnderlyingRebaseParams(address(usdc), 1, 1e16, 1 days);
    vm.stopPrank();
    // seed state
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 50 ether, ALICE);
    // accrue
    vm.warp(block.timestamp + 2 days);
    uint256 treBefore = usdc.balanceOf(TREAS);
    vm.prank(ADMIN);
    wrapper.harvestAll();
    uint256 treAfter = usdc.balanceOf(TREAS);
    assertEq(treAfter, treBefore, "no skim expected for feeMode=1");
  }

  // ---- Rebase token scenarios (audit Issue-2) ----
  function test_RebaseToken_PositiveRebase_AllowsUnwrap() public {
    // Add a second underlying usdc2
    MockRebaseERC20 reb = new MockRebaseERC20("REB", "REB");
    DStockWrapper rebWrapper = _deployWrapperForUnderlying(address(reb));

    // First wrap is done by ADMIN (OPERATOR_ROLE) to satisfy initial-wrap requirement
    reb.mint(ADMIN, 1_000 ether);
    vm.startPrank(ADMIN);
    reb.approve(address(rebWrapper), type(uint256).max);
    rebWrapper.wrap(address(reb), 100 ether, ADMIN);
    vm.stopPrank();

    // ALICE wraps again to build a position
    reb.mint(ALICE, 100 ether);
    vm.startPrank(ALICE);
    reb.approve(address(rebWrapper), type(uint256).max);
    rebWrapper.wrap(address(reb), 50 ether, ALICE);
    vm.stopPrank();

    // Positive "rebase": mint directly to the wrapper address to simulate underlying growth
    reb.mint(address(rebWrapper), 50 ether);

    // Normal unwrap should work and not lock funds due to legacy liquidToken logic
    uint256 before = reb.balanceOf(ALICE);
    vm.prank(ALICE);
    rebWrapper.unwrap(address(reb), 10 ether, ALICE);
    uint256 afterBal = reb.balanceOf(ALICE);

    assertEq(afterBal, before + 10 ether, "positive rebase unwrap should return underlying");
  }

  function test_RebaseToken_NegativeRebase_TriggersInsufficientLiquidity() public {
    // Deploy a rebase-capable underlying and its wrapper
    MockRebaseERC20 reb = new MockRebaseERC20("REB", "REB");
    DStockWrapper rebWrapper = _deployWrapperForUnderlying(address(reb));

    // First wrap by ADMIN
    reb.mint(ADMIN, 1_000 ether);
    vm.startPrank(ADMIN);
    reb.approve(address(rebWrapper), type(uint256).max);
    rebWrapper.wrap(address(reb), 100 ether, ADMIN);
    vm.stopPrank();

    // ALICE builds a position
    reb.mint(ALICE, 200 ether);
    vm.startPrank(ALICE);
    reb.approve(address(rebWrapper), type(uint256).max);
    rebWrapper.wrap(address(reb), 100 ether, ALICE);
    vm.stopPrank();

    // Wrapper holds ~200 REB; simulate negative rebase by burning most of the balance
    reb.burn(address(rebWrapper), 180 ether); // only ~20 REB remain

    // ALICE attempts a large unwrap; should hit protection (InsufficientShares / InsufficientLiquidity), not dirty accounting
    vm.prank(ALICE);
    vm.expectRevert(DStockWrapper.InsufficientShares.selector);
    rebWrapper.unwrap(address(reb), 50 ether, ALICE);
  }

  function test_SettleAndSkim_OnWrap_RemovesSurplusFirst() public {
    // First wrap by operator
    usdc.mint(ADMIN, 1000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    // Use wrapper-applied fee so surplus exists
    wrapper.setUnderlyingRebaseParams(address(usdc), 0, 1e16, 1 days);
    vm.stopPrank();
    // seed and accrue
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 100 ether, ALICE);
    vm.warp(block.timestamp + 2 days);
    uint256 treBefore = usdc.balanceOf(TREAS);
    // This wrap should trigger settle+skim before pricing
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 1 ether, ALICE);
    uint256 treAfter = usdc.balanceOf(TREAS);
    assertGt(treAfter, treBefore, "treasury should increase due to pre-wrap skim");
  }

  function test_SettleAndSkim_OnUnwrap_RemovesSurplusFirst() public {
    // First wrap by operator
    usdc.mint(ADMIN, 1000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    wrapper.setUnderlyingRebaseParams(address(usdc), 0, 1e16, 1 days);
    vm.stopPrank();
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 100 ether, ALICE);
    vm.warp(block.timestamp + 2 days);
    uint256 treBefore = usdc.balanceOf(TREAS);
    // This unwrap should also trigger settle+skim first
    vm.prank(ALICE);
    wrapper.unwrap(address(usdc), 1 ether, ALICE);
    uint256 treAfter = usdc.balanceOf(TREAS);
    assertGt(treAfter, treBefore, "treasury should increase due to pre-unwrap skim");
  }

  // setUnderlyingRebaseParams should harvest pending fees before updating params
  function test_SetUnderlyingRebaseParams_HarvestsBeforeUpdate() public {
    // First wrap by operator
    usdc.mint(ADMIN, 1000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    // Enable wrapper-applied fee accrual
    wrapper.setUnderlyingRebaseParams(address(usdc), 0, 1e16, 1 days);
    vm.stopPrank();
    // Seed pool
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 100 ether, ALICE);
    // Accrue more than one full period
    vm.warp(block.timestamp + 2 days);
    uint256 treBefore = usdc.balanceOf(TREAS);
    // Updating params should internally settle+skim first, increasing treasury
    vm.prank(ADMIN);
    wrapper.setUnderlyingRebaseParams(address(usdc), 0, 2e16, 1 days);
    uint256 treAfter = usdc.balanceOf(TREAS);
    assertGt(treAfter, treBefore, "treasury should increase due to pre-update harvest");
  }

  // applySplit per-underlying
  function test_ApplySplit_PerUnderlying_Authorized_And_Unauthorized() public {
    // First wrap by operator
    usdc.mint(ADMIN, 1000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    vm.stopPrank();
    // Seed pool with tokens via wrap
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 100 ether, ALICE);

    uint256 poolBefore = usdc.balanceOf(address(wrapper));
    uint256 treBefore  = usdc.balanceOf(TREAS);

    // ADMIN reduces pool by half: sends tokens to treasury
    vm.prank(ADMIN);
    wrapper.applySplit(address(usdc), 1, 2);

    uint256 poolAfter = usdc.balanceOf(address(wrapper));
    uint256 treAfter  = usdc.balanceOf(TREAS);
    assertEq(poolAfter, poolBefore / 2, "pool should be halved");
    assertEq(treAfter, treBefore + (poolBefore - poolAfter), "treasury should receive removed tokens");

    // unauthorized attempt
    vm.prank(STRANG);
    vm.expectRevert();
    wrapper.applySplit(address(usdc), 2, 1);
  }

  // multi-underlying add/disable
  function test_AddUnderlying_Authorized_Success_WrapUnwrap_OK() public {
    // First wrap by operator for usdc
    usdc.mint(ADMIN, 1000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    MockERC20 usdc2 = new MockERC20("USDC2","USDC2");
    wrapper.addUnderlying(address(usdc2));
    usdc2.mint(ADMIN, 1000 ether);
    usdc2.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc2), 10 ether, ADMIN); // First wrap for usdc2
    vm.stopPrank();
    usdc2.mint(ALICE, 1_000 ether);
    vm.startPrank(ALICE);
    usdc2.approve(address(wrapper), type(uint256).max);
    (uint256 netMinted, uint256 sharesMinted) = wrapper.wrap(address(usdc2), 100 ether, ALICE);
    assertEq(netMinted, 100 ether);
    assertEq(sharesMinted, 100 ether);
    uint256 balBefore = usdc2.balanceOf(ALICE);
    wrapper.unwrap(address(usdc2), 40 ether, ALICE);
    assertEq(usdc2.balanceOf(ALICE), balBefore + 40 ether, "unwrap did not return underlying");
    vm.stopPrank();
  }

  function test_MultiUnderlying_FeeMode0And1_WrapUnwrap_SharesProRata() public {
    // Add a second underlying usdc2
    MockERC20 usdc2 = new MockERC20("USDC2", "USDC2");
    vm.prank(ADMIN);
    wrapper.addUnderlying(address(usdc2));

    // Explicitly set feeMode=0 for usdc; usdc2 keeps default feeMode=1 (see _addUnderlying)
    vm.prank(ADMIN);
    wrapper.setUnderlyingRebaseParams(address(usdc), 0, 0, 0);

    // Prepare funds and approvals
    usdc.mint(ADMIN, 1_000 ether);
    usdc2.mint(ADMIN, 1_000 ether);
    usdc2.mint(ALICE, 1_000 ether);
    usdc.mint(BOB, 1_000 ether);

    // 1) ADMIN performs the first wrap with usdc to create a baseline pool
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    (uint256 netAdmin, uint256 sAdmin) = wrapper.wrap(address(usdc), 100 ether, ADMIN);
    vm.stopPrank();
    assertEq(netAdmin, 100 ether);
    assertEq(sAdmin, 100 ether);

    // 2) ALICE wraps with usdc2 for the same amount; shares should match ADMIN (pool value split evenly)
    vm.startPrank(ALICE);
    usdc2.approve(address(wrapper), type(uint256).max);
    (uint256 netAlice, uint256 sAlice) = wrapper.wrap(address(usdc2), 100 ether, ALICE);
    vm.stopPrank();
    assertEq(netAlice, 100 ether, "ALICE net deposit mismatch");
    assertEq(sAlice, sAdmin, "shares should be equal for equal 18-dec deposits");

    // Grant KYC to BOB so compliance does not reject subsequent wrap/unwrap
    vm.prank(ADMIN);
    comp.setKyc(BOB, true);

    // 3) BOB deposits 200 usdc; his shares should be 2x ADMIN's for 2x deposit
    vm.startPrank(BOB);
    usdc.approve(address(wrapper), type(uint256).max);
    (uint256 netBob, uint256 sBob) = wrapper.wrap(address(usdc), 200 ether, BOB);
    vm.stopPrank();
    assertEq(netBob, 200 ether);
    assertEq(sBob, 2 * sAdmin, "BOB shares should be 2x ADMIN for 2x deposit");

    uint256 totalS = wrapper.totalShares();
    assertEq(totalS, sAdmin + sAlice + sBob, "totalShares should equal sum of user shares");

    // 4) ALICE partially unwraps usdc2; verify proportional share burn and conservation of pool value/shares
    uint256 aliceSharesBefore = wrapper.sharesOf(ALICE);
    uint256 poolBefore = wrapper.totalSupply();

    uint256 beforeU2 = usdc2.balanceOf(ALICE);
    vm.prank(ALICE);
    wrapper.unwrap(address(usdc2), 50 ether, ALICE);
    uint256 afterU2 = usdc2.balanceOf(ALICE);
    assertEq(afterU2, beforeU2 + 50 ether, "ALICE should receive 50 usdc2 back");

    uint256 aliceSharesAfter = wrapper.sharesOf(ALICE);
    uint256 poolAfter = wrapper.totalSupply();

    assertLt(aliceSharesAfter, aliceSharesBefore, "ALICE shares should decrease after unwrap");
    assertLt(poolAfter, poolBefore, "pool total supply should decrease after unwrap");
    assertEq(wrapper.sharesOf(ADMIN) + wrapper.sharesOf(ALICE) + wrapper.sharesOf(BOB), wrapper.totalShares(), "shares conservation after multi-underlying unwrap");
  }

  function test_AddUnderlying_Unauthorized_Fail_Then_WrapUnwrap_Fail() public {
    MockERC20 usdc3 = new MockERC20("USDC3","USDC3");
    vm.prank(STRANG);
    vm.expectRevert();
    wrapper.addUnderlying(address(usdc3));
    usdc3.mint(ALICE, 100 ether);
    vm.startPrank(ALICE);
    usdc3.approve(address(wrapper), type(uint256).max);
    vm.expectRevert(DStockWrapper.UnknownUnderlying.selector);
    wrapper.wrap(address(usdc3), 10 ether, ALICE);
    vm.expectRevert(DStockWrapper.UnknownUnderlying.selector);
    wrapper.unwrap(address(usdc3), 1 ether, ALICE);
    vm.stopPrank();
  }

  function test_DisableUnderlying_Authorized_Then_WrapUnwrap_Fail() public {
    // First wrap by operator
    usdc.mint(ADMIN, 1000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    vm.stopPrank();
    vm.startPrank(ALICE);
    wrapper.wrap(address(usdc), 50 ether, ALICE);
    vm.stopPrank();
    vm.prank(ADMIN);
    wrapper.setUnderlyingEnabled(address(usdc), false);
    usdc.mint(ALICE, 10 ether);
    vm.startPrank(ALICE);
    usdc.approve(address(wrapper), type(uint256).max);
    vm.expectRevert(DStockWrapper.UnsupportedUnderlying.selector);
    wrapper.wrap(address(usdc), 1 ether, ALICE);
    vm.expectRevert(DStockWrapper.UnsupportedUnderlying.selector);
    wrapper.unwrap(address(usdc), 1 ether, ALICE);
    vm.stopPrank();
  }

  function test_DisableUnderlying_Unauthorized_NoEffect_WrapStillOK() public {
    // First wrap by operator
    usdc.mint(ADMIN, 1000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    vm.stopPrank();
    vm.prank(STRANG);
    vm.expectRevert();
    wrapper.setUnderlyingEnabled(address(usdc), false);
    vm.startPrank(ALICE);
    usdc.mint(ALICE, 20 ether);
    usdc.approve(address(wrapper), type(uint256).max);
    (uint256 netMinted, uint256 sharesMinted) = wrapper.wrap(address(usdc), 10 ether, ALICE);
    assertEq(netMinted, 10 ether);
    assertEq(sharesMinted, 10 ether);
    vm.stopPrank();
  }

  // ---- view helper coverage ----
  function test_View_PreviewWrap_And_PreviewUnwrap() public {
    // configure fees
    vm.prank(ADMIN);
    wrapper.setWrapFeeBps(200); // 2%
    vm.prank(ADMIN);
    wrapper.setUnwrapFeeBps(300); // 3%

    // first wrap by operator
    usdc.mint(ADMIN, 1_000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);

    (uint256 minted18Preview, uint256 fee18Preview) =
      wrapper.previewWrap(address(usdc), 100 ether);
    (uint256 net18, uint256 sharesMinted) =
      wrapper.wrap(address(usdc), 100 ether, ADMIN);
    vm.stopPrank();

    // previewWrap should match the actual net deposit from wrap
    assertEq(net18, minted18Preview, "previewWrap net mismatch");
    assertEq(minted18Preview + fee18Preview, 100 ether, "gross != net+fee");
    assertEq(sharesMinted, net18, "first wrap shares != net");

    // compare previewUnwrap with actual unwrap result
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 10 ether, ALICE);
    uint256 before = usdc.balanceOf(ALICE);

    (uint256 released18Preview, uint256 fee18UnwrapPreview) =
      wrapper.previewUnwrap(address(usdc), 5 ether);

    vm.prank(ALICE);
    wrapper.unwrap(address(usdc), 5 ether, ALICE);
    uint256 delta = usdc.balanceOf(ALICE) - before;

    assertEq(delta, released18Preview, "previewUnwrap released mismatch");
    assertEq(released18Preview + fee18UnwrapPreview, 5 ether, "gross != released+fee");
  }

  function test_View_PreviewWrap_Unwrap_UnknownOrDisabledUnderlying() public {
    // for unknown underlying, preview should return (0,0)
    MockERC20 other = new MockERC20("OTHER", "OTH");
    (uint256 m1, uint256 f1) = wrapper.previewWrap(address(other), 100 ether);
    (uint256 r1, uint256 f2) = wrapper.previewUnwrap(address(other), 100 ether);
    assertEq(m1, 0);
    assertEq(f1, 0);
    assertEq(r1, 0);
    assertEq(f2, 0);

    // after adding and disabling an underlying, preview should also return (0,0)
    vm.prank(ADMIN);
    wrapper.addUnderlying(address(other));
    vm.prank(ADMIN);
    wrapper.setUnderlyingEnabled(address(other), false);

    (uint256 m2, uint256 f3) = wrapper.previewWrap(address(other), 100 ether);
    (uint256 r2, uint256 f4) = wrapper.previewUnwrap(address(other), 100 ether);
    assertEq(m2, 0);
    assertEq(f3, 0);
    assertEq(r2, 0);
    assertEq(f4, 0);
  }

  function test_View_SharesOf_And_TotalShares_AfterTransfersAndUnwrap() public {
    // first wrap by operator
    usdc.mint(ADMIN, 1_000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 100 ether, ADMIN);
    vm.stopPrank();

    // multi-user wrap flow
    vm.startPrank(ALICE);
    wrapper.wrap(address(usdc), 50 ether, ALICE);
    vm.stopPrank();

    // grant KYC to BOB so later wrap/unwrap are not rejected by compliance
    vm.prank(ADMIN);
    comp.setKyc(BOB, true);

    usdc.mint(BOB, 100 ether);
    vm.startPrank(BOB);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 20 ether, BOB);
    vm.stopPrank();

    // transfer + unwrap
    vm.prank(ALICE);
    wrapper.transfer(BOB, 10 ether);

    vm.prank(BOB);
    wrapper.unwrap(address(usdc), 5 ether, BOB);

    uint256 sAdmin = wrapper.sharesOf(ADMIN);
    uint256 sAlice = wrapper.sharesOf(ALICE);
    uint256 sBob   = wrapper.sharesOf(BOB);
    uint256 totalS = wrapper.totalShares();

    // sum of sharesOf should equal totalShares
    assertEq(sAdmin + sAlice + sBob, totalS, "shares sum mismatch");
    assertGt(wrapper.balanceOf(ALICE) + wrapper.balanceOf(BOB), 0, "balances should be > 0");
  }

  function test_MultiUser_WrapUnwrap_And_SharesConservation() public {
    // first wrap by ADMIN
    usdc.mint(ADMIN, 1_000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 100 ether, ADMIN);
    vm.stopPrank();

    // other users build positions
    usdc.mint(ALICE, 200 ether);
    vm.startPrank(ALICE);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 50 ether, ALICE);
    vm.stopPrank();

    vm.prank(ADMIN);
    comp.setKyc(BOB, true);
    usdc.mint(BOB, 300 ether);
    vm.startPrank(BOB);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 150 ether, BOB);
    vm.stopPrank();

    // Step 1: check share conservation after initial wraps
    uint256 sAdmin = wrapper.sharesOf(ADMIN);
    uint256 sAlice = wrapper.sharesOf(ALICE);
    uint256 sBob   = wrapper.sharesOf(BOB);
    uint256 totalS = wrapper.totalShares();
    assertEq(sAdmin + sAlice + sBob, totalS, "shares not conserved after initial wraps");

    // Step 2: multiple transfers
    vm.prank(ALICE);
    wrapper.transfer(BOB, 10 ether);
    vm.prank(BOB);
    wrapper.transfer(ADMIN, 20 ether);

    sAdmin = wrapper.sharesOf(ADMIN);
    sAlice = wrapper.sharesOf(ALICE);
    sBob   = wrapper.sharesOf(BOB);
    totalS = wrapper.totalShares();
    assertEq(sAdmin + sAlice + sBob, totalS, "shares not conserved after transfers");

    // Step 3: multiple unwraps
    vm.prank(ALICE);
    wrapper.unwrap(address(usdc), 20 ether, ALICE);
    vm.prank(BOB);
    wrapper.unwrap(address(usdc), 30 ether, BOB);

    sAdmin = wrapper.sharesOf(ADMIN);
    sAlice = wrapper.sharesOf(ALICE);
    sBob   = wrapper.sharesOf(BOB);
    totalS = wrapper.totalShares();
    assertEq(sAdmin + sAlice + sBob, totalS, "shares not conserved after unwraps");

    // Ensure at least one user still has a positive balance to avoid a trivial all-zero scenario
    assertGt(wrapper.balanceOf(ADMIN) + wrapper.balanceOf(ALICE) + wrapper.balanceOf(BOB), 0, "some balances should remain > 0");
  }

  function test_View_UnderlyingInfo_And_IsUnderlyingEnabled_And_ListUnderlyings() public {
    // Initially there is only one underlying
    address[] memory all = wrapper.listUnderlyings();
    assertEq(all.length, 1);
    assertEq(all[0], address(usdc));

    bool enabled = wrapper.isUnderlyingEnabled(address(usdc));
    assertTrue(enabled, "usdc should be enabled");

    (bool isEnabled, uint8 dec, uint256 liq) = wrapper.underlyingInfo(address(usdc));
    assertTrue(isEnabled, "info.enabled");
    assertEq(dec, usdc.decimals(), "decimals mismatch");
    assertEq(liq, 0, "initial liquidity should be 0");

    // After wrapping, liquidity should be greater than 0
    usdc.mint(ADMIN, 500 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 100 ether, ADMIN);
    vm.stopPrank();

    (isEnabled, dec, liq) = wrapper.underlyingInfo(address(usdc));
    assertTrue(isEnabled, "enabled after wrap");
    assertEq(dec, usdc.decimals());
    assertEq(liq, usdc.balanceOf(address(wrapper)), "liquidity mismatch");

    // Add a second underlying and then disable it
    MockERC20 other = new MockERC20("OTHER", "OTH");
    vm.prank(ADMIN);
    wrapper.addUnderlying(address(other));
    all = wrapper.listUnderlyings();
    assertEq(all.length, 2);
    assertEq(all[1], address(other));

    vm.prank(ADMIN);
    wrapper.setUnderlyingEnabled(address(other), false);
    enabled = wrapper.isUnderlyingEnabled(address(other));
    assertFalse(enabled, "other should be disabled");

    // For an unknown underlying, underlyingInfo should return an empty/default tuple
    MockERC20 unknown = new MockERC20("UNK", "UNK");
    (bool en2, uint8 dec2, uint256 liq2) = wrapper.underlyingInfo(address(unknown));
    assertFalse(en2);
    assertEq(dec2, 0);
    assertEq(liq2, 0);
  }

  // ---- Governance setter coverage ----
  function test_SetCompliance_OnlyOperator_And_NoChange() public {
    address old = address(comp);
    DStockCompliance newComp = new DStockCompliance(ADMIN);

    // Non-operator calls should fail (AccessControl revert)
    vm.prank(STRANG);
    vm.expectRevert();
    wrapper.setCompliance(address(newComp));

    // Operator successfully updates the compliance module
    vm.prank(ADMIN);
    wrapper.setCompliance(address(newComp));
    assertEq(address(wrapper.compliance()), address(newComp));

    // Setting the same address should trigger NoChange
    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.NoChange.selector);
    wrapper.setCompliance(address(newComp));

    // Can update back to the old compliance contract
    vm.prank(ADMIN);
    wrapper.setCompliance(old);
    assertEq(address(wrapper.compliance()), old);
  }

  function test_SetTreasury_WrapUnwrapFee_Guards() public {
    // Non-operator cannot set treasury
    vm.prank(STRANG);
    vm.expectRevert();
    wrapper.setTreasury(address(0x1234));

    // Setting the same treasury should trigger NoChange
    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.NoChange.selector);
    wrapper.setTreasury(TREAS);

    // First set treasury to 0 (allowed while fees are 0)
    vm.prank(ADMIN);
    wrapper.setTreasury(address(0));
    assertEq(wrapper.treasury(), address(0));

    // Setting non-zero fees while treasury is 0 should trigger FeeTreasuryRequired
    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.FeeTreasuryRequired.selector);
    wrapper.setWrapFeeBps(100);

    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.FeeTreasuryRequired.selector);
    wrapper.setUnwrapFeeBps(200);

    // After restoring treasury, setting fees should work
    vm.prank(ADMIN);
    wrapper.setTreasury(TREAS);
    vm.prank(ADMIN);
    wrapper.setWrapFeeBps(100);
    vm.prank(ADMIN);
    wrapper.setUnwrapFeeBps(200);
    assertEq(wrapper.wrapFeeBps(), 100);
    assertEq(wrapper.unwrapFeeBps(), 200);

    // Setting the same fee again should trigger NoChange
    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.NoChange.selector);
    wrapper.setWrapFeeBps(100);

    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.NoChange.selector);
    wrapper.setUnwrapFeeBps(200);
  }

  function test_SetMinInitialDeposit_Guards_And_EffectOnFirstWrap() public {
    uint256 currentMin = wrapper.minInitialDeposit18();

    // Non-operator must not be allowed to set minInitialDeposit
    vm.prank(STRANG);
    vm.expectRevert();
    wrapper.setMinInitialDeposit(currentMin + 1 ether);

    // Setting the same value should trigger NoChange
    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.NoChange.selector);
    wrapper.setMinInitialDeposit(currentMin);

    // After increasing min, a first wrap with amount below min should revert TooSmall
    vm.prank(ADMIN);
    wrapper.setMinInitialDeposit(20 ether);
    usdc.mint(ADMIN, 100 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    vm.expectRevert(DStockWrapper.TooSmall.selector);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);
    vm.stopPrank();

    // After lowering min, a smaller amount can complete the first wrap
    vm.prank(ADMIN);
    wrapper.setMinInitialDeposit(5 ether);
    usdc.mint(ADMIN, 100 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    (uint256 net18, uint256 sharesMinted) = wrapper.wrap(address(usdc), 5 ether, ADMIN);
    vm.stopPrank();
    assertEq(net18, 5 ether);
    assertEq(sharesMinted, 5 ether);
  }

  function test_SetTermsURI_OnlyOperator_And_NoChange() public {
    // Non-operator must not be allowed to call setTermsURI
    vm.prank(STRANG);
    vm.expectRevert();
    wrapper.setTermsURI("https://new-terms");

    // Normal update path
    vm.prank(ADMIN);
    wrapper.setTermsURI("https://new-terms");
    assertEq(wrapper.termsURI(), "https://new-terms");

    // Setting the same URI should trigger NoChange
    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.NoChange.selector);
    wrapper.setTermsURI("https://new-terms");
  }

  function test_SetWrapUnwrapPaused_OnlyPauser_And_NoChange() public {
    // Calls from non-PAUSER_ROLE should fail
    vm.prank(STRANG);
    vm.expectRevert();
    wrapper.setWrapUnwrapPaused(true);

    // ADMIN has PAUSER_ROLE and can toggle the flag
    vm.prank(ADMIN);
    wrapper.setWrapUnwrapPaused(true);
    assertTrue(wrapper.wrapUnwrapPaused(), "wrapUnwrapPaused should be true");

    // Passing the same value should trigger NoChange
    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.NoChange.selector);
    wrapper.setWrapUnwrapPaused(true);

    // Switch back to false to verify the normal path
    vm.prank(ADMIN);
    wrapper.setWrapUnwrapPaused(false);
    assertFalse(wrapper.wrapUnwrapPaused(), "wrapUnwrapPaused should be false");
  }

  function test_SetCap_OnlyOperator_And_NoChange() public {
    // Non-operator must not be allowed to set cap
    vm.prank(STRANG);
    vm.expectRevert();
    wrapper.setCap(1_000 ether);

    // Normal cap update
    vm.prank(ADMIN);
    wrapper.setCap(500 ether);
    assertEq(wrapper.cap(), 500 ether);

    // Setting the same cap should trigger NoChange
    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.NoChange.selector);
    wrapper.setCap(500 ether);
  }

  function test_ForceMoveToTreasury_Guards_And_Success() public {
    // Complete the first wrap and give ALICE some shares
    usdc.mint(ADMIN, 1_000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 100 ether, ADMIN);
    vm.stopPrank();

    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 50 ether, ALICE);

    // Non-operator call must fail
    vm.prank(STRANG);
    vm.expectRevert();
    wrapper.forceMoveToTreasury(ALICE, 1 ether);

    // With treasury set to 0, a call must revert with ZeroAddress
    vm.prank(ADMIN);
    wrapper.setTreasury(address(0));
    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.ZeroAddress.selector);
    wrapper.forceMoveToTreasury(ALICE, 1 ether);

    // Restore treasury
    vm.prank(ADMIN);
    wrapper.setTreasury(TREAS);

    // Using from == treasury must trigger NotAllowed
    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.NotAllowed.selector);
    wrapper.forceMoveToTreasury(TREAS, 1 ether);

    // Using amount18 == 0 must trigger TooSmall
    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.TooSmall.selector);
    wrapper.forceMoveToTreasury(ALICE, 0);

    // Success path: move some amount from ALICE to treasury
    uint256 sAliceBefore = wrapper.sharesOf(ALICE);
    uint256 sTreasBefore = wrapper.sharesOf(TREAS);
    uint256 totalBefore  = wrapper.totalShares();
    uint256 balAliceBefore = wrapper.balanceOf(ALICE);
    uint256 balTreasBefore = wrapper.balanceOf(TREAS);

    vm.prank(ADMIN);
    wrapper.forceMoveToTreasury(ALICE, 10 ether);

    uint256 sAliceAfter = wrapper.sharesOf(ALICE);
    uint256 sTreasAfter = wrapper.sharesOf(TREAS);
    uint256 totalAfter  = wrapper.totalShares();
    uint256 balAliceAfter = wrapper.balanceOf(ALICE);
    uint256 balTreasAfter = wrapper.balanceOf(TREAS);

    // Shares move from ALICE to treasury while totalShares remains unchanged
    assertLt(sAliceAfter, sAliceBefore, "ALICE shares should decrease");
    assertGt(sTreasAfter, sTreasBefore, "TREAS shares should increase");
    assertEq(sAliceBefore + sTreasBefore, sAliceAfter + sTreasAfter, "shares conservation violated");
    assertEq(totalAfter, totalBefore, "totalShares should remain unchanged");

    // Balance level should also reflect the transfer
    assertLt(balAliceAfter, balAliceBefore, "ALICE balance should decrease");
    assertGt(balTreasAfter, balTreasBefore, "TREAS balance should increase");
  }

  // ---- Factory-level control: setPausedByFactory ----
  function test_SetPausedByFactory_OnlyFactoryOrPauser_And_WhenOperational() public {
    // Unauthorized caller should revert with NotAllowed
    vm.prank(STRANG);
    vm.expectRevert(DStockWrapper.NotAllowed.selector);
    wrapper.setPausedByFactory(true);

    // First complete an initial wrap
    usdc.mint(ADMIN, 1_000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 100 ether, ADMIN);
    vm.stopPrank();

    // factoryRegistry (ADMIN) can pause
    vm.prank(ADMIN);
    wrapper.setPausedByFactory(true);
    assertTrue(wrapper.pausedByFactory(), "pausedByFactory should be true");

    // When pausedByFactory=true, whenOperational modifier should block operations
    vm.prank(ALICE);
    vm.expectRevert("paused");
    wrapper.wrap(address(usdc), 1 ether, ALICE);

    // Granting a new PAUSER_ROLE also allows modifying factory-level pause
    vm.startPrank(ADMIN);
    wrapper.grantRole(wrapper.PAUSER_ROLE(), BOB);
    vm.stopPrank();

    vm.prank(BOB);
    wrapper.setPausedByFactory(false);
    assertFalse(wrapper.pausedByFactory(), "pausedByFactory should be false");

    // After unpausing, wrap should work again
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 1 ether, ALICE);
  }

  // ---- Extreme / boundary amounts ----
  function test_Wrap_RespectsCapAndDoesNotOverflow() public {
    // Set a relatively small cap
    vm.prank(ADMIN);
    wrapper.setCap(100 ether);

    // First wrap by operator
    usdc.mint(ADMIN, 1_000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 60 ether, ADMIN);
    vm.stopPrank();

    // Wrap close to cap should still succeed
    vm.startPrank(ALICE);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 40 ether, ALICE);

    // Wrapping 1 more ether should trigger CapExceeded
    vm.expectRevert(DStockWrapper.CapExceeded.selector);
    wrapper.wrap(address(usdc), 1 ether, ALICE);
    vm.stopPrank();
  }

  function test_Wrap_TooSmall_WhenFeesConsumeAll() public {
    // Set 100% wrap fee
    vm.prank(ADMIN);
    wrapper.setWrapFeeBps(10_000);

    usdc.mint(ALICE, 10 ether);
    vm.startPrank(ALICE);
    usdc.approve(address(wrapper), type(uint256).max);
    vm.expectRevert(DStockWrapper.TooSmall.selector);
    wrapper.wrap(address(usdc), 1 ether, ALICE);
    vm.stopPrank();
  }

  function test_Unwrap_TooSmall_WhenFeesConsumeAll() public {
    // Set 100% unwrap fee
    vm.prank(ADMIN);
    wrapper.setUnwrapFeeBps(10_000);

    // Complete the first wrap and give ADMIN some shares
    usdc.mint(ADMIN, 100 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    wrapper.wrap(address(usdc), 10 ether, ADMIN);

    // With fee=100%, any unwrap would result in zero net amount and thus trigger TooSmall
    vm.expectRevert(DStockWrapper.TooSmall.selector);
    wrapper.unwrap(address(usdc), 1 ether, ADMIN);
    vm.stopPrank();
  }

  function test_Unwrap_AllLiquidity_Success_NoDust() public {
    // Use a single underlying usdc; verify a single user can redeem all of their liquidity without dirty accounting
    usdc.mint(ADMIN, 1_000 ether);
    vm.startPrank(ADMIN);
    usdc.approve(address(wrapper), type(uint256).max);
    // First wrap by ADMIN to create the pool
    wrapper.wrap(address(usdc), 100 ether, ADMIN);
    vm.stopPrank();

    // ALICE deposits her own liquidity
    usdc.mint(ALICE, 200 ether);
    vm.startPrank(ALICE);
    usdc.approve(address(wrapper), type(uint256).max);
    // Record ALICE's net deposit
    (uint256 netAlice, ) = wrapper.wrap(address(usdc), 100 ether, ALICE);
    vm.stopPrank();

    // ALICE unwraps all of her net deposit in one shot
    uint256 aliceBefore = usdc.balanceOf(ALICE);
    vm.prank(ALICE);
    wrapper.unwrap(address(usdc), netAlice, ALICE);
    uint256 aliceAfter = usdc.balanceOf(ALICE);

    // User gets back all of her net deposit, and her shares/balance go to zero
    assertEq(aliceAfter, aliceBefore + netAlice, "ALICE should receive full personal liquidity");
    assertEq(wrapper.balanceOf(ALICE), 0, "ALICE wrapper balance should be zero");
    assertEq(wrapper.sharesOf(ALICE), 0, "ALICE shares should be zero");
    // Pool and totalShares still consist of ADMIN's portion and should not be zero
    assertGt(wrapper.totalShares(), 0, "totalShares should remain > 0 due to ADMIN liquidity");
    assertGt(usdc.balanceOf(address(wrapper)), 0, "wrapper underlying balance should remain > 0 for ADMIN");
  }
}
