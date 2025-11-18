/**
 * DStockWrapper_setCap.ts
 * -----------------------
 * Calls `setCap(newCap18)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_setCap.ts
 */

import { formatEther, parseUnits } from "ethers";
import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = ["function setCap(uint256 newCap)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const capHuman = requireEnv("CAP_NEW");
  const cap = parseUnits(capHuman, 18);

  console.log("=== DStockWrapper.setCap ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("Cap 18  :", formatEther(cap));

  const tx = await wrapper.setCap(cap);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

