## `Wrapper_ForceMove.t.sol` Test Cases

- **test_ForceMoveToTreasury_Success**: When ALICE holds some shares, an `OPERATOR_ROLE` address calls `forceMoveToTreasury`; verifies that shares are moved from ALICE to `TREAS`, amounts are conserved, and both `ForceMovedToTreasury` and `Transfer` events are emitted as expected.
- **test_ForceMoveToTreasury_Revert_Unauthorized**: A caller without `OPERATOR_ROLE` calls `forceMoveToTreasury`; the call must revert due to access control.
- **test_ForceMoveToTreasury_Revert_ZeroTreasury**: After setting `treasury` to the zero address, calling `forceMoveToTreasury` must revert with `ZeroAddress`.
- **test_ForceMoveToTreasury_Revert_FromEqualsTreasury**: If `from == treasury` when calling `forceMoveToTreasury`, it must revert with `NotAllowed` to prevent self‑transfer.
- **test_ForceMoveToTreasury_Revert_ZeroAmount**: When `amount18` is 0, `forceMoveToTreasury` must revert with `TooSmall`.
- **test_ForceMoveToTreasury_Revert_InsufficientShares**: When the requested amount corresponds to more shares than ALICE actually holds, the call must revert with `InsufficientShares`.
- **test_ForceMoveToTreasury_AfterPoolRescale**: After calling `applySplit` to rescale the pool, running `forceMoveToTreasury` must still compute and move shares correctly even if the effective pool size (and underlying valuation) has changed.

- **interaction with pause / factory control**
  - When the wrapper is `pause`d or `setPausedByFactory(true)`:
    - Decide whether `forceMoveToTreasury` remains allowed as a governance/enforcement path;
    - Tests should assert the chosen behavior (either still allowed or explicitly blocked).

- **multi‑user scenarios**
  - With multiple holders, call `forceMoveToTreasury` against different addresses multiple times:
    - Verify the cumulative effect on each holder’s shares and `balanceOf`;
    - Ensure total shares and the aggregate wrapper balance remain conserved.


