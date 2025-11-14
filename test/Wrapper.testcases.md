## `Wrapper.t.sol` Test Cases

- **test_Wrap_Success**: Verifies that a regular user can successfully call `wrap` when compliance checks pass; checks that the underlying token balance decreases, the returned `net` matches the minted `shares`, and the wrapper balance is correct.
- **test_Wrap_Fail_KycOnWrap_From**: A non‑KYC address attempts to `wrap` and is rejected by the compliance module with a `NotAllowed` revert.
- **test_Wrap_Fail_ToMustBeCustody_WhenFlagOn**: When `wrapToCustodyOnly` is enabled, wrapping directly to a non‑custody address must revert; after marking a custody address, wrapping to that custody address should succeed.
- **test_Wrap_Fail_InsufficientAllowance**: When allowance is 0, calling `wrap` must revert because the ERC20 `transferFrom` fails.
- **test_Wrap_Fail_Paused**: When the wrapper is `pause`d, `wrap` calls must fail; after `unpause`, `wrap` should work again.

- **test_FirstWrap_RequiresOperatorRole**: When `_totalShares == 0`, a first `wrap` by a non‑`OPERATOR_ROLE` caller must revert with `NotAllowed`.
- **test_FirstWrap_RequiresMinimumAmount**: When `_totalShares == 0`, even an `OPERATOR_ROLE` caller must revert `TooSmall` if the first `wrap`’s `depositEff18` is less than `minInitialDeposit18`.
- **test_FirstWrap_OperatorWithMinimumAmount_Success**: With `OPERATOR_ROLE` and deposit amount ≥ `minInitialDeposit18`, the first `wrap` should succeed and mint shares 1:1 against the effective deposit.
- **test_AfterFirstWrap_RegularUsersCanWrap**: After the operator completes the first `wrap`, regular users can continue to `wrap` and receive correct shares.

- **test_WrapUnwrapPause_TransferStillWorks**: When `wrapUnwrapPaused` is enabled, both `wrap`/`unwrap` must revert with `WrapUnwrapPaused`, while ERC20 `transfer` remains available; once the flag is turned off, `wrap` works again.

- **test_Unwrap_Success**: User first `wrap`s and then `unwrap`s a specific amount of underlying; checks that the underlying is returned correctly and that wrapper balance and shares decrease accordingly.
- **test_Unwrap_Fail_KycOnUnwrap_From**: An address is KYC’ed at `wrap` time but later loses KYC; subsequent `unwrap` must be rejected by the compliance module (`NotAllowed`).
- **test_Unwrap_Fail_FromMustBeCustody_WhenFlagOn**: With `unwrapFromCustodyOnly` enabled, `unwrap` from a non‑custody address must fail; after marking the address as custody, `unwrap` must succeed.
- **test_Unwrap_Fail_InsufficientShares**: With zero liquidity/shares in the system, calling `unwrap` must fail due to `InsufficientLiquidity`/`InsufficientShares` protection.

- **test_SetTokenMetadata_Success**: `OPERATOR_ROLE` calls `setTokenName` and `setTokenSymbol`; the wrapper’s `name`/`symbol` are updated to the new values.
- **test_SetTokenMetadata_Unauthorized**: Non‑`OPERATOR_ROLE` caller invokes the metadata setters; calls must revert due to access control.

- **test_UnderlyingRebaseParams_And_HarvestAll**: Sets per‑underlying rebase parameters (`feeMode=0`, 1%/day). After some accrual and a call to `harvestAll`, the surplus yield should be skimmed to `treasury`.
- **test_UnderlyingFeeMode1_NoSkimOnHarvest**: With `feeMode=1` (underlying self‑rebasing), `harvestAll` must not skim funds and the `treasury` balance must remain unchanged.
- **test_SettleAndSkim_OnWrap_RemovesSurplusFirst**: After enabling wrapper‑side fees and creating notional surplus, a subsequent `wrap` must first settle+skim so that `treasury`’s balance increases.
- **test_SettleAndSkim_OnUnwrap_RemovesSurplusFirst**: Similarly, before `unwrap`, the wrapper must settle+skim, ensuring that surplus is harvested before redemption.
- **test_SetUnderlyingRebaseParams_HarvestsBeforeUpdate**: Updating fee parameters for an underlying should first harvest/skim accrued fees so `treasury` gets all fees up to the update.

- **feeMode=1 self‑rebasing underlying and its impact on wrap/unwrap**
  - **test_RebaseToken_PositiveRebase_AllowsUnwrap**: Using a `feeMode=1` rebase token, after building a pool and giving a user a position, directly minting underlying to the wrapper (simulating positive rebase) should still allow the user to `unwrap` based on nominal amounts without any legacy `liquidToken` lockups or anomalies.
  - **test_RebaseToken_NegativeRebase_TriggersInsufficientLiquidity**: With the same kind of token, after establishing liquidity, force‑burn most of the wrapper’s underlying balance (negative rebase). A subsequent large `unwrap` attempt should revert with `InsufficientLiquidity` rather than producing dirty accounting or incorrect redemption.

