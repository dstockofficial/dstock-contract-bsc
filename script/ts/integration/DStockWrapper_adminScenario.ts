/**
 * DStockWrapper_adminScenario.ts
 * ------------------------------
 * Integration flow:
 *   1. Capture current governance parameters (wrap/unwrap fee bps, cap, min initial deposit, wrap/unwrap pause state).
 *   2. Apply new values supplied via env (`ADMIN_SCENARIO_*` keys) to ensure setters work without restriction.
 *   3. Toggle wrap/unwrap pause, pause/unpause the wrapper to validate Pausable + custom guardrails.
 *   4. Restore the original governance configuration at the end.
 *
 * Run:
 *   npx ts-node --esm script/ts/integration/DStockWrapper_adminScenario.ts
 */

import { formatEther, parseUnits } from "ethers";
import {
  getProvider,
  getWallet,
  getContract,
  requireEnv,
  requireBool,
} from "../invoke/utils.ts";

const WRAPPER_ABI = [
  "function wrapFeeBps() view returns (uint16)",
  "function unwrapFeeBps() view returns (uint16)",
  "function cap() view returns (uint256)",
  "function minInitialDeposit18() view returns (uint256)",
  "function wrapUnwrapPaused() view returns (bool)",
  "function paused() view returns (bool)",
  "function setWrapFeeBps(uint16 bps)",
  "function setUnwrapFeeBps(uint16 bps)",
  "function setCap(uint256 newCap)",
  "function setMinInitialDeposit(uint256 newMin)",
  "function setWrapUnwrapPaused(bool p)",
  "function pause()",
  "function unpause()",
];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);

  const [
    oldWrapFee,
    oldUnwrapFee,
    oldCap,
    oldMin,
    oldWrapPause,
    oldPaused,
  ] = await Promise.all([
    wrapper.wrapFeeBps(),
    wrapper.unwrapFeeBps(),
    wrapper.cap(),
    wrapper.minInitialDeposit18(),
    wrapper.wrapUnwrapPaused(),
    wrapper.paused(),
  ]);

  // Derive new values that are guaranteed to differ from the old ones to avoid NoChange()
  const newWrapFee = Number(oldWrapFee === 0n ? 1n : oldWrapFee - 1n);
  const newUnwrapFee = Number(oldUnwrapFee === 0n ? 1n : oldUnwrapFee - 1n);
  // cap / min are already 18-decimal uint256 on-chain; we can adjust them directly as BigInt
  const newCap = oldCap === 0n ? 1n : oldCap - 1n;
  const newMin = oldMin === 0n ? 1n : oldMin - 1n;
  const newWrapPause = !oldWrapPause;

  console.log("=== DStockWrapper admin scenario ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("\n-- Old config --");
  console.log("WrapFeeBps       :", oldWrapFee);
  console.log("UnwrapFeeBps     :", oldUnwrapFee);
  console.log("Cap (18)         :", formatEther(oldCap));
  console.log("MinInitialDeposit:", formatEther(oldMin));
  console.log("WrapUnwrapPaused :", oldWrapPause);
  console.log("Paused (OZ)      :", oldPaused);

  console.log("\n-- Applying new config --");
  await wrapper.setWrapFeeBps(newWrapFee);
  await wrapper.setUnwrapFeeBps(newUnwrapFee);
  await wrapper.setCap(newCap);
  await wrapper.setMinInitialDeposit(newMin);
  await wrapper.setWrapUnwrapPaused(newWrapPause);
  console.log("Applied governance changes.");

  console.log("Pausing via Pausable...");
  if (oldPaused) {
    await wrapper.unpause();
  } else {
    await wrapper.pause();
  }

  console.log("\n-- Restoring original config --");
  await wrapper.setWrapFeeBps(Number(oldWrapFee));
  await wrapper.setUnwrapFeeBps(Number(oldUnwrapFee));
  await wrapper.setCap(oldCap);
  await wrapper.setMinInitialDeposit(oldMin);
  await wrapper.setWrapUnwrapPaused(oldWrapPause);
  if (oldPaused) {
    await wrapper.pause();
    console.log("Returned to paused state (per original config).");
  } else {
    await wrapper.unpause();
    console.log("Returned to unpaused state (per original config).");
  }

  console.log("Admin scenario completed successfully.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

