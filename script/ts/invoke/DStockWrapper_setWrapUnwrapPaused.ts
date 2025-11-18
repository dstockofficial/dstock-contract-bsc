/**
 * DStockWrapper_setWrapUnwrapPaused.ts
 * ------------------------------------
 * Calls `setWrapUnwrapPaused(paused)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_setWrapUnwrapPaused.ts
 */

import { getProvider, getWallet, getContract, requireBool } from "./utils.ts";

const WRAPPER_ABI = ["function setWrapUnwrapPaused(bool p)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const paused = requireBool("WRAP_UNWRAP_PAUSED");

  console.log("=== DStockWrapper.setWrapUnwrapPaused ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("Paused  :", paused);

  const tx = await wrapper.setWrapUnwrapPaused(paused);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

