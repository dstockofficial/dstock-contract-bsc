/**
 * DStockWrapper_totalShares.ts
 * ----------------------------
 * Calls `totalShares()` and prints the raw share supply.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_totalShares.ts
 */

import { getProvider, getContract } from "./utils.ts";

const WRAPPER_ABI = ["function totalShares() view returns (uint256)"];

async function main() {
  const provider = getProvider();
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, provider);
  const total = await wrapper.totalShares();

  console.log("=== DStockWrapper.totalShares ===");
  console.log("Wrapper     :", wrapper.target);
  console.log("TotalShares :", total.toString());
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

