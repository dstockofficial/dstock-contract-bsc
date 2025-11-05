// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/DStockCompliance.sol";
import {DStockWrapper} from "../src/DStockWrapper.sol";
import {IDStockWrapper} from "../src/interfaces/IDStockWrapper.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
  constructor() ERC20("USDC", "USDC") {}
  function mint(address to, uint256 a) external { _mint(to, a); }
}

contract ComplianceIntegrationTest is Test {
  DStockWrapper    wrapper;
  DStockCompliance comp;
  MockERC20        usdc;

  address admin = address(0xA11CE);
  address alice = address(0xA1);
  address bob   = address(0xB2);
  address tre   = address(0xFEE);

  function setUp() public {
    usdc = new MockERC20();
    comp = new DStockCompliance(admin);

    // Grant OPERATOR to admin and set global flags explicitly.
    vm.startPrank(admin);
    comp.grantRole(comp.OPERATOR_ROLE(), admin);

    // Set global flags for the test:
    // - enforceSanctions: true
    // - transferRestricted: true (transfer requires KYC <-> KYC)
    // - wrapToCustodyOnly: false
    // - unwrapFromCustodyOnly: false
    // - kycOnWrap: true (FROM must be KYC)
    // - kycOnUnwrap: true (FROM must be KYC)
    DStockCompliance.Flags memory g = DStockCompliance.Flags({
      set: true,
      enforceSanctions: true,
      transferRestricted: true,
      wrapToCustodyOnly: false,
      unwrapFromCustodyOnly: false,
      kycOnWrap: true,
      kycOnUnwrap: true
    });
    comp.setFlagsGlobal(g);

    // KYC only alice; bob remains non-KYC initially
    comp.setKyc(alice, true);
    vm.stopPrank();

    // ---- deploy wrapper with multi-underlying InitParams ----
    wrapper = new DStockWrapper();
    address[] memory initialU = new address[](1);
    initialU[0] = address(usdc);

    wrapper.initialize(
      IDStockWrapper.InitParams({
        // roles / pointers
        admin: admin,
        factoryRegistry: address(0),

        // token meta
        initialUnderlyings: initialU,
        name: "dUSDC",
        symbol: "dUSDC",
        decimalsOverride: 0,

        // compliance / fees / limits
        compliance: address(comp),
        treasury: tre,
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

    // Fund alice and approve wrapper
    usdc.mint(alice, 100 ether);
    vm.startPrank(alice);
    usdc.approve(address(wrapper), type(uint256).max);
    vm.stopPrank();
  }

  function test_Wrap_AllowIfKyc() public {
    // alice is KYC; wrap should pass
    vm.prank(alice);
    wrapper.wrap(address(usdc), 10 ether, alice);
    assertEq(wrapper.balanceOf(alice), 10 ether);
  }

  function test_Transfer_BlockIfNonKyc() public {
    // Mint to alice via wrap
    vm.prank(alice);
    wrapper.wrap(address(usdc), 10 ether, alice);

    // With transferRestricted = true, transferring to non-KYC bob should revert
    vm.startPrank(alice);
    vm.expectRevert(DStockWrapper.NotAllowed.selector);
    wrapper.transfer(bob, 1 ether);
    vm.stopPrank();

    // After granting KYC to bob, transfer should succeed
    vm.prank(admin);
    comp.setKyc(bob, true);

    vm.prank(alice);
    wrapper.transfer(bob, 1 ether);
    assertEq(wrapper.balanceOf(bob), 1 ether);
  }
}
