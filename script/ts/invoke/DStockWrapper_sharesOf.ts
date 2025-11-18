/**
 * DStockWrapper_sharesOf.ts
 * -------------------------
 * Reads `sharesOf(account)` and `totalShares()` for diagnostics.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_sharesOf.ts
 *
 * Required env:
 *   - WRAPPER
 *   - ACCOUNT (defaults to ADMIN / signer)
 */

import { formatEther } from "ethers";
import { getProvider, getContract } from "./utils.ts";

const WRAPPER_ABI = [
  "function sharesOf(address user) view returns (uint256)",
  "function totalShares() view returns (uint256)",
  "function balanceOf(address user) view returns (uint256)",
];

async function main() {
  const provider = getProvider();
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, provider);
  const account =
    process.env.ACCOUNT ||
    process.env.ADMIN ||
    process.env.WALLET ||
    (() => {
      throw new Error("Set ACCOUNT (or ADMIN/WALLET) in .env");
    })();

  const [shares, balance, totalShares] = await Promise.all([
    wrapper.sharesOf(account),
    wrapper.balanceOf(account),
    wrapper.totalShares(),
  ]);

  console.log("=== DStockWrapper.sharesOf ===");
  console.log("Wrapper    :", wrapper.target);
  console.log("Account    :", account);
  console.log("Shares     :", shares.toString());
  console.log("Balance    :", formatEther(balance));
  console.log("TotalShares:", totalShares.toString());
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

