/**
 * DStockWrapper_applySplit.ts
 * ---------------------------
 * Calls `applySplit(token, numerator, denominator)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_applySplit.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = [
  "function applySplit(address token, uint256 numerator, uint256 denominator)",
];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const token = requireEnv("SPLIT_UNDERLYING");
  const numerator = BigInt(requireEnv("SPLIT_NUMERATOR"));
  const denominator = BigInt(requireEnv("SPLIT_DENOMINATOR"));

  console.log("=== DStockWrapper.applySplit ===");
  console.log("Wrapper    :", wrapper.target);
  console.log("Operator   :", wallet.address);
  console.log("Underlying :", token);
  console.log("Ratio      :", `${numerator.toString()} / ${denominator.toString()}`);

  const tx = await wrapper.applySplit(token, numerator, denominator);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

