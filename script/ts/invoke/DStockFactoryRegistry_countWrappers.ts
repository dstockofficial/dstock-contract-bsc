/**
 * DStockFactoryRegistry_countWrappers.ts
 * --------------------------------------
 * Calls `countWrappers()` on the factory.
 *
 * Run:
 *   npx ts-node script/ts/DStockFactoryRegistry_countWrappers.ts
 */

import { getProvider, getContract } from "./utils.ts";

const FACTORY_ABI = ["function countWrappers() view returns (uint256)"];

async function main() {
  const provider = getProvider();
  const factory = getContract("FACTORY", FACTORY_ABI, provider);
  const count = await factory.countWrappers();

  console.log("=== DStockFactoryRegistry.countWrappers ===");
  console.log("Factory:", factory.target);
  console.log("Count  :", count.toString());
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

