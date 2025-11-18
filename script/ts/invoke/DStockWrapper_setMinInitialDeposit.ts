/**
 * DStockWrapper_setMinInitialDeposit.ts
 * -------------------------------------
 * Calls `setMinInitialDeposit(newMin18)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_setMinInitialDeposit.ts
 */

import { formatEther, parseUnits } from "ethers";
import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = ["function setMinInitialDeposit(uint256 newMin)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const minHuman = requireEnv("MIN_INITIAL_DEPOSIT_NEW");
  const min = parseUnits(minHuman, 18);

  console.log("=== DStockWrapper.setMinInitialDeposit ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("Min 18  :", formatEther(min));

  const tx = await wrapper.setMinInitialDeposit(min);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

