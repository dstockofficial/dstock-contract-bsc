// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/DStockCompliance.sol";

contract ComplianceTest is Test {
  // ---- actors ----
  address ADMIN = address(0xA11CE);
  address OP    = address(0x0123);
  address STRG  = address(0xBEEF);

  address ALICE = address(0xA1);
  address BOB   = address(0xB2);
  address CUST  = address(0xC3);
  address EVIL  = address(0xBAD);

  // pseudo token (wrapper) address for per-token overrides
  address TOKEN = address(0x1000);

  DStockCompliance comp;

  function setUp() public {
    comp = new DStockCompliance(ADMIN);

    // grant OPERATOR to ADMIN for convenience
    vm.startPrank(ADMIN);
    comp.grantRole(comp.OPERATOR_ROLE(), ADMIN); 
    vm.stopPrank();
  }

  // ------------------------------------------------
  // Lists & Flags: setKyc / batchSetKyc / setSanctioned / setCustody
  // ------------------------------------------------
  function test_SetKyc_And_Events() public {
    vm.startPrank(ADMIN);

    // KYC single
    vm.expectEmit(true, true, false, true);
    emit DStockCompliance.KycUpdated(ALICE, true);
    comp.setKyc(ALICE, true);
    assertTrue(comp.kyc(ALICE));

    // batch KYC
    address[] memory arr = new address[](2);
    arr[0] = address(0x1111);
    arr[1] = address(0x2222);

    vm.expectEmit(false, false, false, true);
    emit DStockCompliance.KycBatchUpdated(arr, true);
    comp.batchSetKyc(arr, true);
    assertTrue(comp.kyc(arr[0]));
    assertTrue(comp.kyc(arr[1]));

    // sanction
    vm.expectEmit(true, true, false, true);
    emit DStockCompliance.SanctionUpdated(EVIL, true);
    comp.setSanctioned(EVIL, true);
    assertTrue(comp.sanctioned(EVIL));

    // custody
    vm.expectEmit(true, true, false, true);
    emit DStockCompliance.CustodyUpdated(CUST, true);
    comp.setCustody(CUST, true);
    assertTrue(comp.custody(CUST));

    vm.stopPrank();
  }

  function test_SetLists_Unauthorized_Revert() public {
    // no role
    vm.prank(STRG);
    vm.expectRevert();
    comp.setKyc(ALICE, true);

    vm.prank(STRG);
    vm.expectRevert();

    comp.batchSetKyc(new address[](0), true);

    vm.prank(STRG);
    vm.expectRevert();
    comp.setSanctioned(EVIL, true);

    vm.prank(STRG);
    vm.expectRevert();
    comp.setCustody(CUST, true);
  }

  // ------------------------------------------------
  // Global / Token-level flags & precedence
  // ------------------------------------------------
  function test_SetFlags_Global_And_Token_Override() public {
    // global: transfer not restricted initially in constructor? we overwrite
    DStockCompliance.Flags memory g = DStockCompliance.Flags({
      set: true,
      enforceSanctions: true,
      transferRestricted: false,
      wrapToCustodyOnly: false,
      unwrapFromCustodyOnly: false,
      kycOnWrap: true,
      kycOnUnwrap: true
    });

    vm.startPrank(ADMIN);
    vm.expectEmit(false, false, false, true);
    emit DStockCompliance.FlagsGlobalUpdated(g);
    comp.setFlagsGlobal(g);
    vm.stopPrank();

    // token-level: force transferRestricted = true regardless of global
    DStockCompliance.Flags memory t = comp.getFlags(TOKEN);
    t.transferRestricted = true;

    vm.startPrank(ADMIN);
    vm.expectEmit(true, false, false, true);
    emit DStockCompliance.FlagsTokenUpdated(TOKEN, t);
    comp.setFlagsForToken(TOKEN, t);
    vm.stopPrank();

    // verify precedence: TOKEN requires KYC↔KYC on transfer
    // put KYC for ALICE only
    vm.prank(ADMIN);
    comp.setKyc(ALICE, true);

    // non-kyc -> kyc should FAIL on TOKEN
    bool ok = comp.isTransferAllowed(TOKEN, address(0x0CC), ALICE, 1, 0);
    assertFalse(ok, "token override should require KYC to KYC");

    // clear token flags -> back to global (no transfer restriction)
    vm.prank(ADMIN);
    comp.clearFlagsForToken(TOKEN);

    ok = comp.isTransferAllowed(TOKEN, address(0xCC), ALICE, 1, 0);
    // global transferRestricted=false => allow
    assertTrue(ok, "global should allow non-kyc -> kyc when not restricted");
  }

  function test_SetFlags_Unauthorized_Revert() public {
    DStockCompliance.Flags memory dummy = comp.getFlags(address(0));
    vm.prank(STRG);
    vm.expectRevert();
    comp.setFlagsGlobal(dummy);

    vm.prank(STRG);
    vm.expectRevert();
    comp.setFlagsForToken(TOKEN, dummy);

    vm.prank(STRG);
    vm.expectRevert();
    comp.clearFlagsForToken(TOKEN);
  }

  // ------------------------------------------------
  // Compliance: Transfer(0)
  // - transferRestricted = true => require KYC↔KYC
  // ------------------------------------------------
  function test_Transfer_Action_Requires_KYC_When_Restricted() public {
    // set global: transferRestricted = true
    DStockCompliance.Flags memory g = comp.getFlags(address(0));
    g.transferRestricted = true;
    vm.prank(ADMIN);
    comp.setFlagsGlobal(g);

    // ALICE KYC, BOB not KYC
    vm.prank(ADMIN);
    comp.setKyc(ALICE, true);

    // non-kyc -> kyc fails
    assertFalse(comp.isTransferAllowed(TOKEN, address(0x0101), ALICE, 1, 0));

    // kyc -> kyc ok
    vm.prank(ADMIN);
    comp.setKyc(BOB, true);
    assertTrue(comp.isTransferAllowed(TOKEN, ALICE, BOB, 1, 0));
  }

  // ------------------------------------------------
  // Compliance: Wrap(1)
  // - kycOnWrap enforces FROM must be KYC
  // - wrapToCustodyOnly enforces TO must be custody
  // both independent; if both on -> both must be satisfied
  // ------------------------------------------------
  function test_Wrap_Action_FromKyc_And_ToCustody() public {
    // global baseline
    DStockCompliance.Flags memory g = DStockCompliance.Flags({
      set: true,
      enforceSanctions: true,
      transferRestricted: false,
      wrapToCustodyOnly: false,
      unwrapFromCustodyOnly: false,
      kycOnWrap: true,   // enforce FROM KYC
      kycOnUnwrap: true
    });
    vm.prank(ADMIN);
    comp.setFlagsGlobal(g);

    // Only ALICE is KYC
    vm.prank(ADMIN);
    comp.setKyc(ALICE, true);

    // Case 1: wrapToCustodyOnly=false => only from needs KYC
    assertTrue(comp.isTransferAllowed(TOKEN, ALICE, BOB, 1, 1), "kyc from only expected ok");
    assertFalse(comp.isTransferAllowed(TOKEN, BOB,   ALICE, 1, 1), "non-kyc from should fail");

    // Case 2: also require custody-only
    vm.prank(ADMIN);
    DStockCompliance.Flags memory t = comp.getFlags(TOKEN);
    t.wrapToCustodyOnly = true;
    vm.prank(ADMIN);
    comp.setFlagsForToken(TOKEN, t);

    // to must be custody
    assertFalse(comp.isTransferAllowed(TOKEN, ALICE, BOB, 1, 1), "to not custody -> fail");
    vm.prank(ADMIN);
    comp.setCustody(CUST, true);
    assertTrue(comp.isTransferAllowed(TOKEN, ALICE, CUST, 1, 1), "to custody -> ok");
  }

  // ------------------------------------------------
  // Compliance: Unwrap(2)
  // - kycOnUnwrap enforces FROM must be KYC
  // - unwrapFromCustodyOnly enforces FROM must be custody
  // independent; both on -> both must be satisfied
  // ------------------------------------------------
  function test_Unwrap_Action_FromKyc_And_FromCustody() public {
    // global: kycOnUnwrap = true, unwrapFromCustodyOnly = false
    DStockCompliance.Flags memory g = DStockCompliance.Flags({
      set: true,
      enforceSanctions: true,
      transferRestricted: false,
      wrapToCustodyOnly: false,
      unwrapFromCustodyOnly: false,
      kycOnWrap: true,
      kycOnUnwrap: true
    });
    vm.prank(ADMIN);
    comp.setFlagsGlobal(g);

    // KYC ALICE
    vm.prank(ADMIN);
    comp.setKyc(ALICE, true);

    // Case 1: only from-KYC required
    assertTrue(comp.isTransferAllowed(TOKEN, ALICE, BOB, 1, 2), "from kyc -> ok");
    assertFalse(comp.isTransferAllowed(TOKEN, BOB,   ALICE, 1, 2), "from non-kyc -> fail");

    // Case 2: also require from-custody (token-level)
    vm.startPrank(ADMIN);
    DStockCompliance.Flags memory t = comp.getFlags(TOKEN);
    t.unwrapFromCustodyOnly = true;
    comp.setFlagsForToken(TOKEN, t);
    comp.setCustody(ALICE, true);
    vm.stopPrank();

    assertTrue(comp.isTransferAllowed(TOKEN, ALICE, BOB, 1, 2), "from custody+kyc -> ok");

    // remove custody -> fail
    vm.prank(ADMIN);
    comp.setCustody(ALICE, false);
    assertFalse(comp.isTransferAllowed(TOKEN, ALICE, BOB, 1, 2), "from not custody -> fail");
  }

  // ------------------------------------------------
  // Sanctions: when enforceSanctions=true, any sanctioned from/to -> reject
  // ------------------------------------------------
  function test_EnforceSanctions_Blocks_All_Actions() public {
    // ensure enforceSanctions = true
    DStockCompliance.Flags memory g = comp.getFlags(address(0));
    g.enforceSanctions = true;
    vm.prank(ADMIN);
    comp.setFlagsGlobal(g);

    vm.prank(ADMIN);
    comp.setSanctioned(EVIL, true);

    // any action with EVIL involved should be false
    assertFalse(comp.isTransferAllowed(TOKEN, EVIL, ALICE, 1, 0));
    assertFalse(comp.isTransferAllowed(TOKEN, ALICE, EVIL, 1, 0));
    assertFalse(comp.isTransferAllowed(TOKEN, EVIL, ALICE, 1, 1));
    assertFalse(comp.isTransferAllowed(TOKEN, ALICE, EVIL, 1, 1));
    assertFalse(comp.isTransferAllowed(TOKEN, EVIL, ALICE, 1, 2));
    assertFalse(comp.isTransferAllowed(TOKEN, ALICE, EVIL, 1, 2));
  }
}
