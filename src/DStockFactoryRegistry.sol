// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {IDStockWrapper} from "./interfaces/IDStockWrapper.sol";

/// @title DStockFactoryRegistry
/// @notice Factory + registry; uses a Beacon to point to a single DStockWrapper implementation.
///         Creating a new wrapper deploys only a BeaconProxy. Supports mapping MANY underlyings to ONE wrapper.
contract DStockFactoryRegistry is AccessControl {
  // ---------- Roles ----------
  bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
  bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");

  // ---------- Beacon & Compliance ----------
  UpgradeableBeacon public immutable beacon; // owner = this factory contract
  address public globalCompliance;           // Global compliance module (wrappers can override locally)

  // ---------- Registry (multi-underlying) ----------
  // underlying token => wrapper
  mapping(address => address) public wrapperOf;

  // wrapper bookkeeping
  mapping(address => bool) public isWrapper;
  address[] public allWrappers;

  // metadata
  mapping(address => bool)   public deprecated;     // wrapper => deprecated or not
  mapping(address => string) public deprecateReason;

  // ---------- Events ----------
  event FactoryInitialized(address admin, address wrapperImpl, address beacon, address globalCompliance);
  event WrapperCreated(address indexed wrapper, string name, string symbol);
  event UnderlyingMapped(address indexed underlying, address indexed wrapper);
  event UnderlyingUnmapped(address indexed underlying, address indexed wrapper);

  event GlobalComplianceChanged(address indexed oldC, address indexed newC);
  event WrapperImplementationUpgraded(address indexed oldImpl, address indexed newImpl);
  event WrapperPausedByFactory(address indexed wrapper, bool paused);
  event Deprecated(address indexed wrapper, string reason);

  event UnderlyingsAdded(address indexed wrapper, address[] tokens);
  event UnderlyingsMigrated(address indexed oldWrapper, address indexed newWrapper, address[] tokens);

  // ---------- Errors ----------
  error ZeroAddress();
  error AlreadyRegistered();
  error NotRegistered();
  error SameAddress();
  error InvalidParams(string);

  /// @param admin Administrator (will be granted DEFAULT_ADMIN_ROLE/OPERATOR_ROLE/PAUSER_ROLE)
  /// @param initialWrapperImplementation Initial DStockWrapper implementation the Beacon points to
  /// @param _globalCompliance Global compliance module address (can be zero)
  constructor(
    address admin,
    address initialWrapperImplementation,
    address _globalCompliance
  ) {
    if (admin == address(0) || initialWrapperImplementation == address(0)) revert ZeroAddress();

    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(OPERATOR_ROLE, admin);
    _grantRole(PAUSER_ROLE, admin);

    // Deploy the Beacon (note: when created in the constructor, UpgradeableBeacon owner is this factory itself)
    beacon = new UpgradeableBeacon(initialWrapperImplementation, address(this));

    globalCompliance = _globalCompliance;

    emit FactoryInitialized(admin, initialWrapperImplementation, address(beacon), _globalCompliance);
  }

  // ============================ Create ============================

  /// @notice Create a new DStockWrapper (BeaconProxy) and map all initial underlyings to it.
  /// @dev The proxy is deployed; logic is shared via the Beacon; initialization uses InitParams struct.
  ///      `p.initialUnderlyings` may be empty (wrapper can add later), but if non-empty, each must be unused.
  function createWrapper(IDStockWrapper.InitParams calldata p)
    external
    onlyRole(OPERATOR_ROLE)
    returns (address wrapper)
  {
    // Clone params so we can override compliance/factoryRegistry
    IDStockWrapper.InitParams memory _p = p;

    // Fill compliance if not provided
    if (_p.compliance == address(0)) {
      _p.compliance = globalCompliance;
    }
    // Inject back-pointer to factory
    _p.factoryRegistry = address(this);

    // Validate initial underlyings (no duplicates, none already mapped)
    if (_p.initialUnderlyings.length > 0) {
      for (uint256 i = 0; i < _p.initialUnderlyings.length; i++) {
        address u = _p.initialUnderlyings[i];
        if (u == address(0)) revert ZeroAddress();
        if (wrapperOf[u] != address(0)) revert AlreadyRegistered(); // already mapped elsewhere
      }
    }

    bytes memory initData = abi.encodeWithSelector(IDStockWrapper.initialize.selector, _p);

    // Deploy BeaconProxy and initialize
    wrapper = address(new BeaconProxy(address(beacon), initData));

    // Bookkeeping for wrapper
    isWrapper[wrapper] = true;
    allWrappers.push(wrapper);
    emit WrapperCreated(wrapper, _p.name, _p.symbol);

    // Map each initial underlying -> wrapper
    for (uint256 i = 0; i < _p.initialUnderlyings.length; i++) {
      address u = _p.initialUnderlyings[i];
      wrapperOf[u] = wrapper;
      emit UnderlyingMapped(u, wrapper);
    }
  }

  // ====================== Governance / Ops =======================

  /// @notice Upgrade the implementation for all wrappers (through the Beacon)
  /// @dev The Beacon owner is this factory contract, so the upgrade is executed here
  function setWrapperImplementation(address newImplementation)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (newImplementation == address(0)) revert ZeroAddress();
    address oldImpl = beacon.implementation();
    if (oldImpl == newImplementation) revert SameAddress();

    beacon.upgradeTo(newImplementation);
    emit WrapperImplementationUpgraded(oldImpl, newImplementation);
  }

  /// @notice Set the global compliance module (wrappers may override locally)
  function setGlobalCompliance(address c) external onlyRole(OPERATOR_ROLE) {
    address old = globalCompliance;
    if (old == c) revert SameAddress();
    globalCompliance = c; // can be zero to disable compliance checks by default
    emit GlobalComplianceChanged(old, c);
  }

  /// @notice Factory-level pause/unpause for a specific wrapper (wrapper must implement setPausedByFactory)
  function pauseWrapper(address wrapper, bool paused) external onlyRole(PAUSER_ROLE) {
    if (!isWrapper[wrapper]) revert NotRegistered();
    IDStockWrapper(wrapper).setPausedByFactory(paused);
    emit WrapperPausedByFactory(wrapper, paused);
  }

  /// @notice Mark a wrapper as deprecated (metadata only; does not change on-chain balances)
  function deprecate(address wrapper, string calldata reason) external onlyRole(OPERATOR_ROLE) {
    if (!isWrapper[wrapper]) revert NotRegistered();
    deprecated[wrapper] = true;
    deprecateReason[wrapper] = reason;
    emit Deprecated(wrapper, reason);
  }

  /// @notice Add and map new underlyings to an existing wrapper.
  /// @dev Calls wrapper.addUnderlying() then records the mapping.
  function addUnderlyings(address wrapper, address[] calldata tokens)
    external
    onlyRole(OPERATOR_ROLE)
  {
    if (!isWrapper[wrapper]) revert NotRegistered();
    if (deprecated[wrapper]) revert InvalidParams("deprecated wrapper");
    if (IDStockWrapper(wrapper).factoryRegistry() != address(this)) revert InvalidParams("foreign wrapper");
    if (tokens.length == 0) revert InvalidParams("empty tokens");

    // Validate and ensure no conflicts before mutating state
    for (uint256 i = 0; i < tokens.length; i++) {
      address u = tokens[i];
      if (u == address(0)) revert ZeroAddress();
      if (wrapperOf[u] != address(0)) revert AlreadyRegistered();
    }

    // Call wrapper to enable each underlying, then map
    for (uint256 i = 0; i < tokens.length; i++) {
      IDStockWrapper(wrapper).addUnderlying(tokens[i]);
      wrapperOf[tokens[i]] = wrapper;
      emit UnderlyingMapped(tokens[i], wrapper);
    }

    emit UnderlyingsAdded(wrapper, tokens);
  }

  /// @notice Remove a single underlying mapping (e.g., when disabled in the wrapper).
  /// @dev This only updates the factory registry; wrapper is expected to be disabled via setUnderlyingEnabled(false).
  function removeUnderlyingMapping(address underlying) external onlyRole(OPERATOR_ROLE) {
    address w = wrapperOf[underlying];
    if (w == address(0)) revert NotRegistered();
    wrapperOf[underlying] = address(0);
    emit UnderlyingUnmapped(underlying, w);
  }

  /// @notice Migrate a batch of underlyings from `oldWrapper` to `newWrapper`.
  /// @dev Requires admin; will call `addUnderlying` on the new wrapper and remap each token.
  function migrateUnderlyings(address[] calldata underlyings, address oldWrapper, address newWrapper)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    if (newWrapper == address(0) || oldWrapper == address(0)) revert ZeroAddress();
    if (!isWrapper[oldWrapper]) revert InvalidParams("oldWrapper not a wrapper");
    if (!isWrapper[newWrapper]) revert InvalidParams("newWrapper not a wrapper");
    if (underlyings.length == 0) revert InvalidParams("empty underlyings");

    // Validate ownership & conflicts
    for (uint256 i = 0; i < underlyings.length; i++) {
      address u = underlyings[i];
      if (wrapperOf[u] != oldWrapper) revert InvalidParams("token not owned by oldWrapper");
    }

    // Add to new, remap
    for (uint256 i = 0; i < underlyings.length; i++) {
      address u = underlyings[i];
      IDStockWrapper(newWrapper).addUnderlying(u);
      wrapperOf[u] = newWrapper;
      emit UnderlyingMapped(u, newWrapper);
    }

    emit UnderlyingsMigrated(oldWrapper, newWrapper, underlyings);
  }

  // ============================= Views ===========================

  function getWrapper(address underlying) external view returns (address) {
    return wrapperOf[underlying];
  }

  function countWrappers() external view returns (uint256) {
    return allWrappers.length;
  }

  /// @notice Get paginated wrapper list
  function getAllWrappers(uint256 offset, uint256 limit) external view returns (address[] memory result) {
    uint256 n = allWrappers.length;
    if (offset >= n) return new address[](0);
    uint256 end = offset + limit;
    if (end > n) end = n;

    result = new address[](end - offset);
    for (uint256 i = offset; i < end; i++) {
      result[i - offset] = allWrappers[i];
    }
  }
}
