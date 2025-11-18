/**
 * DStockFactoryRegistry_setUnderlyingStatus.ts
 * --------------------------------------------
 * Calls `setUnderlyingStatusForWrapper(wrapper, underlying, enabled)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockFactoryRegistry_setUnderlyingStatus.ts
 */

import { getProvider, getWallet, getContract, requireBool, requireEnv } from "./utils.ts";

const FACTORY_ABI = [
  "function setUnderlyingStatusForWrapper(address wrapper, address underlying, bool enabled)",
];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const factory = getContract("FACTORY", FACTORY_ABI, wallet);
  const wrapperTarget = requireEnv("TARGET_WRAPPER");
  const underlying = requireEnv("UNDERLYING_TOGGLE");
  const enabled = requireBool("UNDERLYING_ENABLED");

  console.log("=== DStockFactoryRegistry.setUnderlyingStatusForWrapper ===");
  console.log("Factory   :", factory.target);
  console.log("Operator  :", wallet.address);
 	console.log("Wrapper   :", wrapperTarget);
  console.log("Underlying:", underlying);
  console.log("Enabled   :", enabled);

  const tx = await factory.setUnderlyingStatusForWrapper(wrapperTarget, underlying, enabled);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

