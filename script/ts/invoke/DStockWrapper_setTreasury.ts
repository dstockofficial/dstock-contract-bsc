/**
 * DStockWrapper_setTreasury.ts
 * ----------------------------
 * Calls `setTreasury(newTreasury)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_setTreasury.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = ["function setTreasury(address t)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const newTreasury = requireEnv("NEW_TREASURY");

  console.log("=== DStockWrapper.setTreasury ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("Treasury:", newTreasury);

  const tx = await wrapper.setTreasury(newTreasury);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

