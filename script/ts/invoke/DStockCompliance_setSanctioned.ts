/**
 * DStockCompliance_setSanctioned.ts
 * ---------------------------------
 * Sets `sanctioned[target] = value`.
 *
 * Run:
 *   npx ts-node script/ts/DStockCompliance_setSanctioned.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const COMPLIANCE_ABI = ["function setSanctioned(address user, bool bad)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const compliance = getContract("COMPLIANCE", COMPLIANCE_ABI, wallet);
  const target = requireEnv("TARGET");
  const value = requireEnv("VALUE").toLowerCase() === "true";

  console.log("=== DStockCompliance.setSanctioned ===");
  console.log("Operator:", wallet.address);
  console.log("Target  :", target);
  console.log("Value   :", value);

  const tx = await compliance.setSanctioned(target, value);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

