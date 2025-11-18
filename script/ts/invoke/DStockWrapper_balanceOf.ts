/**
 * DStockWrapper_balanceOf.ts
 * --------------------------
 * Reads ERC20 `balanceOf(account)` for the wrapper token.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_balanceOf.ts
 */

import { formatEther } from "ethers";
import { getProvider, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = ["function balanceOf(address user) view returns (uint256)"];

async function main() {
  const provider = getProvider();
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, provider);
  const account =
    process.env.ACCOUNT ||
    process.env.ADMIN ||
    requireEnv("ACCOUNT");

  const bal = await wrapper.balanceOf(account);

  console.log("=== DStockWrapper.balanceOf ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Account :", account);
  console.log("Balance :", formatEther(bal));
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

