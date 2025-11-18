/**
 * DStockWrapper_name.ts
 * ---------------------
 * Reads ERC20 `name()`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_name.ts
 */

import { getProvider, getContract } from "./utils.ts";

const WRAPPER_ABI = ["function name() view returns (string)"];

async function main() {
  const provider = getProvider();
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, provider);
  const name = await wrapper.name();

  console.log("=== DStockWrapper.name ===");
  console.log("Wrapper:", wrapper.target);
  console.log("Name   :", name);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

