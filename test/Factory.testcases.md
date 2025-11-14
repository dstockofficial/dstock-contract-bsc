## `Factory.t.sol` Test Cases

- **test_CreateWrapper_MultiUnderlyings_Authorized**: An `OPERATOR_ROLE` address can create a wrapper with multiple initial underlyings; verifies `wrappersOf` mappings, `listUnderlyings`, and wrapper count/state.
- **test_CreateWrapper_Unauthorized_Revert**: A caller without `OPERATOR_ROLE` invoking `createWrapper` must be rejected, validating factory access control.
- **test_CreateWrapper_DuplicateUnderlying_AllowsMultiple**: Allows the same underlying asset to be wrapped by multiple wrappers; verifies that `getWrappers` returns multiple wrappers and `getWrapper` returns the first in the list for backward compatibility.

- **test_GetWrappers_MultipleAndFirstCompat**: When the same underlying maps to multiple wrappers, `getWrappers` returns the full list and `getWrapper` returns the first wrapper.

- **test_SetUnderlyingStatusForWrapper_AffectsTargetOnly**: With two wrappers sharing the same underlying, calling `setUnderlyingStatusForWrapper` on one should only affect that wrapper’s enable status.

- **test_RemoveUnderlyingMappingForWrapper_OnlyRemovesOne**: Calling `removeUnderlyingMappingForWrapper` must remove the mapping for only the target wrapper and disable the underlying on that wrapper; other wrappers remain mapped and enabled.

- **test_AddUnderlyings_NoDuplicateMapping**: Repeatedly calling `addUnderlyings` with the same token for the same wrapper must not create duplicate mappings; `wrappersOf` should contain the wrapper only once.

- **test_Deprecate_MarksFlag**: After calling `deprecate`, `deprecated[wrapper]` should be set to `true` and `deprecateReason` should store the provided reason string.

- **test_SetUnderlyingStatusForWrapper_NotRegistered_Revert**: Calling `setUnderlyingStatusForWrapper` for an unregistered `(wrapper, underlying)` pair must revert with `NotRegistered`.

- **test_GrantRevoke_Role_Effect**: After revoking `OPERATOR_ROLE`, `createWrapper` calls must fail; after re‑granting the role, `createWrapper` should succeed again.

- **test_SetWrapperImplementation_Authorized**: A `DEFAULT_ADMIN_ROLE` address can call `setWrapperImplementation` to upgrade the Beacon implementation; the `WrapperImplementationUpgraded` event should be emitted as expected.
- **test_SetWrapperImplementation_Unauthorized_Revert**: A non‑admin calling `setWrapperImplementation` should revert due to `onlyRole` checks.

- **test_PauseWrapper_ByFactory_Authorized**: A `PAUSER_ROLE` address can call `pauseWrapper`, which must call the wrapper’s `setPausedByFactory` to pause and then unpause; the `WrapperPausedByFactory` event must be emitted correctly.
- **test_PauseWrapper_Unauthorized_Revert**: A caller without `PAUSER_ROLE` trying to call `pauseWrapper` must revert.
- **test_PauseWrapper_NotRegistered_Revert**: Calling `pauseWrapper` on an address that is not a registered wrapper should revert with `NotRegistered`.

- **global compliance module**
  - `setGlobalCompliance`:
    - Setting to a new address should update `globalCompliance` and emit `GlobalComplianceChanged`.
    - Setting to the current address should revert with `SameAddress`.

- **pagination**
  - `getAllWrappers(offset, limit)`:
    - With multiple wrappers, various `offset/limit` combinations should return the correct length and order slices.
    - When `offset >= countWrappers()`, the function must return an empty array.
    - When `limit` exceeds the remaining number of items, the result should be truncated to the remaining count.

- **edge cases and error paths**
  - `addUnderlyings`:
    - Calling it on a wrapper that is marked `deprecated` must revert (cannot add new underlyings to a deprecated wrapper).
    - Passing an empty `tokens` array must revert with `"empty tokens"` via `InvalidParams`.
  - `removeUnderlyingMappingForWrapper`:
    - Calling with an `(wrapper, underlying)` pair that is not mapped must revert `NotRegistered`.
  - `createWrapper`:
    - If `initialUnderlyings` contains the zero address, the call must revert `ZeroAddress`.
    - The caller‑provided `factoryRegistry` field must be ignored and overwritten by the factory’s own address, ensuring consistent registry behavior.


