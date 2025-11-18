/**
 * DStockWrapper_setCompliance.ts
 * ------------------------------
 * Calls `setCompliance(newAddress)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_setCompliance.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = ["function setCompliance(address c)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const newCompliance = requireEnv("NEW_COMPLIANCE");

  console.log("=== DStockWrapper.setCompliance ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("New comp:", newCompliance);

  const tx = await wrapper.setCompliance(newCompliance);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

