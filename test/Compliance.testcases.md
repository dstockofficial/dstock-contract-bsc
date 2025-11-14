## `Compliance.t.sol` Test Cases

- **test_SetKyc_And_Events**: Verifies that toggling KYC status for an address via `setKyc` emits the correct events and updates the internal KYC mapping as expected.

- **test_SetLists_Unauthorized_Revert**: Calls to blacklist/whitelist (or equivalent) setters such as `setSanctioned`, `setWhitelisted`, etc., from unauthorized addresses must revert due to `onlyRole` checks.

- **test_SetFlags_Global_And_Token_Override**: Covers how global flags and per‑token flags combine:
  - Configure a global rule set;
  - Override rules for a specific token;
  - `isTransferAllowed` should prioritize token‑level rules when present.

- **test_SetFlags_Unauthorized_Revert**: Non‑operator calls to `setFlagsGlobal` / `setFlagsForToken` must be rejected, validating role‑based access control.

- **test_Transfer_Action_Requires_KYC_When_Restricted**: When `transferRestricted = true`, transfers involving non‑KYC addresses must be rejected while transfers with fully KYC’ed parties should be allowed.

- **test_Wrap_Action_FromKyc_And_ToCustody**: Under `kycOnWrap = true` and `wrapToCustodyOnly` (and similar flags), only `wrap` operations where the `from` address passes KYC and the `to` address is marked as custody should be allowed.

- **test_Unwrap_Action_FromKyc_And_FromCustody**: With `kycOnUnwrap = true` and/or `unwrapFromCustodyOnly`, verifies that only `unwrap` operations from KYC’ed/custody addresses succeed.

- **test_EnforceSanctions_Blocks_All_Actions**: When `enforceSanctions = true` and an address is on the sanctions list, all actions for that address (transfer / wrap / unwrap) must be rejected by `isTransferAllowed`.

- **test_ListManagement_Idempotent_And_SanctionsToggle**: Repeatedly updates KYC, custody and sanctions flags to confirm idempotent behavior and shows that turning sanctions on/off properly toggles whether a sanctioned address is blocked.
- **test_EnforceSanctions_ToggleEffect**: Explicitly disables and re‑enables `enforceSanctions` via `setFlagsGlobal`, verifying that the sanctions list is ignored when disabled and fully enforced when enabled.

- **test_FlagsMatrix_TransferRestricted_AffectsOnlyTransfer**: With `transferRestricted = true` and wrap/unwrap KYC disabled, demonstrates that only transfers require KYC↔KYC while wrap/unwrap remain unaffected, and that once both parties are KYC’ed, transfers succeed.
- **test_FlagsMatrix_KycOnWrapUnwrap_IndependentFromTransferRestriction**: With `kycOnWrap = kycOnUnwrap = true` and `transferRestricted = false`, shows that transfers stay unrestricted but wrap/unwrap require the `from` address to be KYC’ed.

- **test_IsTransferAllowed_UnknownAction_Rejected**: Calls `isTransferAllowed` with an unknown `action` code (such as `3`) and asserts that such actions are always rejected.

