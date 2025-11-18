/**
 * DStockFactoryRegistry_getAllWrappers.ts
 * ---------------------------------------
 * Reads paginated wrapper list via `getAllWrappers(offset, limit)`.
 *
 * Optional env: OFFSET (default 0), LIMIT (default 20)
 *
 * Run:
 *   npx ts-node script/ts/DStockFactoryRegistry_getAllWrappers.ts
 */

import { getProvider, getContract } from "./utils.ts";

const FACTORY_ABI = [
  "function getAllWrappers(uint256 offset, uint256 limit) view returns (address[])",
];

async function main() {
  const provider = getProvider();
  const factory = getContract("FACTORY", FACTORY_ABI, provider);
  const offset = BigInt(process.env.OFFSET || "0");
  const limit = BigInt(process.env.LIMIT || "20");
  const list = await factory.getAllWrappers(offset, limit);

  console.log("=== DStockFactoryRegistry.getAllWrappers ===");
  console.log("Factory:", factory.target);
  console.log(`Range  : [${offset}, ${offset + limit})`);
  list.forEach((addr: string, idx: number) => {
    console.log(`#${Number(offset) + idx}: ${addr}`);
  });
  if (list.length === 0) console.log("(no wrappers in range)");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

