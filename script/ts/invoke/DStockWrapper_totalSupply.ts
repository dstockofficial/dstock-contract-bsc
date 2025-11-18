/**
 * DStockWrapper_totalSupply.ts
 * ----------------------------
 * Reads ERC20 `totalSupply()` from the wrapper.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_totalSupply.ts
 */

import { formatEther } from "ethers";
import { getProvider, getContract } from "./utils.ts";

const WRAPPER_ABI = ["function totalSupply() view returns (uint256)"];

async function main() {
  const provider = getProvider();
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, provider);
  const total = await wrapper.totalSupply();

  console.log("=== DStockWrapper.totalSupply ===");
  console.log("Wrapper     :", wrapper.target);
  console.log("TotalSupply :", formatEther(total), "wrapper units");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

