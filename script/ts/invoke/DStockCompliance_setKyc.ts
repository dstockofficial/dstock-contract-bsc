/**
 * DStockCompliance_setKyc.ts
 * --------------------------
 * Sets `kyc[target] = value`.
 *
 * Required env:
 *   - COMPLIANCE
 *   - TARGET
 *   - VALUE (true/false)
 *
 * Run:
 *   npx ts-node script/ts/DStockCompliance_setKyc.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const COMPLIANCE_ABI = ["function setKyc(address user, bool ok)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const compliance = getContract("COMPLIANCE", COMPLIANCE_ABI, wallet);
  const target = requireEnv("TARGET");
  const value = requireEnv("VALUE").toLowerCase() === "true";

  console.log("=== DStockCompliance.setKyc ===");
  console.log("Operator:", wallet.address);
  console.log("Target  :", target);
  console.log("Value   :", value);

  const tx = await compliance.setKyc(target, value);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

