/**
 * DStockWrapper_setUnderlyingRebaseParams.ts
 * ------------------------------------------
 * Calls `setUnderlyingRebaseParams(token, feeMode, feePerPeriodRay, periodLength)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_setUnderlyingRebaseParams.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = [
  "function setUnderlyingRebaseParams(address token, uint8 feeMode, uint256 feePerPeriodRay, uint32 periodLength)",
];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const token = requireEnv("REBASING_UNDERLYING");
  const feeMode = Number(requireEnv("REBASING_FEE_MODE"));
  const feePerPeriodRay = BigInt(requireEnv("REBASING_FEE_PER_PERIOD_RAY"));
  const periodLength = Number(requireEnv("REBASING_PERIOD_LENGTH"));

  console.log("=== DStockWrapper.setUnderlyingRebaseParams ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("Underlying:", token);
  console.log("feeMode  :", feeMode);
  console.log("fee/Ray  :", feePerPeriodRay.toString());
  console.log("period   :", periodLength, "seconds");

  const tx = await wrapper.setUnderlyingRebaseParams(
    token,
    feeMode,
    feePerPeriodRay,
    periodLength
  );
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

