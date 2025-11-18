/**
 * DStockWrapper_symbol.ts
 * -----------------------
 * Reads ERC20 `symbol()`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_symbol.ts
 */

import { getProvider, getContract } from "./utils.ts";

const WRAPPER_ABI = ["function symbol() view returns (string)"];

async function main() {
  const provider = getProvider();
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, provider);
  const symbol = await wrapper.symbol();

  console.log("=== DStockWrapper.symbol ===");
  console.log("Wrapper:", wrapper.target);
  console.log("Symbol :", symbol);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

