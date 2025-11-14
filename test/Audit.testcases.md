## Overview of DStock Audit Test Cases

This document maps each **Question / Issue / Recommendation** from the audit report to:

- **Current status**: fixed and testable / fixed by refactor with old code removed (no direct test) / no longer applicable due to design changes.
- **Related contracts and functions**.
- **Existing or planned test cases** (in `Wrapper.t.sol`, `Factory.t.sol`, etc.).
- Where no direct test exists, a short explanation (for example, the code was removed or the point is purely design‑level).

> Note: Items marked as "code removed, cannot directly test the old bug" mean the relevant logic no longer exists in the current version; the audit concern was resolved by architectural refactoring rather than a single patch.

---

## Question Series

### Question‑1: Coordination Between Underlying Mapping Removal and Wrapper Disabling

- **Audit description**: The old `removeUnderlyingMapping()` only updated the factory mapping without calling `setUnderlyingEnabled(false)` in the Wrapper, so there was no on‑chain atomic coordination.
- **Current status**: **Fixed and testable.**  
  The old `removeUnderlyingMapping()` has been replaced by `removeUnderlyingMappingForWrapper(wrapper, underlying)` plus `setUnderlyingEnabled` on the Wrapper side, providing atomic coordination.
- **Related contracts & functions**:
  - `DStockFactoryRegistry.removeUnderlyingMappingForWrapper(address wrapper, address underlying)`
  - `DStockWrapper.setUnderlyingEnabled(address token, bool enabled)`
- **Test case**:
  - `Factory.t.sol::test_RemoveUnderlyingMappingForWrapper_OnlyRemovesOne`
- **Test intention summary**:
  - When `removeUnderlyingMappingForWrapper` is called:
    - The target `underlying` must be disabled on the corresponding `wrapper`;
    - In the registry, `wrappersOf[underlying]` must remove only the specified `wrapper`;
    - The `UnderlyingUnmapped` event is emitted and state remains consistent.

---

### Question‑2: Overall Design of DStockWrapper and User Incentives

- **Audit description**: The old design used a global `multiplier` to charge holding fees, so balances would only decay over time without any user yield; this raised questions about design and incentives.
- **Current status**: **Resolved via architectural redesign; old problematic code removed, cannot directly test old logic.**  
  The new design uses "real‑time pool valuation + per‑underlying fee/rebase parameters":
  - No more global `multiplier` or `liquidToken`;
  - Uses `UnderlyingInfo.feeMode/feePerPeriodRay/periodLength` plus `_settleAndSkim*` to charge and settle fees per underlying into `treasury`;
  - `feeMode = 1` supports self‑rebasing underlyings (e.g., TSLAx).
- **Related contracts & functions**:
  - `DStockWrapper._poolAvailable18()`
  - `DStockWrapper._underlyingEffective18(address token)`
  - `DStockWrapper._settleAndSkimUnderlying / _settleAndSkimAll`
  - `DStockWrapper.setUnderlyingRebaseParams`
  - `DStockWrapper.harvestAll`
- **Main related tests** (illustrate the new design rather than the old defect):
  - `Wrapper.t.sol::test_UnderlyingRebaseParams_And_HarvestAll`
  - `Wrapper.t.sol::test_SettleAndSkim_OnWrap_RemovesSurplusFirst`
  - `Wrapper.t.sol::test_SettleAndSkim_OnUnwrap_RemovesSurplusFirst`
  - `Wrapper.t.sol::test_UnderlyingFeeMode1_NoSkimOnHarvest`

---

### Question‑3: Handling Old Wrappers and Funds After `migrateUnderlyings()`

- **Audit description**: The old `DStockFactoryRegistry.migrateUnderlyings()` did batch mapping migration but did not specify how old wrappers and funds should be handled, and did not remove them from `allWrappers`.
- **Current status**: **Code removed, cannot directly test the old issue.**  
  The current version has removed `migrateUnderlyings()` and instead:
  - Supports mapping one underlying to multiple wrappers via `wrappersOf`;
  - Provides `deprecate(wrapper, reason)` as a deprecation marker (metadata only, no fund movement);
  - No longer migrates underlyings at the factory layer; migration of user positions is a manual off‑chain process (users unwrap old wrapper and wrap into a new one).
