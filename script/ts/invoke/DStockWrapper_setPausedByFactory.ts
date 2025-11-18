/**
 * DStockWrapper_setPausedByFactory.ts
 * -----------------------------------
 * Calls `setPausedByFactory(paused)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_setPausedByFactory.ts
 */

import { getProvider, getWallet, getContract, requireBool } from "./utils.ts";

const WRAPPER_ABI = ["function setPausedByFactory(bool p)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const paused = requireBool("PAUSED_BY_FACTORY");

  console.log("=== DStockWrapper.setPausedByFactory ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("Paused  :", paused);

  const tx = await wrapper.setPausedByFactory(paused);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

