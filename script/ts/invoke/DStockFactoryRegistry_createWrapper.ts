/**
 * DStockFactoryRegistry_createWrapper.ts
 * --------------------------------------
 * Calls `createWrapper(initParams)` via the factory.
 *
 * Provide a JSON file describing `IDStockWrapper.InitParams` and set
 * `WRAPPER_INIT_FILE=/path/to/file.json`.
 *
 * Run:
 *   npx ts-node script/ts/DStockFactoryRegistry_createWrapper.ts
 */

import fs from "fs";
import path from "path";
import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const FACTORY_ABI = [
  "function createWrapper((address,address,address[],string,string,uint8,address,address,uint16,uint16,uint256,string,uint256,uint256,uint32,uint8) p) returns (address)",
];

function loadInitParams(filePath: string) {
  const full = path.resolve(process.cwd(), filePath);
  const raw = fs.readFileSync(full, "utf8");
  return JSON.parse(raw);
}

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const factory = getContract("FACTORY", FACTORY_ABI, wallet);
  const params = loadInitParams(requireEnv("WRAPPER_INIT_FILE"));

  console.log("=== DStockFactoryRegistry.createWrapper ===");
  console.log("Factory :", factory.target);
  console.log("Operator:", wallet.address);
  console.log("Params  :", params);

  const tx = await factory.createWrapper(params);
  console.log("Tx sent :", tx.hash);
  const receipt = await tx.wait();
  console.log("Tx confirmed.");
  const newWrapper = receipt.logs?.find?.(() => false);
  if (receipt?.logs?.length) {
    console.log("Check factory events for emitted wrapper address.");
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

