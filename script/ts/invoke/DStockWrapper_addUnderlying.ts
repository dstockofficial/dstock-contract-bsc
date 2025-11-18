/**
 * DStockWrapper_addUnderlying.ts
 * ------------------------------
 * Calls `addUnderlying(token)` (factory/operator only).
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_addUnderlying.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = ["function addUnderlying(address token)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const token = requireEnv("UNDERLYING_TO_ADD");

  console.log("=== DStockWrapper.addUnderlying ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("Token   :", token);

  const tx = await wrapper.addUnderlying(token);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

