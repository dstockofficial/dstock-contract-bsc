/**
 * DStockFactoryRegistry_addUnderlyings.ts
 * ---------------------------------------
 * Calls `addUnderlyings(wrapper, tokens[])`.
 *
 * Run:
 *   npx ts-node script/ts/DStockFactoryRegistry_addUnderlyings.ts
 */

import { getProvider, getWallet, getContract, requireEnv, parseAddressList } from "./utils.ts";

const FACTORY_ABI = [
  "function addUnderlyings(address wrapper, address[] tokens)",
];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const factory = getContract("FACTORY", FACTORY_ABI, wallet);
  const wrapperTarget = requireEnv("TARGET_WRAPPER");
  const parsed = parseAddressList(requireEnv("UNDERLYINGS_LIST"));
  if (parsed.length === 0) {
    throw new Error("UNDERLYINGS_LIST must contain at least one address");
  }

  console.log("=== DStockFactoryRegistry.addUnderlyings ===");
  console.log("Factory :", factory.target);
  console.log("Operator:", wallet.address);
  console.log("Wrapper :", wrapperTarget);
  console.log("Tokens  :", parsed);

  const tx = await factory.addUnderlyings(wrapperTarget, parsed);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

