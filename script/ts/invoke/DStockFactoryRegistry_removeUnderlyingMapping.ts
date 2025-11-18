/**
 * DStockFactoryRegistry_removeUnderlyingMapping.ts
 * -----------------------------------------------
 * Calls `removeUnderlyingMappingForWrapper(wrapper, underlying)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockFactoryRegistry_removeUnderlyingMapping.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const FACTORY_ABI = [
  "function removeUnderlyingMappingForWrapper(address wrapper, address underlying)",
];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const factory = getContract("FACTORY", FACTORY_ABI, wallet);
  const wrapperTarget = requireEnv("TARGET_WRAPPER");
  const underlying = requireEnv("UNDERLYING_REMOVE");

  console.log("=== DStockFactoryRegistry.removeUnderlyingMappingForWrapper ===");
  console.log("Factory   :", factory.target);
  console.log("Operator  :", wallet.address);
  console.log("Wrapper   :", wrapperTarget);
  console.log("Underlying:", underlying);

  const tx = await factory.removeUnderlyingMappingForWrapper(wrapperTarget, underlying);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

