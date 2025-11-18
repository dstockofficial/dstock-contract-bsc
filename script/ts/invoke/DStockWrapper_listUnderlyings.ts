/**
 * DStockWrapper_listUnderlyings.ts
 * --------------------------------
 * Lists all underlying tokens registered with the wrapper.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_listUnderlyings.ts
 */

import { getProvider, getContract } from "./utils.ts";

const WRAPPER_ABI = [
  "function listUnderlyings() view returns (address[])",
];

async function main() {
  const provider = getProvider();
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, provider);
  const list = await wrapper.listUnderlyings();

  console.log("=== DStockWrapper.listUnderlyings ===");
  console.log("Wrapper:", wrapper.target);
  list.forEach((addr: string, idx: number) => {
    console.log(`#${idx}: ${addr}`);
  });
  if (list.length === 0) {
    console.log("(no underlyings registered)");
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

