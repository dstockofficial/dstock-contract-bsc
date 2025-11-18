/**
 * DStockFactoryRegistry_getWrapper.ts
 * -----------------------------------
 * Calls `getWrapper(underlying)` (legacy single-wrapper getter).
 *
 * Run:
 *   npx ts-node script/ts/DStockFactoryRegistry_getWrapper.ts
 */

import { getProvider, getContract, requireEnv } from "./utils.ts";

const FACTORY_ABI = ["function getWrapper(address underlying) view returns (address)"];

async function main() {
  const provider = getProvider();
  const factory = getContract("FACTORY", FACTORY_ABI, provider);
  const underlying = requireEnv("UNDERLYING");
  const wrapper = await factory.getWrapper(underlying);

  console.log("=== DStockFactoryRegistry.getWrapper ===");
  console.log("Factory   :", factory.target);
  console.log("Underlying:", underlying);
  console.log("Wrapper   :", wrapper);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

