/**
 * DStockCompliance_batchSetKyc.ts
 * -------------------------------
 * Calls `batchSetKyc(users[], value)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockCompliance_batchSetKyc.ts
 */

import { getProvider, getWallet, getContract, parseAddressList, requireBool, requireEnv } from "./utils.ts";

const COMPLIANCE_ABI = ["function batchSetKyc(address[] users, bool ok)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const compliance = getContract("COMPLIANCE", COMPLIANCE_ABI, wallet);
  const users = parseAddressList(requireEnv("KYC_BATCH_ADDRESSES"));
  if (users.length === 0) {
    throw new Error("KYC_BATCH_ADDRESSES must contain at least one address");
  }
  const value = requireBool("KYC_BATCH_VALUE");

  console.log("=== DStockCompliance.batchSetKyc ===");
  console.log("Compliance:", compliance.target);
  console.log("Operator  :", wallet.address);
  console.log("Users     :", users);
  console.log("Value     :", value);

  const tx = await compliance.batchSetKyc(users, value);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

