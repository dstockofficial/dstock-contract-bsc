/**
 * DStockFactoryRegistry_getWrappers.ts
 * ------------------------------------
 * Lists all wrappers that include a specific UNDERLYING token.
 *
 * Run:
 *   npx ts-node script/ts/DStockFactoryRegistry_getWrappers.ts
 */

import { getProvider, getContract, requireEnv } from "./utils.ts";

const FACTORY_ABI = [
  "function getWrappers(address underlying) view returns (address[])",
];

async function main() {
  const provider = getProvider();
  const factory = getContract("FACTORY", FACTORY_ABI, provider);
  const underlying = requireEnv("UNDERLYING");
  const wrappers = await factory.getWrappers(underlying);

  console.log("=== DStockFactoryRegistry.getWrappers ===");
  console.log("Factory   :", factory.target);
  console.log("Underlying:", underlying);
  wrappers.forEach((addr: string, idx: number) => {
    console.log(`#${idx}: ${addr}`);
  });
  if (wrappers.length === 0) console.log("(no wrappers mapped)");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

