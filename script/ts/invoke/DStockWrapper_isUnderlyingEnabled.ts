/**
 * DStockWrapper_isUnderlyingEnabled.ts
 * ------------------------------------
 * Calls `isUnderlyingEnabled(token)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_isUnderlyingEnabled.ts
 */

import { getProvider, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = ["function isUnderlyingEnabled(address token) view returns (bool)"];

async function main() {
  const provider = getProvider();
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, provider);
  const token = requireEnv("UNDERLYING");
  const enabled = await wrapper.isUnderlyingEnabled(token);

  console.log("=== DStockWrapper.isUnderlyingEnabled ===");
  console.log("Wrapper  :", wrapper.target);
  console.log("Underlying:", token);
  console.log("Enabled  :", enabled);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

