// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/DStockWrapper.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../src/interfaces/IDStockWrapper.sol";

// --- minimal mock ERC20 for underlying ---
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract MockERC20 is ERC20 {
  constructor() ERC20("USDC", "USDC") {}
  function mint(address to, uint256 a) external { _mint(to, a); }
}

contract WrapperForceMoveTest is Test {
  event Transfer(address indexed from, address indexed to, uint256 value);

  DStockWrapper wrapper;
  MockERC20     usdc;

  address ADMIN   = address(0xA11CE);
  address ALICE   = address(0xA1);
  address TREAS   = address(0xFEE);
  address STRANGE = address(0xBEEF);

  uint256 constant RAY = 1e18;

  function setUp() public {
    // underlying + balances
    usdc = new MockERC20();
    usdc.mint(ALICE, 1_000e18);

    // deploy wrapper proxy with treasury preset and no compliance restrictions
    DStockWrapper impl = new DStockWrapper();
    UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
    // init with multi-underlying (USDC as initial underlying)
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
        compliance: address(0),
        treasury: TREAS,
        wrapFeeBps: 0,
        unwrapFeeBps: 0,
        cap: 0,
        termsURI: "https://terms",

        // accounting params
        initialMultiplierRay: 1e18,
        feePerPeriodRay: 0,
        periodLength: 0,
        feeModel: 0
      });
    bytes memory initData = abi.encodeWithSelector(DStockWrapper.initialize.selector, p);
    wrapper = DStockWrapper(address(new BeaconProxy(address(beacon), initData)));

    // approve + wrap some to ALICE so she holds shares
    vm.startPrank(ALICE);
    usdc.approve(address(wrapper), type(uint256).max);
    // wrapper in latest version expects wrap(token, amount, to); if your local wrapper keeps old signature, adjust accordingly
    wrapper.wrap(address(usdc), 100e18, ALICE); // ALICE gets ~100 shares when multiplier=1e18
    vm.stopPrank();
  }

  // -------- helpers --------
  function _expectedSharesForAmount(uint256 amount) internal view returns (uint256 s, uint256 outAmt) {
    uint256 totalAmt = wrapper.totalSupply();
    uint256 totalSh  = wrapper.totalShares();
    // ceilDiv(amount * totalShares, totalAmt)
    s = (amount * totalSh + (totalAmt - 1)) / totalAmt;
    // out amount at pre-state valuation equals proportion
    outAmt = (s * totalAmt) / totalSh;
  }

  // =========================
  // Success path
  // =========================
  function test_ForceMoveToTreasury_Success() public {
    uint256 reqAmount = 30e18;

    // pre-state
    (uint256 sExp, uint256 amtExp) = _expectedSharesForAmount(reqAmount);

    uint256 aliceSharesBefore = wrapper.sharesOf(ALICE);
    uint256 treasSharesBefore = wrapper.sharesOf(TREAS);
    uint256 sumBefore         = wrapper.balanceOf(ALICE) + wrapper.balanceOf(TREAS);

    // expect events
    vm.expectEmit(true, true, false, true);
    emit DStockWrapper.ForceMovedToTreasury(ALICE, TREAS, amtExp, sExp);

    vm.expectEmit(true, true, false, true);
    emit Transfer(ALICE, TREAS, amtExp);

    // call as OPERATOR (admin has OPERATOR_ROLE from initialize)
    vm.prank(ADMIN);
    wrapper.forceMoveToTreasury(ALICE, reqAmount);

    // post checks
    uint256 aliceSharesAfter = wrapper.sharesOf(ALICE);
    uint256 treasSharesAfter = wrapper.sharesOf(TREAS);

    assertEq(aliceSharesAfter, aliceSharesBefore - sExp, "alice shares dec");
    assertEq(treasSharesAfter, treasSharesBefore + sExp, "treasury shares inc");

    // amounts via balanceOf are in amount terms; total should remain the same (redistribution)
    uint256 sumAfter = wrapper.balanceOf(ALICE) + wrapper.balanceOf(TREAS);
    assertEq(sumAfter, sumBefore, "conservation at amount terms");
  }

  // =========================
  // Reverts
  // =========================
  function test_ForceMoveToTreasury_Revert_Unauthorized() public {
    vm.prank(STRANGE);
    vm.expectRevert();
    wrapper.forceMoveToTreasury(ALICE, 1e18);
  }

  function test_ForceMoveToTreasury_Revert_ZeroTreasury() public {
    // set treasury to zero by admin (authorized)
    vm.prank(ADMIN);
    wrapper.setTreasury(address(0));

    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.ZeroAddress.selector);
    wrapper.forceMoveToTreasury(ALICE, 1e18);
  }

  function test_ForceMoveToTreasury_Revert_FromEqualsTreasury() public {
    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.NotAllowed.selector);
    wrapper.forceMoveToTreasury(TREAS, 1e18);
  }

  function test_ForceMoveToTreasury_Revert_ZeroAmount() public {
    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.TooSmall.selector);
    wrapper.forceMoveToTreasury(ALICE, 0);
  }

  function test_ForceMoveToTreasury_Revert_InsufficientShares() public {
    // ask to move more than ALICE amount (ALICE has ~100e18)
    vm.prank(ADMIN);
    vm.expectRevert(DStockWrapper.InsufficientShares.selector);
    wrapper.forceMoveToTreasury(ALICE, 1000e18);
  }

  // sanity: multiplier != 1e18 still behaves correctly
  function test_ForceMoveToTreasury_AfterPoolRescale() public {
    // simulate a pool rescale by reducing underlying by half (send to treasury)
    vm.prank(ADMIN);
    wrapper.applySplit(address(usdc), 1, 2);

    uint256 reqAmount = 10e18;
    (uint256 sExp, ) = _expectedSharesForAmount(reqAmount);

    uint256 aliceSharesBefore = wrapper.sharesOf(ALICE);
    uint256 treasSharesBefore = wrapper.sharesOf(TREAS);

    vm.prank(ADMIN);
    wrapper.forceMoveToTreasury(ALICE, reqAmount);

    assertEq(wrapper.sharesOf(ALICE), aliceSharesBefore - sExp);
    assertEq(wrapper.sharesOf(TREAS), treasSharesBefore + sExp);
  }
}
