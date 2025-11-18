/**
 * DStockWrapper_harvestAll.ts
 * ---------------------------
 * Calls `harvestAll()`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_harvestAll.ts
 */

import { getProvider, getWallet, getContract } from "./utils.ts";

const WRAPPER_ABI = ["function harvestAll()"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);

  console.log("=== DStockWrapper.harvestAll ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);

  const tx = await wrapper.harvestAll();
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