- **Related contracts & functions**:
  - `DStockFactoryRegistry.deprecate(address wrapper, string reason)`
  - `DStockFactoryRegistry.getWrappers(address underlying)`
- **Test case**:
  - `Factory.t.sol::test_Deprecate_MarksFlag`
- **Notes**:
  - Since `migrateUnderlyings` has been removed, the original question "how are old wrapper funds handled after migration" is no longer applicable; the new design (multiple wrappers + deprecation flag) addresses the lifecycle instead.

---

### Question‑4: Fractional Shares and Precision on Split/Reverse‑Split

- **Audit description**: Merging/splitting shares may produce fractional shares; the auditor asked whether there are off‑chain settlement mechanisms to avoid loss.
- **Current status**: **Resolved by refactor and design constraints; the old "global multiplier merge" code has been removed.**  
  In the current version:
  - There is no global share consolidation; instead, `applySplit(token, numerator, denominator)` only adjusts that underlying’s pool balance (moving surplus to/from `treasury`);
  - Shares remain 18‑decimals ERC‑20; fractional shares are represented directly by `balanceOf`;
  - Very small operations are rejected via `TooSmall`, avoiding scenarios where shares are burned but the effective gain is ≈0.
- **Related contracts & functions**:
  - `DStockWrapper.applySplit(address token, uint256 numerator, uint256 denominator)`
  - `DStockWrapper._toAmountView` / `totalSupply` / `balanceOf`
- **Test cases**:
  - `Wrapper.t.sol::test_ApplySplit_PerUnderlying_Authorized_And_Unauthorized`
  - `Wrapper.t.sol::test_Unwrap_TooSmall_WhenFeesConsumeAll`
  - `Wrapper.t.sol::test_View_SharesOf_And_TotalShares_AfterTransfersAndUnwrap`

---

## Issue Series

### Issue‑1: Pause Mechanism (`pausedByFactory` and OZ Pausable Integration)

- **Audit description**: The old `whenNotPaused` only checked the OZ pause flag and ignored `pausedByFactory`, making the factory‑level pause ineffective.
- **Current status**: **Fixed and testable.**  
  The code now uses a unified `whenOperational` modifier that checks both `paused()` and `pausedByFactory`.
- **Related contracts & functions**:
  - `DStockWrapper.whenOperational` (modifier)
  - `DStockWrapper.wrap/unwrap/_update`
  - `DStockWrapper.setPausedByFactory`
  - `DStockFactoryRegistry.pauseWrapper`
- **Test cases**:
  - `Wrapper.t.sol::test_Wrap_Fail_Paused`
  - `Wrapper.t.sol::test_SetPausedByFactory_OnlyFactoryOrPauser_And_WhenOperational`
  - `Factory.t.sol::test_PauseWrapper_ByFactory_Authorized`

---

### Issue‑2: Incompatibility with Rebase Tokens in Accounting

- **Audit description**: The old design tracked liquidity via `liquidToken`; with rebase tokens (positive/negative rebasing), accounting could diverge, leading to DoS or stuck funds.
- **Current status**: **Resolved via refactor; old `liquidToken`‑based code removed, cannot directly reproduce the old bug.**  
  The new design uses real‑time pool valuation plus per‑underlying `feeMode` and provides `feeMode = 1` for self‑rebasing assets.
- **Related contracts & functions**:
  - `DStockWrapper.UnderlyingInfo` (`feeMode/feePerPeriodRay/periodLength`)
  - `DStockWrapper._underlyingEffective18`
  - `DStockWrapper._previewUnderlyingMultiplierView`
- **Existing/suggested tests**:
  - Existing: `Wrapper.t.sol::test_UnderlyingFeeMode1_NoSkimOnHarvest`
  - Suggested: dedicated rebase scenarios (implemented via `MockRebaseERC20` in `Wrapper.t.sol`):
    - Scenario A: Wrap, then perform a positive rebase (increase balances), then `unwrap`; verify there is no lockup or mis‑accounting from legacy `liquidToken` logic (now everything should be based on real‑time balances + fees).
    - Scenario B: Wrap, then perform a negative rebase (decrease balances), then attempt an overly large `unwrap`; verify it correctly hits `InsufficientLiquidity` instead of inconsistent accounting or weird behavior.