- **test_ApplySplit_PerUnderlying_Authorized_And_Unauthorized**: `OPERATOR_ROLE` can call `applySplit` to adjust a specific underlying’s pool balance (surplus going to `treasury`); unauthorized callers must revert.

- **test_AddUnderlying_Authorized_Success_WrapUnwrap_OK**: `factory`/operator successfully adds a second underlying; users can `wrap/unwrap` the new underlying normally.
- **test_AddUnderlying_Unauthorized_Fail_Then_WrapUnwrap_Fail**: Non‑factory caller to `addUnderlying` must revert; `wrap/unwrap` on an unknown underlying also must revert with `UnknownUnderlying`.

- **test_DisableUnderlying_Authorized_Then_WrapUnwrap_Fail**: When there is liquidity and the factory disables a given underlying, all `wrap/unwrap` on that underlying must revert with `UnsupportedUnderlying`.
- **test_DisableUnderlying_Unauthorized_NoEffect_WrapStillOK**: Non‑factory calls to `setUnderlyingEnabled` must revert and must not affect state; subsequent `wrap` should still succeed.

- **view coverage**
  - `previewWrap`: For different underlyings and amounts, verifies that returned `mintedAmount18` and `fee18` match actual `wrap` results; for unknown/disabled underlyings, returns `(0,0)`.
  - `previewUnwrap`: Similarly checks `released18` and `fee18`; returns `(0,0)` for unknown/disabled underlyings.
  - `sharesOf` / `totalShares`: After multi‑account wrap/transfer/unwrap flows, verifies that the sum of per‑account `sharesOf` equals `totalShares`.
  - `underlyingInfo`: Verifies `enabled/decimals/liquidity` correctness under enable/disable, different `feeMode` settings and `applySplit` effects.
  - `isUnderlyingEnabled` / `listUnderlyings`: On adding/disabling underlyings, the list and enable flags should be updated consistently.

- **governance setter coverage**
  - `setCompliance`: Only `OPERATOR_ROLE` may call; setting to the existing value must revert with `NoChange`.
  - `setTreasury`: Only `OPERATOR_ROLE` may call; when `wrapFeeBps/unwrapFeeBps > 0`, setting `treasury` to zero must revert `FeeTreasuryRequired`; setting the same address should revert `NoChange`.
  - `setWrapFeeBps` / `setUnwrapFeeBps`: Only `OPERATOR_ROLE`; when setting non‑zero fees with `treasury == 0`, must revert `FeeTreasuryRequired`; setting the same value should revert `NoChange`.
  - `setMinInitialDeposit`: Only `OPERATOR_ROLE`; setting the same value should revert `NoChange`; different min values must interact correctly with first‑wrap behavior (too small vs. large enough).
  - `setTermsURI`: Only `OPERATOR_ROLE`; setting the same string should revert `NoChange`.

- **factory‑level control**
  - `setPausedByFactory`: Calls from `factoryRegistry` or `PAUSER_ROLE` must succeed; other addresses must revert `NotAllowed`; together with `pause()/setPausedByFactory` the `whenOperational` modifier should behave correctly.

- **extreme/boundary amounts**
  - `wrap/unwrap` with extremely small amounts (triggering `TooSmall`), very large amounts (near the upper bound), and behavior near `cap`, ensuring no arithmetic overflows and correct error types.
  - `test_Unwrap_AllLiquidity_Success_NoDust` (suggested): Build a single‑underlying pool, have a user wrap and then unwrap all their personal liquidity; verify:
    - The user’s `shares` and wrapper balance are fully zeroed;
    - The wrapper’s balance for that underlying is zero or only a minimal remainder due to precision;
    - `totalShares` and pool valuation are consistent with full redemption of that user’s share.
  - `test_MultiUnderlying_FeeMode0And1_WrapUnwrap_SharesProRata` (suggested): Build a wrapper with two underlyings where:
    - Underlying A uses `feeMode=0`, underlying B uses `feeMode=1`;
    - Multiple users wrap/unwrap the two underlyings in different proportions;
    - Verify that shares are always allocated and redeemed pro‑rata to total pool value and no share mismatch occurs between underlyings with different `feeMode`.
  - `test_MultiUser_WrapUnwrap_And_SharesConservation` (suggested): With three users that wrap, transfer and unwrap over time, verify:
    - At any time, the sum of `sharesOf` equals `totalShares`;
    - Each wrap/unwrap changes a user’s shares in proportion to their marginal contribution to or withdrawal from the total pool.


