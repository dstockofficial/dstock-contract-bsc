/**
 * DStockCompliance_clearFlagsForToken.ts
 * --------------------------------------
 * Calls `clearFlagsForToken(token)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockCompliance_clearFlagsForToken.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const COMPLIANCE_ABI = ["function clearFlagsForToken(address token)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const compliance = getContract("COMPLIANCE", COMPLIANCE_ABI, wallet);
  const token = requireEnv("FLAGS_WRAPPER");

  console.log("=== DStockCompliance.clearFlagsForToken ===");
  console.log("Compliance:", compliance.target);
  console.log("Operator  :", wallet.address);
  console.log("Token     :", token);

  const tx = await compliance.clearFlagsForToken(token);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

