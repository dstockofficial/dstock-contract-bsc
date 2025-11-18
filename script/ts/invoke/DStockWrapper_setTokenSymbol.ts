/**
 * DStockWrapper_setTokenSymbol.ts
 * -------------------------------
 * Calls `setTokenSymbol(newSymbol)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_setTokenSymbol.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = ["function setTokenSymbol(string newSymbol)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const newSymbol = requireEnv("TOKEN_SYMBOL_NEW");

  console.log("=== DStockWrapper.setTokenSymbol ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("New sym :", newSymbol);

  const tx = await wrapper.setTokenSymbol(newSymbol);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

