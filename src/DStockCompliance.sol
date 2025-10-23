// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IDStockCompliance} from "./interfaces/IDStockCompliance.sol";

/// @title DStockCompliance
/// @notice Minimal, configurable compliance module: KYC / Sanctions / Custody & a set of boolean flags;
///         supports global default rules and per-token overrides (override takes precedence).
contract DStockCompliance is IDStockCompliance, AccessControl {
  // -------------------- Roles --------------------
  bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

  // -------------------- Entities --------------------
  mapping(address => bool) public kyc;        // Whitelist (passed KYC)
  mapping(address => bool) public sanctioned; // Sanctions list (blocked)
  mapping(address => bool) public custody;    // Custody/operational accounts

  // -------------------- Flags --------------------
  struct Flags {
    bool set;                   // Whether this token has its own rule-set (used for override detection)
    bool enforceSanctions;      // Enable sanctions checks
    bool transferRestricted;    // Transfers require KYC⇄KYC
    bool wrapToCustodyOnly;     // Wrap destination must be a custody address (checks `to`)
    bool unwrapFromCustodyOnly; // Unwrap sender must be a custody address (checks `from`)
    bool kycOnWrap;             // Wrap requires `from` to be KYC (independent of wrapToCustodyOnly)
    bool kycOnUnwrap;           // Unwrap requires `from` to be KYC (independent of unwrapFromCustodyOnly)
  }

  /// @dev Global default rules
  Flags public globalFlags;

  /// @dev Per-token overrides (if .set = true, it takes precedence over global)
  mapping(address => Flags) public tokenFlags;

  // -------------------- Events --------------------
  event FlagsGlobalUpdated(Flags flags);
  event FlagsTokenUpdated(address indexed token, Flags flags);
  event KycUpdated(address indexed user, bool ok);
  event SanctionUpdated(address indexed user, bool bad);
  event CustodyUpdated(address indexed user, bool ok);
  event KycBatchUpdated(address[] users, bool ok);

  // -------------------- Constructor --------------------
  constructor(address admin) {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(OPERATOR_ROLE, admin);

    // Global defaults (can be updated later)
    globalFlags = Flags({
      set: true,
      enforceSanctions: true,
      transferRestricted: false,
      wrapToCustodyOnly: false,
      unwrapFromCustodyOnly: false,
      kycOnWrap: true,      // now interpreted as: require FROM to be KYC on wrap
      kycOnUnwrap: true     // require FROM to be KYC on unwrap
    });
    emit FlagsGlobalUpdated(globalFlags);
  }

  // -------------------- Views --------------------
  function getFlags(address token) public view returns (Flags memory f) {
    f = tokenFlags[token];
    if (!f.set) f = globalFlags;
  }

  /// @inheritdoc IDStockCompliance
  function isTransferAllowed(
    address token,
    address from,
    address to,
    uint256 /*amount*/,
    uint8 action // 0=Transfer, 1=Wrap, 2=Unwrap
  ) external view override returns (bool) {
    Flags memory f = getFlags(token);

    // 1) Sanctions check (applies to all actions)
    if (f.enforceSanctions) {
      if (sanctioned[from] || sanctioned[to]) return false;
    }

    // 2) Action-specific logic
    if (action == 0) {
      // Transfer: optionally require KYC⇄KYC
      if (f.transferRestricted) {
        if (!kyc[from] || !kyc[to]) return false;
      }
      return true;

    } else if (action == 1) {
      // Wrap:
      // - kycOnWrap: require FROM to be KYC
      // - wrapToCustodyOnly: require TO to be a custody address
      if (f.kycOnWrap && !kyc[from]) return false;
      if (f.wrapToCustodyOnly && !custody[to]) return false;
      return true;

    } else if (action == 2) {
      // Unwrap:
      // - kycOnUnwrap: require FROM to be KYC
      // - unwrapFromCustodyOnly: require FROM to be a custody address
      if (f.kycOnUnwrap && !kyc[from]) return false;
      if (f.unwrapFromCustodyOnly && !custody[from]) return false;
      return true;

    } else {
      // Unknown action -> reject
      return false;
    }
  }

  // -------------------- Admin: Flags --------------------
  function setFlagsGlobal(Flags calldata f) external onlyRole(OPERATOR_ROLE) {
    Flags memory copy = f;
    copy.set = true; // keep set=true so downstream can detect override state
    globalFlags = copy;
    emit FlagsGlobalUpdated(globalFlags);
  }

  function clearFlagsForToken(address token) external onlyRole(OPERATOR_ROLE) {
    delete tokenFlags[token];
    emit FlagsTokenUpdated(token, tokenFlags[token]);
  }

  function setFlagsForToken(address token, Flags calldata f) external onlyRole(OPERATOR_ROLE) {
    Flags memory copy = f;
    copy.set = true;
    tokenFlags[token] = copy;
    emit FlagsTokenUpdated(token, tokenFlags[token]);
  }

  // -------------------- Admin: Entities --------------------
  function setKyc(address user, bool ok) external onlyRole(OPERATOR_ROLE) {
    kyc[user] = ok;
    emit KycUpdated(user, ok);
  }

  function batchSetKyc(address[] calldata users, bool ok) external onlyRole(OPERATOR_ROLE) {
    for (uint256 i = 0; i < users.length; i++) {
      kyc[users[i]] = ok;
    }
    emit KycBatchUpdated(users, ok);
  }

  function setSanctioned(address user, bool bad) external onlyRole(OPERATOR_ROLE) {
    sanctioned[user] = bad;
    emit SanctionUpdated(user, bad);
  }

  function setCustody(address user, bool ok) external onlyRole(OPERATOR_ROLE) {
    custody[user] = ok;
    emit CustodyUpdated(user, ok);
  }
}
