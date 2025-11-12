// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IDStockCompliance} from "./interfaces/IDStockCompliance.sol";
import {IDStockWrapper} from "./interfaces/IDStockWrapper.sol";

/// @title DStockWrapper (multi-underlying, dynamic pool valuation)
/// @notice Multiple underlyings (e.g. TSLAx/TSLAy/...) map to ONE d-stock.
///         Shares represent pro-rata claim on the pool. Fees/rebases are handled per-underlying.
///         Safe rescaling supports arbitrary token decimals (both <18 and >18).
contract DStockWrapper is
  Initializable,
  ERC20Upgradeable,
  AccessControlUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable
{
  using SafeERC20 for IERC20;

  // ---------- ROLES ----------
  bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
  bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");

  // ---------- CONSTANTS ----------
  uint256 private constant RAY = 1e18;

  // ---------- CONFIG ----------
  address public factoryRegistry;       // back-pointer to factory
  IDStockCompliance public compliance;  // can be 0
  constructor() {
    _disableInitializers();
  }
  address public treasury;              // fee sink (can be 0)
  uint16  public wrapFeeBps;            // 0 ok
  uint16  public unwrapFeeBps;          // 0 ok
  uint256 public cap;                   // 18-decimal cap; 0 => unlimited
  string  public termsURI;              // terms
  bool    public pausedByFactory;       // factory-level pause
  bool    public wrapUnwrapPaused;      // local pause for wrap/unwrap only

  // ---------- TOKEN META ----------
  string private _tokenName;
  string private _tokenSymbol;

  // ---------- SHARES + MULTIPLIER ----------
  mapping(address => uint256) internal _shares;
  uint256 internal _totalShares;

  // ---------- MULTI-UNDERLYING ----------
  struct UnderlyingInfo {
    bool    enabled;
    uint8   decimals;      // 0 => not initialized
    // Per-underlying rebase/fee parameters
    uint8   feeMode;          
    uint256 feePerPeriodRay;   // Ray
    uint32  periodLength;      // seconds
    uint64  lastTimeFeeApplied; // ts
    uint8   feeModel;          // reserved / type
  }
  mapping(address => UnderlyingInfo) internal underlyings;
  address[] internal allUnderlyings;

  // ---------- EVENTS ----------
  event Wrapped(address indexed token, address indexed from, address indexed to,
                uint256 gross18, uint256 fee18, uint256 net18, uint256 mintedShares);
  event Unwrapped(address indexed token, address indexed from, address indexed to,
                  uint256 gross18, uint256 fee18, uint256 net18, uint256 burnedShares);

  event ComplianceChanged(address indexed oldC, address indexed newC);
  event TreasuryChanged(address indexed oldT, address indexed newT);
  event WrapFeeChanged(uint16 oldBps, uint16 newBps);
  event UnwrapFeeChanged(uint16 oldBps, uint16 newBps);
  event CapChanged(uint256 oldCap, uint256 newCap);
  event TermsURIChanged(string oldURI, string newURI);
  event TokenNameChanged(string oldName, string newName);
  event TokenSymbolChanged(string oldSymbol, string newSymbol);
  event UnderlyingAdded(address indexed token, uint8 decimals);
  event UnderlyingStatusChanged(address indexed token, bool enabled);
  event ForceMovedToTreasury(address indexed from, address indexed treasury, uint256 amount, uint256 shares);
  event WrapUnwrapPauseChanged(bool isPaused);
  event UnderlyingRebaseParamsChanged(address indexed token, uint8 feeMode, uint256 feePerPeriodRay, uint32 periodLength);
  event UnderlyingHarvested(address indexed token, uint256 periodsApplied, uint64 newAnchorTs);
  event UnderlyingSettledAndSkimmed(address indexed token, uint256 periodsApplied, uint64 newAnchorTs, uint256 skimToken);

  // ---------- ERRORS ----------
  error NotAllowed();
  error ZeroAddress();
  error CapExceeded();
  error TooSmall();
  error InsufficientShares();
  error UnknownUnderlying();
  error UnsupportedUnderlying();
  error InsufficientLiquidity();
  error FeeTreasuryRequired();
  error NoChange();
  error WrapUnwrapPaused();

  // ---------- INITIALIZER ----------
  function initialize(IDStockWrapper.InitParams calldata p) external initializer {
    if (p.admin == address(0)) revert ZeroAddress();
    if (p.factoryRegistry == address(0)) revert ZeroAddress();
    if ((p.wrapFeeBps > 0 || p.unwrapFeeBps > 0) && p.treasury == address(0)) revert FeeTreasuryRequired();

    _tokenName  = p.name;
    _tokenSymbol = p.symbol;

    __ERC20_init(p.name, p.symbol);
    __AccessControl_init();
    __Pausable_init();
    __ReentrancyGuard_init();

    _grantRole(DEFAULT_ADMIN_ROLE, p.admin);
    _grantRole(OPERATOR_ROLE, p.admin);
    _grantRole(PAUSER_ROLE, p.admin);

    factoryRegistry    = p.factoryRegistry;
    compliance         = IDStockCompliance(p.compliance);
    treasury           = p.treasury;
    wrapFeeBps         = p.wrapFeeBps;
    unwrapFeeBps       = p.unwrapFeeBps;
    cap                = p.cap;
    termsURI           = p.termsURI;
    // optional initial underlyings
    for (uint256 i = 0; i < p.initialUnderlyings.length; ++i) {
      _addUnderlying(p.initialUnderlyings[i]);
    }
  }

  // ---------- ERC20 ----------
  function name()   public view override returns (string memory) { return _tokenName; }
  function symbol() public view override returns (string memory) { return _tokenSymbol; }
  function decimals() public pure override returns (uint8) { return 18; }
  function totalSupply() public view override returns (uint256) { return _toAmountView(_totalShares); }
  function balanceOf(address a) public view override returns (uint256) { return _toAmountView(_shares[a]); }

  // ---------- BUSINESS ----------
  /// @notice Wrap `amount` of a specific `token` into the unified d-stock.
  function wrap(address token, uint256 amount, address to)
    external
    nonReentrant
    whenOperational
    returns (uint256 net18, uint256 mintedShares)
  {
    if (wrapUnwrapPaused) revert WrapUnwrapPaused();
    UnderlyingInfo storage info = underlyings[token];
    if (info.decimals == 0) revert UnknownUnderlying();
    if (!info.enabled)      revert UnsupportedUnderlying();
    if (wrapFeeBps > 0 && treasury == address(0)) revert FeeTreasuryRequired();

    _checkCompliance(msg.sender, to, amount, 1 /* Wrap */);

    // Settle + skim all enabled underlyings atomically to avoid timing arbitrage across tokens
    _settleAndSkimAll();

    // 3) Snapshot pool value before deposit (prevent self-dilution)
    uint256 availBefore = _poolAvailable18();

    // 4) Pull funds
    uint256 balBefore = IERC20(token).balanceOf(address(this));
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    uint256 received = IERC20(token).balanceOf(address(this)) - balBefore;

    // 5) Fees and net deposit (compute in token units to avoid double rounding)
    uint256 feeToken = (wrapFeeBps == 0) ? 0 : (received * wrapFeeBps) / 10_000;
    uint256 netToken = received - feeToken;
    if (netToken == 0) revert TooSmall();
    if (feeToken > 0 && treasury != address(0)) {
      IERC20(token).safeTransfer(treasury, feeToken);
    }
    uint256 gross18 = _normalize(token, received);
    uint256 fee18   = _normalize(token, feeToken);
    net18 = _normalize(token, netToken);

    // 6) Effective contributed value: after settlement factor=1, equals net18
    uint256 depositEff18 = net18;
    uint256 s;
    if (_totalShares == 0) {
      s = depositEff18;
    } else {
      if (availBefore == 0) revert TooSmall();
      s = (depositEff18 * _totalShares) / availBefore;
    }
    if (s == 0) revert TooSmall();
    if (cap != 0 && (availBefore + depositEff18) > cap) revert CapExceeded();

    _shares[to] += s;
    _totalShares += s;
    mintedShares = s;

    emit Wrapped(token, msg.sender, to, gross18, fee18, net18, s);
    emit Transfer(address(0), to, _toAmount(s));
  }

  /// @notice Unwrap `amount` (token units) of `token` out to `to`.
  function unwrap(address token, uint256 amount, address to)
    external
    nonReentrant
    whenOperational
  {
    if (wrapUnwrapPaused) revert WrapUnwrapPaused();
    UnderlyingInfo storage info = underlyings[token];
    if (info.decimals == 0) revert UnknownUnderlying();
    if (!info.enabled)      revert UnsupportedUnderlying();
    if (unwrapFeeBps > 0 && treasury == address(0)) revert FeeTreasuryRequired();

    _checkCompliance(msg.sender, to, amount, 2 /* Unwrap */);

    // Settle + skim all enabled underlyings atomically to avoid timing arbitrage across tokens
    _settleAndSkimAll();
    uint256 gross18 = _normalize(token, amount);

    // Burn shares based on pre-withdraw pool value
    uint256 totalAvailBefore = _poolAvailable18();
    if (_totalShares == 0 || totalAvailBefore == 0) revert InsufficientLiquidity();
    // Burn shares using ceil division to cover gross18 at pre-withdraw valuation
    uint256 s = (gross18 * _totalShares + (totalAvailBefore - 1)) / totalAvailBefore;
    if (_shares[msg.sender] < s) revert InsufficientShares();

    // compute fee/net in token native units to avoid double rounding; protect zero-net
    uint256 feeToken = (unwrapFeeBps == 0) ? 0 : (amount * unwrapFeeBps) / 10_000;
    uint256 netToken = amount - feeToken;
    if (netToken == 0) revert TooSmall();

    // for events, keep normalized values for analytics
    uint256 fee18 = (unwrapFeeBps == 0) ? 0 : (gross18 * unwrapFeeBps) / 10_000;
    uint256 net18 = gross18 - fee18;

    uint256 needOut = netToken + ((treasury != address(0) && feeToken > 0) ? feeToken : 0);
    uint256 currentBal = IERC20(token).balanceOf(address(this));
    if (currentBal < needOut) revert InsufficientLiquidity();

    _shares[msg.sender] -= s;
    _totalShares        -= s;

    if (feeToken > 0 && treasury != address(0)) {
      IERC20(token).safeTransfer(treasury, feeToken);
    }
    IERC20(token).safeTransfer(to, netToken);

    emit Unwrapped(token, msg.sender, to, gross18, fee18, net18, s);
    emit Transfer(msg.sender, address(0), _toAmount(s));
  }

  // transfer at shares layer (no per-tx fee)
  function _update(address from, address to, uint256 value)
    internal
    override
    whenOperational
  {
    if (value == 0) return;

    _checkCompliance(from, to, value, 0 /* Transfer */);

    uint256 s = _toShares(value);
    if (s == 0 || _shares[from] < s) revert InsufficientShares();

    _shares[from] -= s;
    _shares[to]   += s;

    emit Transfer(from, to, _toAmount(s));
  }

  // ---------- GOVERNANCE ----------
  function setCompliance(address c) external onlyRole(OPERATOR_ROLE) {
    address old = address(compliance);
    if (old == c) revert NoChange();
    compliance = IDStockCompliance(c);
    emit ComplianceChanged(old, c);
  }

  function setTreasury(address t) external onlyRole(OPERATOR_ROLE) {
    address old = treasury;
    if (old == t) revert NoChange();
    if (t == address(0) && (wrapFeeBps > 0 || unwrapFeeBps > 0)) revert FeeTreasuryRequired();
    treasury = t;
    emit TreasuryChanged(old, t);
  }

  function setWrapFeeBps(uint16 bps) external onlyRole(OPERATOR_ROLE) {
    uint16 old = wrapFeeBps;
    if (old == bps) revert NoChange();
    if (bps > 0 && treasury == address(0)) revert FeeTreasuryRequired();
    wrapFeeBps = bps;
    emit WrapFeeChanged(old, bps);
  }

  function setUnwrapFeeBps(uint16 bps) external onlyRole(OPERATOR_ROLE) {
    uint16 old = unwrapFeeBps;
    if (old == bps) revert NoChange();
    if (bps > 0 && treasury == address(0)) revert FeeTreasuryRequired();
    unwrapFeeBps = bps;
    emit UnwrapFeeChanged(old, bps);
  }

  function setCap(uint256 newCap) external onlyRole(OPERATOR_ROLE) {
    uint256 old = cap;
    if (old == newCap) revert NoChange();
    cap = newCap;
    emit CapChanged(old, newCap);
  }

  function setTermsURI(string calldata uri) external onlyRole(OPERATOR_ROLE) {
    string memory old = termsURI;
    if (keccak256(bytes(old)) == keccak256(bytes(uri))) revert NoChange();
    termsURI = uri;
    emit TermsURIChanged(old, uri);
  }

  function setTokenName(string calldata newName) external onlyRole(OPERATOR_ROLE) {
    require(bytes(newName).length != 0, "empty name");
    string memory old = _tokenName;
    if (keccak256(bytes(old)) == keccak256(bytes(newName))) revert NoChange();
    _tokenName = newName;
    emit TokenNameChanged(old, newName);
  }

  function setTokenSymbol(string calldata newSymbol) external onlyRole(OPERATOR_ROLE) {
    require(bytes(newSymbol).length != 0, "empty symbol");
    string memory old = _tokenSymbol;
    if (keccak256(bytes(old)) == keccak256(bytes(newSymbol))) revert NoChange();
    _tokenSymbol = newSymbol;
    emit TokenSymbolChanged(old, newSymbol);
  }

  function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
  function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

  function setPausedByFactory(bool p) external {
    if (msg.sender != factoryRegistry && !hasRole(PAUSER_ROLE, msg.sender)) revert NotAllowed();
    pausedByFactory = p;
  }

  /// @notice Pause or unpause only wrapping/unwrapping while keeping transfers operational.
  function setWrapUnwrapPaused(bool p) external onlyRole(PAUSER_ROLE) {
    if (wrapUnwrapPaused == p) revert NoChange();
    wrapUnwrapPaused = p;
    emit WrapUnwrapPauseChanged(p);
  }

  /// @notice Apply a split/reverse-split on a specific underlying by adjusting its pool balance.
  /// @dev If numerator > denominator, pulls additional tokens from treasury; if less, sends surplus to treasury.
  function applySplit(address token, uint256 numerator, uint256 denominator)
    external
    onlyRole(OPERATOR_ROLE)
    nonReentrant
  {
    require(numerator > 0 && denominator > 0, "bad ratio");
    UnderlyingInfo storage info = underlyings[token];
    if (info.decimals == 0) revert UnknownUnderlying();
    if (!info.enabled)      revert UnsupportedUnderlying();

    // Settle + skim all first to avoid timing arbitrage across tokens
    _settleAndSkimAll();

    uint256 oldBal = IERC20(token).balanceOf(address(this));
    uint256 targetBal = (oldBal * numerator) / denominator;

    if (targetBal > oldBal) {
      uint256 add = targetBal - oldBal;
      address dst = address(this);
      address src = treasury;
      if (src == address(0)) revert ZeroAddress();
      IERC20(token).safeTransferFrom(src, dst, add);
    } else if (oldBal > targetBal) {
      uint256 remove = oldBal - targetBal;
      address dst = treasury;
      if (dst == address(0)) revert ZeroAddress();
      IERC20(token).safeTransfer(dst, remove);
    }
    // No event reuse; the pool balance itself is authoritative
  }

  /// @notice Set per-underlying rebase/fee parameters.
  function setUnderlyingRebaseParams(address token, uint8 _feeMode, uint256 _feePerPeriodRay, uint32 _periodLength)
    external
    onlyRole(OPERATOR_ROLE)
  {
    UnderlyingInfo storage info = underlyings[token];
    if (info.decimals == 0) revert UnknownUnderlying();
    if (info.feeMode == _feeMode && info.feePerPeriodRay == _feePerPeriodRay && info.periodLength == _periodLength) {
      revert NoChange();
    }
    // Harvest/settle pending fees for this underlying before changing parameters
    // to avoid dropping accrual between the old anchor and now.
    _settleAndSkimUnderlying(token);
    info.feeMode        = _feeMode;
    info.feePerPeriodRay = _feePerPeriodRay;
    info.periodLength    = _periodLength;
    info.lastTimeFeeApplied = uint64(block.timestamp);
    emit UnderlyingRebaseParamsChanged(token, _feeMode, _feePerPeriodRay, _periodLength);
  }

  /// @notice Harvest and skim across all enabled underlyings.
  function harvestAll() external onlyRole(OPERATOR_ROLE) nonReentrant {
    _settleAndSkimAll();
  }

  /// @notice Optional enforcement path: move amount(18) from `from` to `treasury` at shares layer.
  function forceMoveToTreasury(address from, uint256 amount18)
    external
    onlyRole(OPERATOR_ROLE)
    nonReentrant
  {
    address dst = treasury;
    if (dst == address(0)) revert ZeroAddress();
    if (from == dst)       revert NotAllowed();
    if (amount18 == 0)     revert TooSmall();

    uint256 s = _toShares(amount18);
    if (_toAmount(s) < amount18) s += 1;
    if (_shares[from] < s) revert InsufficientShares();

    _shares[from] -= s;
    _shares[dst]  += s;

    uint256 amt = _toAmount(s);
    emit ForceMovedToTreasury(from, dst, amt, s);
    emit Transfer(from, dst, amt);
  }

  // ---------- VIEWS ----------
  function sharesOf(address a) external view returns (uint256) { return _shares[a]; }
  function totalShares() external view returns (uint256) { return _totalShares; }

  function previewWrap(address token, uint256 amountToken)
    external view
    returns (uint256 mintedAmount18, uint256 fee18)
  {
    UnderlyingInfo memory info = underlyings[token];
    if (info.decimals == 0 || !info.enabled) return (0, 0);
    uint256 gross18 = _normalize(token, amountToken);
    fee18 = (wrapFeeBps == 0) ? 0 : (gross18 * wrapFeeBps) / 10_000;
    mintedAmount18 = gross18 - fee18;
  }

  function previewUnwrap(address token, uint256 amountToken)
    external view
    returns (uint256 released18, uint256 fee18)
  {
    UnderlyingInfo memory info = underlyings[token];
    if (info.decimals == 0 || !info.enabled) return (0, 0);
    uint256 gross18 = _normalize(token, amountToken);
    fee18 = (unwrapFeeBps == 0) ? 0 : (gross18 * unwrapFeeBps) / 10_000;
    released18 = gross18 - fee18;
  }

  // multi-underlying views/admin
  function isUnderlyingEnabled(address token) external view returns (bool) {
    return underlyings[token].enabled;
  }

  function listUnderlyings() external view returns (address[] memory) {
    return allUnderlyings;
  }

  function underlyingInfo(address token)
    external
    view
    returns (bool isEnabled, uint8 tokenDecimals, uint256 liquidToken)
  {
    UnderlyingInfo memory info = underlyings[token];
    if (info.decimals == 0) return (false, 0, 0);
    // Effective liquid token = balanceOf * underlyingMultiplier (Ray)
    uint256 bal = IERC20(token).balanceOf(address(this));
    (uint256 m, ) = _previewUnderlyingMultiplierView(info);
    uint256 effective = (bal * m) / RAY;
    return (info.enabled, info.decimals, effective);
  }

  /// @dev Factory-only to preserve registry invariant: one underlying -> one wrapper (Issue-12)
  function addUnderlying(address token) external {
    if (msg.sender != factoryRegistry) revert NotAllowed();
    _addUnderlying(token);
  }

  /// @notice Internal helper used by the factory-only external entrypoint.
  function _setUnderlyingEnabled(address token, bool enabled) internal {
    UnderlyingInfo storage info = underlyings[token];
    if (info.decimals == 0) revert UnknownUnderlying();
    info.enabled = enabled;
    emit UnderlyingStatusChanged(token, enabled);
  }

  /// @notice Factory-only external entrypoint to enable/disable an underlying.
  /// @dev Restricts to exact factoryRegistry to ensure all status changes go via the factory.
  function setUnderlyingEnabled(address token, bool enabled) external {
    if (msg.sender != factoryRegistry) revert NotAllowed();
    _setUnderlyingEnabled(token, enabled);
  }


  /// @dev Business gating: both OZ pause and factory pause must be false.
  modifier whenOperational() {
    require(!paused() && !pausedByFactory, "paused");
    _;
  }

  // Dynamic pool valuation helpers
  function _poolAvailable18() internal view returns (uint256 total18) {
    for (uint256 i = 0; i < allUnderlyings.length; i++) {
      address u = allUnderlyings[i];
      if (!underlyings[u].enabled) continue;
      total18 += _underlyingEffective18(u);
    }
  }

  function _toShares(uint256 amount18) internal view returns (uint256) {
    if (amount18 == 0) return 0;
    if (_totalShares == 0) return amount18;
    uint256 avail18 = _poolAvailable18();
    if (avail18 == 0) return 0;
    return (amount18 * _totalShares) / avail18;
  }

  function _toAmount(uint256 shares) internal view returns (uint256) {
    if (shares == 0) return 0;
    if (_totalShares == 0) return 0;
    uint256 avail18 = _poolAvailable18();
    return (shares * avail18) / _totalShares;
  }

  function _toAmountView(uint256 shares) internal view returns (uint256) {
    if (shares == 0) return 0;
    if (_totalShares == 0) return 0;
    uint256 avail18 = _poolAvailable18();
    return (shares * avail18) / _totalShares;
  }

  // Atomic per-underlying settlement + surplus skim
  function _settleAndSkimUnderlying(address token) internal {
    address dst = treasury;
    UnderlyingInfo storage infoStore = underlyings[token];
    if (infoStore.decimals == 0 || !infoStore.enabled) return;

    // Snapshot info for pre-harvest factor
    UnderlyingInfo memory info = infoStore;

    uint256 skimToken = 0;
    if (dst != address(0)) {
      uint256 balToken = IERC20(token).balanceOf(address(this));
      if (balToken > 0) {
        uint256 raw18 = _normalize(token, balToken);
        (uint256 m, ) = _previewUnderlyingMultiplierView(info);
        uint256 eff18 = (raw18 * m) / RAY;
        if (raw18 > eff18) {
          uint256 surplus18 = raw18 - eff18;
          skimToken = _denormalize(token, surplus18);
          if (skimToken > 0) {
            IERC20(token).safeTransfer(dst, skimToken);
          }
        }
      }
    }

    // Advance anchor after computing skim with pre-harvest factor
    if (info.feeMode != 1 && info.periodLength != 0 && info.feePerPeriodRay != 0 && block.timestamp > info.lastTimeFeeApplied) {
      uint256 elapsed = block.timestamp - info.lastTimeFeeApplied;
      uint256 periods = elapsed / info.periodLength;
      if (periods > 0) {
        uint64 newAnchor = uint64(block.timestamp - (elapsed % info.periodLength));
        infoStore.lastTimeFeeApplied = newAnchor;
        emit UnderlyingHarvested(token, periods, newAnchor);
        emit UnderlyingSettledAndSkimmed(token, periods, newAnchor, skimToken);
        return;
      }
    }
    if (skimToken > 0) {
      emit UnderlyingSettledAndSkimmed(token, 0, infoStore.lastTimeFeeApplied, skimToken);
    }
  }

  // Settle + skim across all enabled underlyings
  function _settleAndSkimAll() internal {
    for (uint256 i = 0; i < allUnderlyings.length; i++) {
      address u = allUnderlyings[i];
      if (!underlyings[u].enabled) continue;
      _settleAndSkimUnderlying(u);
    }
  }

  // ======== PER-UNDERLYING MULTIPLIER (effective liquidity factor) ========
  function _previewUnderlyingMultiplierView(UnderlyingInfo memory info)
    internal
    view
    returns (uint256 newM, uint256 periods)
  {
    // feeMode == 1 => underlying self-rebases/charges; use raw balance (multiplier=1)
    if (info.feeMode == 1) return (RAY, 0);
    if (info.periodLength == 0 || info.feePerPeriodRay == 0) return (RAY, 0);
    if (block.timestamp <= info.lastTimeFeeApplied) return (RAY, 0);
    uint256 elapsed = block.timestamp - info.lastTimeFeeApplied;
    periods = elapsed / info.periodLength;
    if (periods == 0) return (RAY, 0);
    uint256 factor = _rayPow(RAY - info.feePerPeriodRay, periods);
    newM = factor; // relative to 1.0 Ray baseline
  }

  function _underlyingEffective18(address token) internal view returns (uint256 effective18) {
    UnderlyingInfo memory info = underlyings[token];
    if (info.decimals == 0 || !info.enabled) return 0;
    uint256 balToken = IERC20(token).balanceOf(address(this));
    uint256 bal18 = _normalize(token, balToken);
    (uint256 m, ) = _previewUnderlyingMultiplierView(info);
    // feeMode==1 => m=1, equals raw balance; otherwise apply decay factor
    effective18 = (bal18 * m) / RAY;
  }

  /// @dev 10^k with small k (loop), used in segmented scaling to avoid overflow.
  function _pow10(uint8 k) internal pure returns (uint256 r) {
    unchecked {
      r = 1;
      for (uint8 i = 0; i < k; i++) {
        r *= 10;
      }
    }
  }

  /// @dev Safe rescale between arbitrary decimals by segmenting multiply/divide by 10^step (step<=77).
  function _rescale(uint256 amount, uint8 fromDec, uint8 toDec) internal pure returns (uint256) {
    if (fromDec == toDec) return amount;

    if (fromDec < toDec) {
      uint256 diff = uint256(toDec) - uint256(fromDec);
      while (diff > 0) {
        uint8 step = diff > 77 ? uint8(77) : uint8(diff);
        uint256 factor = _pow10(step);
        require(amount == 0 || amount <= type(uint256).max / factor, "scale overflow");
        amount = amount * factor;
        diff -= step;
      }
      return amount;
    } else {
      uint256 diff = uint256(fromDec) - uint256(toDec);
      while (diff > 0) {
        uint8 step = diff > 77 ? uint8(77) : uint8(diff);
        uint256 factor = _pow10(step);
        amount = amount / factor; // floor
        diff -= step;
      }
      return amount;
    }
  }

  /// @dev Convert `amountToken` (token decimals) -> 18-decimal amount
  function _normalize(address token, uint256 amountToken) internal view returns (uint256) {
    uint8 dec = underlyings[token].decimals;
    return _rescale(amountToken, dec, 18);
  }

  /// @dev Convert 18-decimal `amount18` -> token native units (may floor)
  function _denormalize(address token, uint256 amount18) internal view returns (uint256) {
    uint8 dec = underlyings[token].decimals;
    return _rescale(amount18, 18, dec);
  }

  function _checkCompliance(address from, address to, uint256 amount, uint8 action) internal view {
    address c = address(compliance);
    if (c == address(0)) return;
    if (!IDStockCompliance(c).isTransferAllowed(address(this), from, to, amount, action)) {
      revert NotAllowed();
    }
  }

  function _rayPow(uint256 baseRay, uint256 exp) internal pure returns (uint256) {
    uint256 result = RAY;
    while (exp > 0) {
      if (exp & 1 == 1) result = (result * baseRay) / RAY;
      baseRay = (baseRay * baseRay) / RAY;
      exp >>= 1;
    }
    return result;
  }

  function _addUnderlying(address token) internal {
    if (token == address(0)) revert ZeroAddress();
    UnderlyingInfo storage info = underlyings[token];
    if (info.decimals != 0) revert NotAllowed(); // already exists
    uint8 dec = IERC20Metadata(token).decimals(); // no limit now; we rescale safely both ways
    info.decimals    = dec;
    info.enabled     = true;
    info.feeMode        = 1; // default: assume underlying self-rebases/charges
    info.feePerPeriodRay = 0;
    info.periodLength    = 0;
    info.lastTimeFeeApplied = uint64(block.timestamp);
    allUnderlyings.push(token);
    emit UnderlyingAdded(token, dec);
  }  
}

