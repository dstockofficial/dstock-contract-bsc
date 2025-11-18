/**
 * DStockWrapper_unwrap.ts
 * -----------------------
* Execute `unwrap(UNDERLYING, AMOUNT, TO)` using signer shares.
*
* Run:
*   npx ts-node script/ts/DStockWrapper_unwrap.ts
 *
 * Required env:
 *   - WRAPPER
 *   - UNDERLYING
 *   - PRIVATE_KEY / ADMIN_PK
 *   - AMOUNT_WEI or AMOUNT (token units to redeem)
 *
 * Optional env:
 *   - TO (defaults to signer)
 */

import { Contract, formatEther } from "ethers";
import {
  getProvider,
  getWallet,
  getContract,
  requireEnv,
  resolveAmountWei,
  formatTokenAmount,
} from "./utils.ts";

const WRAPPER_ABI = [
  "function unwrap(address token, uint256 amount, address to)",
  "function previewUnwrap(address token, uint256 amountToken) view returns (uint256 released18, uint256 fee18)",
  "function balanceOf(address user) view returns (uint256)",
  "function sharesOf(address user) view returns (uint256)",
];

const ERC20_ABI = [
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function balanceOf(address user) view returns (uint256)",
];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const underlying = requireEnv("UNDERLYING");
  const erc20 = new Contract(underlying, ERC20_ABI, provider);

  const [symbol, decimals] = await Promise.all([
    erc20.symbol().catch(() => "TOKEN"),
    erc20.decimals(),
  ]);
  const amountWei = resolveAmountWei(decimals);
  const to = process.env.TO || wallet.address;

  console.log("=== DStockWrapper.unwrap ===");
  console.log("Signer         :", wallet.address);
  console.log("Wrapper        :", wrapper.target);
  console.log("Underlying     :", underlying);
  console.log("Recipient (to) :", to);
  console.log("Amount (token) :", formatTokenAmount(amountWei, decimals), symbol);

  const preview = await wrapper.previewUnwrap(underlying, amountWei);
  console.log("Preview released18:", formatEther(preview.released18 || preview[0]));
  console.log("Preview fee18    :", formatEther(preview.fee18 || preview[1]));

  const tx = await wrapper.unwrap(underlying, amountWei, to);
  console.log("Unwrap tx sent   :", tx.hash);
  const receipt = await tx.wait();
  console.log("Unwrap confirmed in block", receipt.blockNumber);

  const [wrapperBal, shareBal, tokenBal] = await Promise.all([
    wrapper.balanceOf(wallet.address),
    wrapper.sharesOf(wallet.address),
    erc20.balanceOf(to),
  ]);

  console.log("\n--- Post state ---");
  console.log("Shares (signer) :", shareBal.toString());
  console.log("Wrapper balance :", formatEther(wrapperBal));
  console.log(
    `Underlying bal (to): ${formatTokenAmount(tokenBal, decimals)} ${symbol}`
  );
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

