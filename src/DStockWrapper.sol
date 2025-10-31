// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IDStockCompliance} from "./interfaces/IDStockCompliance.sol";
import {IDStockWrapper} from "./interfaces/IDStockWrapper.sol";

/// @title DStockWrapper (multi-underlying, safe decimals rescaling)
/// @notice Multiple underlyings (e.g. TSLAx/TSLAy/...) can map to ONE d-stock.
///         Shares × multiplier (Ray=1e18) accounting; BPS fees; holding fee; split; force move.
///         This version adds safe rescaling for arbitrary token decimals (both <18 and >18).
contract DStockWrapper is
  Initializable,
  ERC20Upgradeable,
  AccessControlUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  UUPSUpgradeable
{
  using SafeERC20 for IERC20;

  // ---------- ROLES ----------
  bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
  bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");
  bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

  // ---------- CONSTANTS ----------
  uint256 private constant RAY = 1e18;

  // ---------- CONFIG ----------
  address public factoryRegistry;       // optional back-pointer
  IDStockCompliance public compliance;  // can be 0
  address public treasury;              // fee sink (can be 0)
  uint16  public wrapFeeBps;            // 0 ok
  uint16  public unwrapFeeBps;          // 0 ok
  uint256 public cap;                   // 18-decimal cap; 0 => unlimited
  string  public termsURI;              // terms
  bool    public pausedByFactory;       // factory-level pause

  // ---------- TOKEN META ----------
  string private _tokenName;
  string private _tokenSymbol;

  // ---------- SHARES + MULTIPLIER ----------
  mapping(address => uint256) internal _shares;
  uint256 internal _totalShares;
  uint256 public  multiplier;           // Ray; amount = shares * multiplier / RAY

  // ---------- HOLDING FEE ----------
  uint256 public feePerPeriodRay;       // Ray
  uint32  public periodLength;          // seconds
  uint64  public lastTimeFeeApplied;    // ts
  uint8   public feeModel;              // reserved

  // ---------- MULTI-UNDERLYING ----------
  struct UnderlyingInfo {
    bool    enabled;
    uint8   decimals;      // 0 => not initialized
    uint256 liquidToken;   // tracked redeemable liquidity (token units)
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
  event MultiplierUpdated(uint256 newMultiplier);
  event RebaseParamsChanged(uint256 feePerPeriodRay, uint32 periodLength, uint8 feeModel);
  event SplitApplied(uint256 numerator, uint256 denominator, uint256 oldM, uint256 newM);
  event TokenNameChanged(string oldName, string newName);
  event TokenSymbolChanged(string oldSymbol, string newSymbol);
  event UnderlyingAdded(address indexed token, uint8 decimals);
  event UnderlyingStatusChanged(address indexed token, bool enabled);
  event ForceMovedToTreasury(address indexed from, address indexed treasury, uint256 amount, uint256 shares);

  // ---------- ERRORS ----------
  error NotAllowed();
  error ZeroAddress();
  error CapExceeded();
  error TooSmall();
  error InsufficientShares();
  error UnknownUnderlying();
  error UnsupportedUnderlying();
  error InsufficientLiquidity();

  // ---------- INITIALIZER ----------
  function initialize(IDStockWrapper.InitParams calldata p) external initializer {
    if (p.admin == address(0)) revert ZeroAddress();

    _tokenName  = p.name;
    _tokenSymbol = p.symbol;

    __ERC20_init(p.name, p.symbol);
    __AccessControl_init();
    __Pausable_init();
    __ReentrancyGuard_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, p.admin);
    _grantRole(OPERATOR_ROLE, p.admin);
    _grantRole(PAUSER_ROLE, p.admin);
    _grantRole(UPGRADER_ROLE, p.admin);

    factoryRegistry    = p.factoryRegistry;
    compliance         = IDStockCompliance(p.compliance);
    treasury           = p.treasury;
    wrapFeeBps         = p.wrapFeeBps;
    unwrapFeeBps       = p.unwrapFeeBps;
    cap                = p.cap;
    termsURI           = p.termsURI;

    multiplier         = (p.initialMultiplierRay == 0) ? RAY : p.initialMultiplierRay;
    feePerPeriodRay    = p.feePerPeriodRay;
    periodLength       = p.periodLength;
    feeModel           = p.feeModel;
    lastTimeFeeApplied = uint64(block.timestamp);

    // optional initial underlyings
    for (uint256 i = 0; i < p.initialUnderlyings.length; ++i) {
      _addUnderlying(p.initialUnderlyings[i]);
    }
  }

  // ---------- ERC20 ----------
  function name()   public view override returns (string memory) { return _tokenName; }
  function symbol() public view override returns (string memory) { return _tokenSymbol; }
  function decimals() public pure override returns (uint8) { return 18; }
  function totalSupply() public view override returns (uint256) { return _toAmount(_totalShares); }
  function balanceOf(address a) public view override returns (uint256) { return _toAmount(_shares[a]); }

  // ---------- BUSINESS ----------
  /// @notice Wrap `amount` of a specific `token` into the unified d-stock.
  function wrap(address token, uint256 amount, address to)
    external
    nonReentrant
    whenOperational
    updateMultiplier
    returns (uint256 net18, uint256 mintedShares)
  {
    UnderlyingInfo storage info = underlyings[token];
    if (info.decimals == 0) revert UnknownUnderlying();
    if (!info.enabled)      revert UnsupportedUnderlying();

    _checkCompliance(msg.sender, to, amount, 1 /* Wrap */);

    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

    uint256 gross18 = _normalize(token, amount);
    uint256 fee18   = (wrapFeeBps == 0) ? 0 : (gross18 * wrapFeeBps) / 10_000;
    net18 = gross18 - fee18;

    // move fee to treasury (token units) and track net liquidity
    if (fee18 > 0 && treasury != address(0)) {
      uint256 feeToken = _denormalize(token, fee18);
      if (feeToken > 0) IERC20(token).safeTransfer(treasury, feeToken);
      info.liquidToken += (amount - feeToken);
    } else {
      info.liquidToken += amount;
    }

    uint256 s = _toShares(net18);
    if (s == 0) revert TooSmall();
    if (cap != 0 && _toAmount(_totalShares + s) > cap) revert CapExceeded();

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
    updateMultiplier
  {
    UnderlyingInfo storage info = underlyings[token];
    if (info.decimals == 0) revert UnknownUnderlying();
    if (!info.enabled)      revert UnsupportedUnderlying();

    _checkCompliance(msg.sender, to, amount, 2 /* Unwrap */);

    uint256 gross18 = _normalize(token, amount);

    // burn shares (ceil to cover gross18 at current multiplier)
    uint256 s = _toShares(gross18);
    if (_toAmount(s) < gross18) s += 1;
    if (_shares[msg.sender] < s) revert InsufficientShares();

    uint256 fee18 = (unwrapFeeBps == 0) ? 0 : (gross18 * unwrapFeeBps) / 10_000;
    uint256 net18 = gross18 - fee18;

    uint256 feeToken = _denormalize(token, fee18);
    uint256 netToken = _denormalize(token, net18);

    if (info.liquidToken < netToken) revert InsufficientLiquidity();

    _shares[msg.sender] -= s;
    _totalShares        -= s;

    info.liquidToken    -= netToken;
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
    updateMultiplier
    whenOperational
  {
    if (from == address(0) || to == address(0)) {
      super._update(from, to, value);
      return;
    }
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
    compliance = IDStockCompliance(c);
    emit ComplianceChanged(old, c);
  }

  function setTreasury(address t) external onlyRole(OPERATOR_ROLE) {
    address old = treasury;
    treasury = t;
    emit TreasuryChanged(old, t);
  }

  function setWrapFeeBps(uint16 bps) external onlyRole(OPERATOR_ROLE) {
    uint16 old = wrapFeeBps;
    wrapFeeBps = bps;
    emit WrapFeeChanged(old, bps);
  }

  function setUnwrapFeeBps(uint16 bps) external onlyRole(OPERATOR_ROLE) {
    uint16 old = unwrapFeeBps;
    unwrapFeeBps = bps;
    emit UnwrapFeeChanged(old, bps);
  }

  function setCap(uint256 newCap) external onlyRole(OPERATOR_ROLE) {
    uint256 old = cap;
    cap = newCap;
    emit CapChanged(old, newCap);
  }

  function setTermsURI(string calldata uri) external onlyRole(OPERATOR_ROLE) {
    string memory old = termsURI;
    termsURI = uri;
    emit TermsURIChanged(old, uri);
  }

  function setTokenName(string calldata newName) external onlyRole(OPERATOR_ROLE) {
    require(bytes(newName).length != 0, "empty name");
    string memory old = _tokenName;
    _tokenName = newName;
    emit TokenNameChanged(old, newName);
  }

  function setTokenSymbol(string calldata newSymbol) external onlyRole(OPERATOR_ROLE) {
    require(bytes(newSymbol).length != 0, "empty symbol");
    string memory old = _tokenSymbol;
    _tokenSymbol = newSymbol;
    emit TokenSymbolChanged(old, newSymbol);
  }

  function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
  function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

  function setPausedByFactory(bool p) external {
    if (msg.sender != factoryRegistry && !hasRole(PAUSER_ROLE, msg.sender)) revert NotAllowed();
    pausedByFactory = p;
  }

  function applySplit(uint256 numerator, uint256 denominator)
    external
    onlyRole(OPERATOR_ROLE)
    updateMultiplier
  {
    require(numerator > 0 && denominator > 0, "bad ratio");
    uint256 oldM = multiplier;
    uint256 newM = (oldM * numerator) / denominator;
    multiplier = newM > 0 ? newM : 1;
    emit SplitApplied(numerator, denominator, oldM, multiplier);
    emit MultiplierUpdated(multiplier);
  }

  function setRebaseParams(uint256 _feePerPeriodRay, uint32 _periodLength, uint8 _feeModel)
    external onlyRole(OPERATOR_ROLE) updateMultiplier
  {
    feePerPeriodRay = _feePerPeriodRay;
    periodLength    = _periodLength;
    feeModel        = _feeModel;
    emit RebaseParamsChanged(_feePerPeriodRay, _periodLength, _feeModel);
  }

  /// @notice Optional enforcement path: move amount(18) from `from` to `treasury` at shares layer.
  function forceMoveToTreasury(address from, uint256 amount18)
    external
    onlyRole(OPERATOR_ROLE)
    nonReentrant
    updateMultiplier
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

  function getCurrentMultiplier() external view returns (uint256 newMultiplier, uint256 periodsElapsed) {
    (newMultiplier, periodsElapsed) = _previewApplyAccruedFee(multiplier, lastTimeFeeApplied);
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
    returns (bool enabled, uint8 decimals, uint256 liquidToken)
  {
    UnderlyingInfo memory info = underlyings[token];
    return (info.enabled, info.decimals, info.liquidToken);
  }

  function addUnderlying(address token) external onlyRole(OPERATOR_ROLE) {
    _addUnderlying(token);
  }

  function setUnderlyingEnabled(address token, bool enabled) external onlyRole(OPERATOR_ROLE) {
    UnderlyingInfo storage info = underlyings[token];
    if (info.decimals == 0) revert UnknownUnderlying();
    info.enabled = enabled;
    emit UnderlyingStatusChanged(token, enabled);
  }

  // ---------- INTERNAL ----------
  modifier updateMultiplier() {
    _applyAccruedFee();
    _;
  }

  /// @dev Business gating: both OZ pause and factory pause must be false.
  modifier whenOperational() {
    require(!paused() && !pausedByFactory, "paused");
    _;
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  function _toShares(uint256 amount18) internal view returns (uint256) {
    return (amount18 == 0) ? 0 : (amount18 * RAY) / multiplier;
  }

  function _toAmount(uint256 shares) internal view returns (uint256) {
    return (shares == 0) ? 0 : (shares * multiplier) / RAY;
  }

  // ======== SAFE RESCALING (supports decimals > 18) ========

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

  // lazy holding-fee: m *= (1 - f)^n
  function _applyAccruedFee() internal {
    (uint256 m, uint256 periods) = _previewApplyAccruedFee(multiplier, lastTimeFeeApplied);
    if (periods == 0) return;
    multiplier = m > 0 ? m : 1;
    lastTimeFeeApplied = uint64(block.timestamp - ((block.timestamp - lastTimeFeeApplied) % periodLength));
    emit MultiplierUpdated(multiplier);
  }

  function _previewApplyAccruedFee(uint256 m, uint256 lastTs) internal view returns (uint256 newM, uint256 periods) {
    if (periodLength == 0 || feePerPeriodRay == 0) return (m, 0);
    if (block.timestamp <= lastTs) return (m, 0);

    uint256 elapsed = block.timestamp - lastTs;
    periods = elapsed / periodLength;
    if (periods == 0) return (m, 0);

    uint256 factor = _rayPow(RAY - feePerPeriodRay, periods);
    newM = (m * factor) / RAY;
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
    info.liquidToken = 0;
    allUnderlyings.push(token);
    emit UnderlyingAdded(token, dec);
  }

  // total implicit liability (18-decimal)
  function totalDebt_() internal view returns (uint256) {
    return _toAmount(_totalShares);
  }

  function harvestFees() external { _applyAccruedFee(); }
}