---

### Issue‑3: `applySplit()` Not Updating Liquidity Leading to Lockups

- **Audit description**: The old implementation adjusted the multiplier but did not update `liquidToken`, causing redeemable shares and bookkeeping to diverge.
- **Current status**: **Resolved via refactor; old `liquidToken` / global multiplier code removed.**  
  The current version no longer maintains a separate liquidity variable; it relies directly on actual underlying token balances, and `applySplit` only moves tokens between the pool and `treasury`.
- **Related contracts & functions**:
  - `DStockWrapper.applySplit`
- **Test case**:
  - `Wrapper.t.sol::test_ApplySplit_PerUnderlying_Authorized_And_Unauthorized`

---

### Issue‑4: Incorrect Accounting in `unwrap()` (Subtracting Only Net, Not Fee)

- **Audit description**: The old implementation subtracted only `netToken` from `liquidToken` while actually transferring `netToken + feeToken`.
- **Current status**: **Fixed and testable.**  
  The new implementation no longer uses `liquidToken` and instead:
  - Computes `feeToken` and `netToken`;
  - Computes `needOut = netToken + feeToken (if any)`;
  - Verifies `IERC20(token).balanceOf(this) >= needOut`.
- **Related contracts & functions**:
  - `DStockWrapper.unwrap`
- **Test cases**:
  - `Wrapper.t.sol::test_Unwrap_Success`
  - `Wrapper.t.sol::test_Unwrap_TooSmall_WhenFeesConsumeAll`

---

### Issue‑5: Potential DoS in `addUnderlyings()` / `migrateUnderlyings()`

- **Audit description**: In the old design, the factory had to call the Wrapper’s `addUnderlying()` which required `OPERATOR_ROLE`; if that role was not granted, adding/migrating underlyings could fail (DoS).
- **Current status**: **Fixed and testable; old `migrateUnderlyings` removed.**  
  - On the Wrapper side, `addUnderlying` now restricts `msg.sender == factoryRegistry`;
  - The factory is solely responsible for adding and enabling/disabling underlyings; `migrateUnderlyings` is no longer provided.
- **Related contracts & functions**:
  - `DStockWrapper.addUnderlying(address token)` (factory‑only)
  - `DStockFactoryRegistry.addUnderlyings`
- **Test cases**:
  - `Wrapper.t.sol::test_AddUnderlying_Unauthorized_Fail_Then_WrapUnwrap_Fail`
  - `Factory.t.sol::test_AddUnderlyings_NoDuplicateMapping`

---

### Issue‑6: Inaccurate `totalSupply()` / `balanceOf()` Return Values

- **Audit description**: The old design relied on a stale multiplier that was not updated at read time, so observable `totalSupply`/`balanceOf` could diverge from actual state.
- **Current status**: **Fixed and testable.**  
  - The global multiplier was removed;
  - `totalSupply`/`balanceOf` now use `_toAmountView` to recompute against `_poolAvailable18()` on each read.
- **Related contracts & functions**:
  - `DStockWrapper.totalSupply`
  - `DStockWrapper.balanceOf`
  - `DStockWrapper._toAmountView`
- **Test case**:
  - `Wrapper.t.sol::test_View_SharesOf_And_TotalShares_AfterTransfersAndUnwrap`

---

### Issue‑7: Precision Loss in `unwrap()` Causing User Loss

- **Audit description**: In the old normalize/de‑normalize pipeline, it was possible that `feeToken + netToken < user input`; small operations could yield `netToken = 0` while still burning shares.
- **Current status**: **Fixed and testable.**  
  - The implementation now computes `feeToken`/`netToken` directly in the token’s native decimals;
  - If `netToken == 0`, it reverts with `TooSmall`, preventing "burn shares but get nothing" scenarios.
- **Related contracts & functions**:
  - `DStockWrapper.unwrap`
