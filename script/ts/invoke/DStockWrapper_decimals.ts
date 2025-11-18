/**
 * DStockWrapper_decimals.ts
 * -------------------------
 * Reads ERC20 `decimals()`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_decimals.ts
 */

import { getProvider, getContract } from "./utils.ts";

const WRAPPER_ABI = ["function decimals() view returns (uint8)"];

async function main() {
  const provider = getProvider();
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, provider);
  const decimals = await wrapper.decimals();

  console.log("=== DStockWrapper.decimals ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Decimals:", decimals.toString());
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

