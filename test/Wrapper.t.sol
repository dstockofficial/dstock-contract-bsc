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

    // give KYC to ALICE only (BOB no KYC initially)
    comp.setKyc(ALICE, true);
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
    vm.startPrank(ADMIN);
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
    vm.prank(ALICE);
    usdc.approve(address(wrapper), 0);
    vm.prank(ALICE);
    vm.expectRevert();
    wrapper.wrap(address(usdc), 1 ether, ALICE);
  }

  function test_Wrap_Fail_Paused() public {
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

  function test_WrapUnwrapPause_TransferStillWorks() public {
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
    vm.prank(ALICE);
    wrapper.wrap(address(usdc), 10 ether, ALICE);
    uint256 beforeU = usdc.balanceOf(ALICE);
    vm.prank(ALICE);
    wrapper.unwrap(address(usdc), 4 ether, ALICE);
    assertEq(usdc.balanceOf(ALICE), beforeU + 4 ether, "underlying not returned");
    assertEq(wrapper.balanceOf(ALICE), 6 ether, "wrapper balance not reduced");
  }

  function test_Unwrap_Fail_KycOnUnwrap_From() public {
    vm.startPrank(ADMIN);
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
    // Operator sets per-underlying rebase params: feeMode=0 (wrapper-applied), 1%/day
    vm.prank(ADMIN);
    wrapper.setUnderlyingRebaseParams(address(usdc), 0, 1e16, 1 days);

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
    // feeMode = 1 means underlying self-rebases; wrapper should not skim
    vm.prank(ADMIN);
    wrapper.setUnderlyingRebaseParams(address(usdc), 1, 1e16, 1 days);
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

  function test_SettleAndSkim_OnWrap_RemovesSurplusFirst() public {
    // Use wrapper-applied fee so surplus exists
    vm.prank(ADMIN);
    wrapper.setUnderlyingRebaseParams(address(usdc), 0, 1e16, 1 days);
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
    vm.prank(ADMIN);
    wrapper.setUnderlyingRebaseParams(address(usdc), 0, 1e16, 1 days);
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
    // Enable wrapper-applied fee accrual
    vm.prank(ADMIN);
    wrapper.setUnderlyingRebaseParams(address(usdc), 0, 1e16, 1 days);
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
    MockERC20 usdc2 = new MockERC20("USDC2","USDC2");
    vm.prank(ADMIN);
    wrapper.addUnderlying(address(usdc2));
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
}