- **Test cases**:
  - `Wrapper.t.sol::test_Unwrap_TooSmall_WhenFeesConsumeAll`
  - Other normal `unwrap` tests (e.g. `test_Unwrap_Success`) ensure correct amount relationships in non‑edge cases.

---

### Issue‑8: Fees Stuck in Wrapper When Treasury Is Unset

- **Audit description**: In the old design, when `treasury == 0` and fees were configured, user fees were deducted but left inside the contract without any way to withdraw.
- **Current status**: **Fixed and testable.**  
  - `initialize`: if `wrapFeeBps/unwrapFeeBps > 0`, then `treasury` must be non‑zero;
  - `setTreasury` does not allow setting `treasury` to zero while any fee is non‑zero;
  - `setWrapFeeBps/setUnwrapFeeBps` do not allow setting non‑zero fees when `treasury == 0`.
- **Related contracts & functions**:
  - `DStockWrapper.initialize`
  - `DStockWrapper.setTreasury`
  - `DStockWrapper.setWrapFeeBps`
  - `DStockWrapper.setUnwrapFeeBps`
- **Test case**:
  - `Wrapper.t.sol::test_SetTreasury_WrapUnwrapFee_Guards`

---

### Issue‑9: Holding Fees Not Actually Withdrawable

- **Audit description**: The old design updated "book fees" via the multiplier but lacked an external function to actually move the corresponding underlying tokens out.
- **Current status**: **Resolved via refactor and testable.**  
  - `_settleAndSkimUnderlying/_settleAndSkimAll` compute notional surplus and send the extra tokens to `treasury`;
  - `harvestAll` is the explicit entrypoint called by `OPERATOR_ROLE`.
- **Related contracts & functions**:
  - `DStockWrapper._settleAndSkimUnderlying`
  - `DStockWrapper._settleAndSkimAll`
  - `DStockWrapper.harvestAll`
- **Test cases**:
  - `Wrapper.t.sol::test_UnderlyingRebaseParams_And_HarvestAll`
  - `Wrapper.t.sol::test_SettleAndSkim_OnWrap_RemovesSurplusFirst`
  - `Wrapper.t.sol::test_SettleAndSkim_OnUnwrap_RemovesSurplusFirst`
  - `Wrapper.t.sol::test_SetUnderlyingRebaseParams_HarvestsBeforeUpdate`

---

### Issue‑10: Cannot Re‑Add the Same Underlying After Removal or Migration

- **Audit description**: The factory only cleared the registry; `underlyings[token].decimals` in the Wrapper was not reset, so `_addUnderlying` treated the token as existing and refused re‑addition.
- **Current status**: **Fixed and testable.**  
  In the new design:
  - The Wrapper always keeps the `decimals` field and only toggles `enabled`;
  - In `addUnderlyings`, the factory checks via `underlyingInfo`:
    - If `tokenDecimals == 0`, it calls `addUnderlying` to add a new underlying;
    - If the token exists but is disabled, it calls `setUnderlyingEnabled(true)` to re‑enable.
- **Related contracts & functions**:
  - `DStockFactoryRegistry.addUnderlyings`
  - `DStockWrapper.underlyingInfo`
  - `DStockWrapper.addUnderlying`
  - `DStockWrapper.setUnderlyingEnabled`
- **Existing/suggested tests**:
  - Existing: `Factory.t.sol::test_AddUnderlyings_NoDuplicateMapping`
  - Existing: `Factory.t.sol::test_RemoveUnderlyingMappingForWrapper_OnlyRemovesOne` (helps understand disable flow)
  - Suggested full lifecycle test:
    - Create a wrapper, bind underlying U1, and perform a `wrap`;
    - Call `removeUnderlyingMappingForWrapper` to remove U1;
    - Call `addUnderlyings(wrapper, [U1])` to re‑add U1;
    - Finally wrap U1 again to confirm the "remove → re‑add → continue using" path works correctly.

---

### Issue‑11: Incorrect Liquidity Check in `unwrap()`

- **Audit description**: The old implementation only checked `info.liquidToken < netToken` and ignored the fee component, so the check could pass while the actual transfer failed.
- **Current status**: **Fixed and testable.**  
  - As described earlier, the new design checks `currentBal >= needOut` (which includes the fee), and no longer uses `liquidToken`.
