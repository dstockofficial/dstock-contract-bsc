/**
 * DStockWrapper_unpause.ts
 * ------------------------
 * Calls `unpause()`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_unpause.ts
 */

import { getProvider, getWallet, getContract } from "./utils.ts";

const WRAPPER_ABI = ["function unpause()"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);

  console.log("=== DStockWrapper.unpause ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);

  const tx = await wrapper.unpause();
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

