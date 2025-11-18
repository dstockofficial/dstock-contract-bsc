/**
 * DStockCompliance_setCustody.ts
 * ------------------------------
 * Sets `custody[target] = value`.
 *
 * Run:
 *   npx ts-node script/ts/DStockCompliance_setCustody.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const COMPLIANCE_ABI = ["function setCustody(address user, bool ok)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const compliance = getContract("COMPLIANCE", COMPLIANCE_ABI, wallet);
  const target = requireEnv("TARGET");
  const value = requireEnv("VALUE").toLowerCase() === "true";

  console.log("=== DStockCompliance.setCustody ===");
  console.log("Operator:", wallet.address);
  console.log("Target  :", target);
  console.log("Value   :", value);

  const tx = await compliance.setCustody(target, value);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

