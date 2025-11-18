/**
 * DStockWrapper_setUnderlyingEnabled.ts
 * -------------------------------------
 * Calls `setUnderlyingEnabled(token, enabled)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_setUnderlyingEnabled.ts
 */

import { getProvider, getWallet, getContract, requireBool, requireEnv } from "./utils.ts";

const WRAPPER_ABI = ["function setUnderlyingEnabled(address token, bool enabled)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const token = requireEnv("UNDERLYING_TOGGLE");
  const enabled = requireBool("UNDERLYING_ENABLED");

  console.log("=== DStockWrapper.setUnderlyingEnabled ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("Token   :", token);
  console.log("Enabled :", enabled);

  const tx = await wrapper.setUnderlyingEnabled(token, enabled);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

