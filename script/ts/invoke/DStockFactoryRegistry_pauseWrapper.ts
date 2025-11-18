/**
 * DStockFactoryRegistry_pauseWrapper.ts
 * -------------------------------------
 * Calls `pauseWrapper(wrapper, paused)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockFactoryRegistry_pauseWrapper.ts
 */

import { getProvider, getWallet, getContract, requireBool, requireEnv } from "./utils.ts";

const FACTORY_ABI = ["function pauseWrapper(address wrapper, bool paused)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const factory = getContract("FACTORY", FACTORY_ABI, wallet);
  const wrapperTarget = requireEnv("TARGET_WRAPPER");
  const paused = requireBool("TARGET_PAUSED");

  console.log("=== DStockFactoryRegistry.pauseWrapper ===");
  console.log("Factory :", factory.target);
  console.log("Operator:", wallet.address);
  console.log("Wrapper :", wrapperTarget);
  console.log("Paused  :", paused);

  const tx = await factory.pauseWrapper(wrapperTarget, paused);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

