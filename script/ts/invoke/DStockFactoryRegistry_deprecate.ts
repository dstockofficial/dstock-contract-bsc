/**
 * DStockFactoryRegistry_deprecate.ts
 * ----------------------------------
 * Calls `deprecate(wrapper, reason)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockFactoryRegistry_deprecate.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const FACTORY_ABI = ["function deprecate(address wrapper, string reason)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const factory = getContract("FACTORY", FACTORY_ABI, wallet);
  const wrapperTarget = requireEnv("TARGET_WRAPPER");
  const reason = requireEnv("DEPRECATE_REASON");

  console.log("=== DStockFactoryRegistry.deprecate ===");
  console.log("Factory :", factory.target);
  console.log("Operator:", wallet.address);
  console.log("Wrapper :", wrapperTarget);
  console.log("Reason  :", reason);

  const tx = await factory.deprecate(wrapperTarget, reason);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

