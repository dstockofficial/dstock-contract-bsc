/**
 * DStockWrapper_initialize.ts
 * ---------------------------
 * Calls `initialize(InitParams)` on a wrapper proxy (only callable once).
 *
 * Provide `WRAPPER_INIT_FILE` pointing to a JSON file matching
 * `IDStockWrapper.InitParams`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_initialize.ts
 */

import fs from "fs";
import path from "path";
import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = [
  "function initialize((address,address,address[],string,string,uint8,address,address,uint16,uint16,uint256,string,uint256,uint256,uint32,uint8) p)",
];

function loadParams(filePath: string) {
  const full = path.resolve(process.cwd(), filePath);
  const raw = fs.readFileSync(full, "utf8");
  return JSON.parse(raw);
}

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const params = loadParams(requireEnv("WRAPPER_INIT_FILE"));

  console.log("=== DStockWrapper.initialize ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("Params  :", params);

  const tx = await wrapper.initialize(params);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