- **Related contracts & functions**:
  - `DStockWrapper.unwrap`
- **Test cases**:
  - `Wrapper.t.sol::test_Unwrap_Success`
  - `Wrapper.t.sol::test_Unwrap_TooSmall_WhenFeesConsumeAll`

---

### Issue‑12: Bypassing Underlying Uniqueness Check

- **Audit description**: The old design enforced "one underlying → one wrapper", but any `OPERATOR_ROLE` could call `addUnderlying` directly on a Wrapper and bypass factory checks.
- **Current status**: **Design changed to allow multiple wrappers per underlying; the original "uniqueness" requirement is no longer applicable.**  
  - The factory manages multiple wrappers per underlying via `wrappersOf` / `getWrappers`;
  - The Wrapper’s `addUnderlying` is now factory‑only, preventing bypass of the registry;
  - The original audit concern (bypassing uniqueness) is moot under the new design.
- **Related contracts & functions**:
  - `DStockFactoryRegistry.createWrapper`
  - `DStockFactoryRegistry.getWrappers`
  - `DStockWrapper.addUnderlying`
- **Test cases**:
  - `Factory.t.sol::test_CreateWrapper_DuplicateUnderlying_AllowsMultiple`
  - `Factory.t.sol::test_GetWrappers_MultipleAndFirstCompat`
  - `Wrapper.t.sol::test_AddUnderlying_Unauthorized_Fail_Then_WrapUnwrap_Fail`

---

### Issue‑13: Missing Checks for Deprecated Wrappers

- **Audit description**: The old version allowed calling `migrateUnderlyings` or `addUnderlyings` on wrappers already marked as deprecated, which could corrupt state.
- **Current status**: **Fixed and testable; `migrateUnderlyings` removed.**  
  - `addUnderlyings` explicitly checks `if (deprecated[wrapper]) revert InvalidParams("deprecated wrapper");`;
  - Wrapper deprecation is fully managed by the factory.
- **Related contracts & functions**:
  - `DStockFactoryRegistry.deprecate`
  - `DStockFactoryRegistry.addUnderlyings`
- **Existing/suggested tests**:
  - Existing: `Factory.t.sol::test_Deprecate_MarksFlag`
  - Suggested 1: Call `addUnderlyings` on a deprecated wrapper and expect `InvalidParams("deprecated wrapper")`.
  - Suggested 2: Multi‑wrapper + deprecation scenario:
    - Map U1 to W1 and W2;
    - Call `deprecate(W1, "reason")`;
    - Verify `getWrappers(U1)` still returns [W1, W2] (historical record), but `addUnderlyings` for W1 fails while W2 remains fully functional.

---

## Summary of Suggested New Tests (for Planning)

> The following are suggested tests mentioned above, collected here for easier implementation and tracking:

- **Dedicated rebase‑token scenarios (Issue‑2)**  
  - In `Wrapper.t.sol`, add a Mock Rebase Token that supports manual positive/negative rebase for all balances;  
  - Scenario A: Wrap, positive rebase, then unwrap; verify there is no lockup or anomaly from legacy `liquidToken` logic.  
  - Scenario B: Wrap, negative rebase, then attempt an overly large unwrap; verify it correctly triggers `InsufficientLiquidity` without dirty accounting.

- **Full remove‑then‑re‑add underlying flow (Issue‑10)**  
  - Create a wrapper and bind U1, perform a `wrap`;  
  - Call `removeUnderlyingMappingForWrapper` to remove U1;  
  - Call `addUnderlyings(wrapper, [U1])` to re‑add;  
  - Finally wrap U1 again and confirm everything works normally.

- **Defense against `addUnderlyings` on deprecated wrappers (Issue‑13)**  
  - After calling `deprecate` on a wrapper, any `addUnderlyings` call must revert with `InvalidParams("deprecated wrapper")`.

- **Multi‑wrapper + deprecation scenario (Issue‑13 extension)**  
  - Map U1 to W1 and W2;  
  - Deprecate W1;  
  - `getWrappers(U1)` should still return both W1 & W2 to preserve history, but only W2 should accept new underlyings and operations.

---

