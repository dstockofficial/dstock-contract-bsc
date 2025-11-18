## Deployment & Scripting Guide

This repository exposes all Foundry scripts under `script/`. The most common tasks are:

1. **Deploying compliance + wrapper implementation + factory in one shot**  
   ```bash
    forge script script/DeployAll.s.sol:DeployAll \
    --rpc-url "$BSC_TESTNET_RPC" \
    --chain-id 97 \
    --legacy \
    --broadcast -vvvv
   ```
2. **Creating additional wrappers via an existing factory**  
   ```bash
   forge script script/CreateWrapper.s.sol:CreateWrapper \
     --rpc-url "$BSC_TESTNET_RPC" \
     --chain-id 97 \
     --legacy \
     --broadcast -vvvv
   ```
   Requires `FACTORY`, `ADMIN`, `UNDERLYING_COUNT`, `UNDERLYING_i`, and the wrapper metadata/fee env vars.

3. **Preparing compliance and executing a wrap**  
   ```bash
   forge script script/PrepComplianceAndWrap.s.sol:PrepComplianceAndWrap \
     --rpc-url "$BSC_TESTNET_RPC" \
     --chain-id 97 \
     --legacy \
     --broadcast -vvvv
   ```
   Ensures KYC/custody according to the wrapper’s flags and performs a `wrap`.

4. **Standalone deployments (optional)**  
   ```bash
   forge script script/DeployCompliance.s.sol:DeployCompliance \
     --rpc-url "$BSC_TESTNET_RPC" \
     --chain-id 97 \
     --legacy \
     --broadcast -vvvv
   ```
   Deploys a new `DStockCompliance` and configures global flags.

   ```bash
   forge script script/DStockWrapper.s.sol:DStockWrapperScript \
     --rpc-url "$BSC_TESTNET_RPC" \
     --chain-id 97 \
     --legacy \
     --broadcast -vvvv
   ```
   Deploys a bare `DStockWrapper` implementation.

   ```bash
   forge script script/DeployFactory.s.sol:DeployFactory \
     --rpc-url "$BSC_TESTNET_RPC" \
     --chain-id 97 \
     --legacy \
     --broadcast -vvvv
   ```
   Deploys only `DStockFactoryRegistry` (requires existing compliance + wrapper implementation).

### TypeScript Contract Call Scripts

Node-based helpers live in `script/ts/invoke/`, one script per external/view function. Run them with `npx ts-node --esm script/ts/invoke/<file>.ts` (after `npm install`). Integration tests live under `script/ts/integration/`.

- **DStockWrapper** – coverage includes wrap/unwrap flows, integration smoke tests (`integration/DStockWrapper_testWrapFlow.ts`, `integration/DStockWrapper_testUnwrapFlow.ts`, `integration/DStockWrapper_adminScenario.ts`), every ERC20 view, pool accounting (`totalShares`, `isUnderlyingEnabled`, `underlyingInfo`), metadata reads, governance setters (`setCompliance`, `setTreasury`, fee caps, naming, pausing, etc.), underlying management (`addUnderlying`, `setUnderlyingEnabled`, rebase params, split), and ops utilities (`harvestAll`, `forceMoveToTreasury`, `setPausedByFactory`, `setWrapUnwrapPaused`).
- **Factory upgrades** – `integration/DStockFactory_upgradeWrapper.ts` validates beacon upgrades end-to-end.
- **Compliance upgrades** – `integration/DStockCompliance_upgradeScenario.ts` migrates flags + address states then repoints factory/wrapper to the new compliance.
- **DStockFactoryRegistry** – scripts exist for every external (createWrapper, upgrades, global compliance, pause/deprecate, add/remove underlyings, status toggles, and all view helpers).
- **DStockCompliance** – global/per-token flag management, batch/user KYC setters, sanction/custody toggles, `isTransferAllowed`, and flag inspection.

All scripts share `.env` variables loaded from the project root. Use `env.invoke.example.ts` for common invoke scripts and `env.integration.example.ts` for integration scenarios (merge both into your `.env` as needed).

### Required Environment Variables

Common variables:

| Variable | Description |
| --- | --- |
| `BSC_TESTNET_RPC/BSC_RPC` | RPC endpoint |
| `ADMIN` | Admin address (DEFAULT_ADMIN_ROLE / OPERATOR_ROLE / PAUSER_ROLE) |
| `ADMIN_PK` | Private key for `ADMIN` (hex string for Foundry, no `0x`) |
| `COMPLIANCE` | Optional existing compliance address (set to `0x0` to auto-deploy) |
| `WRAPPER_IMPL` | Optional existing wrapper implementation (set to `0x0` to auto-deploy) |
| `WRAPPER_COUNT` | Number of wrappers created by `DeployAll` |
| `UNDERLYING_COUNT_<i>` / `UNDERLYING_<i>_<j>` | Per-wrapper underlying tokens |
| `NAME_<i>`, `SYMBOL_<i>`, ... | Per-wrapper metadata and fee config |
| `FACTORY` | Factory address (for `CreateWrapper`) |
| `UNDERLYING_COUNT` / `UNDERLYING_i` | Underlyings for the single wrapper created by `CreateWrapper` |
| `WRAPPER`, `UNDERLYING`, `COMPLIANCE`, `PRIVATE_KEY`, `TO`, `AMOUNT` or `AMOUNT_WEI` | Required by `PrepComplianceAndWrap` |

### `.env.example`
