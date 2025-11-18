/**
 * DStockWrapper_forceMoveToTreasury.ts
 * ------------------------------------
 * Calls `forceMoveToTreasury(from, amount18)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_forceMoveToTreasury.ts
 */

import { formatEther } from "ethers";
import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = ["function forceMoveToTreasury(address from, uint256 amount18)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const from = requireEnv("FORCE_MOVE_FROM");
  const amount18 = BigInt(requireEnv("FORCE_MOVE_AMOUNT_18"));

  console.log("=== DStockWrapper.forceMoveToTreasury ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("From    :", from);
  console.log("Amount18:", formatEther(amount18));

  const tx = await wrapper.forceMoveToTreasury(from, amount18);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