## Recommendation Series

### Recommendation‑1: Rename Return Parameters of `underlyingInfo()`

- **Audit description**: The return parameter name `decimals` collides conceptually with the ERC‑20 `decimals()` function and may be confusing.
- **Current status**: **Adopted.**  
  - The current signature is `returns (bool isEnabled, uint8 tokenDecimals, uint256 liquidToken)`.
- **Related contracts & functions**:
  - `DStockWrapper.underlyingInfo`
- **Test case**:
  - `Wrapper.t.sol::test_View_UnderlyingInfo_And_IsUnderlyingEnabled_And_ListUnderlyings`

---

### Recommendation‑2: Remove Redundant Code (`totalDebt_`, UUPS, etc.)

- **Audit description**: There were unused internal functions, unreachable branches, and unnecessary UUPS inheritance.
- **Current status**: **Adopted; related code removed, cannot write tests for the old redundancy.**  
  - The current version no longer inherits from `UUPSUpgradeable`;  
  - `totalDebt_` and other unused functions/branches have been removed.

---

### Recommendation‑3: Setter Functions Should Reject No‑Op Updates

- **Audit description**: Many setters did not check whether the new value equals the current value, which can cause redundant events and confusion for off‑chain listeners.
- **Current status**: **Adopted and testable.**  
  - Multiple setters now use `NoChange` or `SameAddress`‑style errors to guard against no‑op updates.
- **Related contracts & functions**:
  - `DStockWrapper.setCompliance`
  - `DStockWrapper.setTreasury`
  - `DStockWrapper.setWrapFeeBps`
  - `DStockWrapper.setUnwrapFeeBps`
  - `DStockWrapper.setMinInitialDeposit`
  - `DStockWrapper.setTermsURI`
  - `DStockFactoryRegistry.setGlobalCompliance`
- **Test cases**:
  - `Wrapper.t.sol::test_SetCompliance_OnlyOperator_And_NoChange`
  - `Wrapper.t.sol::test_SetTreasury_WrapUnwrapFee_Guards`
  - `Wrapper.t.sol::test_SetMinInitialDeposit_Guards_And_EffectOnFirstWrap`
  - `Wrapper.t.sol::test_SetTermsURI_OnlyOperator_And_NoChange`
  - `Factory.t.sol::test_SetWrapperImplementation_Authorized` / `test_SetWrapperImplementation_Unauthorized_Revert` (similar "no‑change" logic on the factory side)

---

### Recommendation‑4: Call `_disableInitializers()` in the Constructor

- **Audit description**: The constructor did not call `_disableInitializers()`, so there was a theoretical risk that the implementation contract itself could be initialized.
- **Current status**: **Adopted.**  
  - The `DStockWrapper` constructor now calls `_disableInitializers()`.
- **Test**:
  - This is mainly an initialization‑pattern best practice and is guaranteed by the OpenZeppelin template; there is no dedicated test case in the current suite.

---

## Note Series (Risk Notes, Not Bugs)

These are design/governance‑level risk notes, not specific defects. They do not map to direct tests but are recorded here for audit cross‑reference:

- **Note‑1: Centralization Risk**  
  - Multiple high‑privilege roles (`DEFAULT_ADMIN_ROLE`, `OPERATOR_ROLE`, `PAUSER_ROLE`, etc.) can modify fee parameters, underlying mappings, and pause status;  
  - In production deployments, multi‑sig, operational processes, or off‑chain governance should be used to mitigate single‑point‑of‑failure risk.

- **Note‑2: Underlying Value Equivalence Assumption**  
  - All underlyings within a given wrapper are assumed to be economically equivalent (same issuer, similar collateral profile, etc.); shares represent a proportional claim on the entire pool.  
  - This is an economic/asset‑selection assumption that cannot be fully verified by contract tests alone and must be enforced by asset management and risk processes.

- **Note‑3: Peg‑Out and "Bank Run" Risk**  
  - If an underlying de‑pegs or defaults, users may rush to redeem "better" assets first, causing pool imbalance or even a bank‑run‑like situation;  
  - The contract provides tools such as pause/disable underlyings, but the concrete response strategy must be handled by operations and risk management.


