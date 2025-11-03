// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Interface for the multi-underlying DStockWrapper used by the factory.
/// @dev Backward-incompatible change: single `underlying` is replaced by `initialUnderlyings`.
interface IDStockWrapper {
  struct InitParams {
    // --- roles / pointers ---
    address   admin;               // will receive DEFAULT_ADMIN/OPERATOR/PAUSER/UPGRADER in wrapper
    address   factoryRegistry;     // optional back-pointer set by factory

    // --- token meta ---
    address[] initialUnderlyings;  // zero or more underlyings at init; can add more later via addUnderlying()
    string    name;
    string    symbol;
    uint8     decimalsOverride;    // reserved; wrapper currently returns 18

    // --- compliance / fees / limits ---
    address   compliance;          // 0 => no compliance checks
    address   treasury;            // fee sink for wrap/unwrap (can be 0)
    uint16    wrapFeeBps;          // fee on wrap (in BPS); 0 allowed
    uint16    unwrapFeeBps;        // fee on unwrap (in BPS); 0 allowed
    uint256   cap;                 // cap in 18-decimal amount terms; 0 => unlimited
    string    termsURI;            // optional terms link

    // --- accounting params ---
    uint256   initialMultiplierRay; // 1e18 = 1:1 amount/share
    uint256   feePerPeriodRay;      // holding-fee per period in Ray; 0 disables
    uint32    periodLength;         // seconds; 0 disables
    uint8     feeModel;             // reserved; 0 = discrete
  }

  // ---- lifecycle (factory uses this) ----
  function initialize(InitParams calldata p) external;
  function setPausedByFactory(bool paused) external;
  function factoryRegistry() external view returns (address);

  // ---- multi-underlying admin (optional for factory; used by ops) ----
  function addUnderlying(address token) external;
  function setUnderlyingEnabled(address token, bool enabled) external;

  // ---- multi-underlying business (frontends/scripts will call these) ----
  /// @notice Wrap exact `amount` of `token` into the unified d-stock.
  /// @return net18    Amount credited in 18-decimal amount terms after fee.
  /// @return shares   Shares minted.
  function wrap(address token, uint256 amount, address to)
    external
    returns (uint256 net18, uint256 shares);

  /// @notice Unwrap exact `amount` (token units) of `token` out to `to`.
  function unwrap(address token, uint256 amount, address to) external;

  // ---- views (optional) ----
  function isUnderlyingEnabled(address token) external view returns (bool);
  function listUnderlyings() external view returns (address[] memory);
  /// @return enabled Whether token is enabled
  /// @return decimals Token decimals (<=18)
  /// @return liquidToken Tracked redeemable liquidity in token units
  function underlyingInfo(address token)
    external
    view
    returns (bool enabled, uint8 decimals, uint256 liquidToken);
}
