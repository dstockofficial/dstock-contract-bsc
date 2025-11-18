/**
 * DStockWrapper_setWrapFeeBps.ts
 * ------------------------------
 * Calls `setWrapFeeBps(newBps)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_setWrapFeeBps.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = ["function setWrapFeeBps(uint16 bps)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const bps = Number(requireEnv("WRAP_FEE_BPS_NEW"));

  console.log("=== DStockWrapper.setWrapFeeBps ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("New bps :", bps);

  const tx = await wrapper.setWrapFeeBps(bps);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

