/**
 * DStockFactoryRegistry_setGlobalCompliance.ts
 * -------------------------------------------
 * Calls `setGlobalCompliance(newCompliance)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockFactoryRegistry_setGlobalCompliance.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const FACTORY_ABI = ["function setGlobalCompliance(address c)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const factory = getContract("FACTORY", FACTORY_ABI, wallet);
  const compliance = requireEnv("FACTORY_NEW_COMPLIANCE");

  console.log("=== DStockFactoryRegistry.setGlobalCompliance ===");
  console.log("Factory :", factory.target);
  console.log("Operator:", wallet.address);
  console.log("New comp:", compliance);

  const tx = await factory.setGlobalCompliance(compliance);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

