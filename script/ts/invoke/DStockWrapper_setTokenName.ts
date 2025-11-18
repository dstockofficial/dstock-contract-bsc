/**
 * DStockWrapper_setTokenName.ts
 * -----------------------------
 * Calls `setTokenName(newName)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_setTokenName.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = ["function setTokenName(string newName)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const newName = requireEnv("TOKEN_NAME_NEW");

  console.log("=== DStockWrapper.setTokenName ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("New name:", newName);

  const tx = await wrapper.setTokenName(newName);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

