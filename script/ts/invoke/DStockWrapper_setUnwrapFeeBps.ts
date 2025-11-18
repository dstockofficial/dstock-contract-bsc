/**
 * DStockWrapper_setUnwrapFeeBps.ts
 * --------------------------------
 * Calls `setUnwrapFeeBps(newBps)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_setUnwrapFeeBps.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = ["function setUnwrapFeeBps(uint16 bps)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const bps = Number(requireEnv("UNWRAP_FEE_BPS_NEW"));

  console.log("=== DStockWrapper.setUnwrapFeeBps ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("New bps :", bps);

  const tx = await wrapper.setUnwrapFeeBps(bps);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

