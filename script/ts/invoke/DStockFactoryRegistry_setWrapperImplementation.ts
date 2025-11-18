/**
 * DStockFactoryRegistry_setWrapperImplementation.ts
 * -------------------------------------------------
 * Calls `setWrapperImplementation(newImplementation)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockFactoryRegistry_setWrapperImplementation.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const FACTORY_ABI = ["function setWrapperImplementation(address newImplementation)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const factory = getContract("FACTORY", FACTORY_ABI, wallet);
  const impl = requireEnv("WRAPPER_IMPL_NEW");

  console.log("=== DStockFactoryRegistry.setWrapperImplementation ===");
  console.log("Factory :", factory.target);
  console.log("Operator:", wallet.address);
  console.log("New impl:", impl);

  const tx = await factory.setWrapperImplementation(impl);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

