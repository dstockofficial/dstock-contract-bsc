/**
 * DStockWrapper_wrap.ts
 * ---------------------
 * Execute a live `wrap(UNDERLYING, AMOUNT, TO)` call against an already deployed
 * DStockWrapper.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_wrap.ts
 *
 * Required env:
 *   - WRAPPER: wrapper contract address
 *   - UNDERLYING: ERC20 token to wrap
 *   - PRIVATE_KEY / ADMIN_PK: signer holding the underlying
 *   - AMOUNT_WEI or AMOUNT: amount of underlying tokens (token units)
 *
 * Optional env:
 *   - TO: recipient address (defaults to signer)
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
  "function wrap(address token, uint256 amount, address to) returns (uint256 net18, uint256 shares)",
  "function previewWrap(address token, uint256 amountToken) view returns (uint256 mintedAmount18, uint256 fee18)",
  "function balanceOf(address user) view returns (uint256)",
  "function sharesOf(address user) view returns (uint256)",
];

const ERC20_ABI = [
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address user) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const underlying = requireEnv("UNDERLYING");
  const erc20 = new Contract(underlying, ERC20_ABI, wallet);

  const [symbol, decimals] = await Promise.all([
    erc20.symbol().catch(() => "TOKEN"),
    erc20.decimals(),
  ]);
  const amountWei = resolveAmountWei(decimals);
  const to = process.env.TO || wallet.address;

  console.log("=== DStockWrapper.wrap ===");
  console.log("Signer         :", wallet.address);
  console.log("Wrapper        :", wrapper.target);
  console.log("Underlying     :", underlying);
  console.log("Recipient (to) :", to);
  console.log("Amount (token) :", formatTokenAmount(amountWei, decimals), symbol);

  const preview = await wrapper.previewWrap(underlying, amountWei);
  console.log("Preview net18  :", formatEther(preview.mintedAmount18 || preview[0]));
  console.log("Preview fee18  :", formatEther(preview.fee18 || preview[1]));

  const allowance = await erc20.allowance(wallet.address, wrapper.target);
  if (allowance < amountWei) {
    console.log("Allowance insufficient. Approving...");
    const approveTx = await erc20.approve(wrapper.target, amountWei);
    await approveTx.wait();
    console.log("→ Approved.");
  }

  const tx = await wrapper.wrap(underlying, amountWei, to);
  console.log("Wrap tx sent   :", tx.hash);
  const receipt = await tx.wait();
  console.log("Wrap confirmed in block", receipt.blockNumber);

  const [wrapperBal, shareBal, tokenBal] = await Promise.all([
    wrapper.balanceOf(to),
    wrapper.sharesOf(to),
    erc20.balanceOf(wallet.address),
  ]);

  console.log("\n--- Post state ---");
  console.log("Wrapper balance:", formatEther(wrapperBal));
  console.log("Shares         :", shareBal.toString());
  console.log(
    `Underlying bal : ${formatTokenAmount(tokenBal, decimals)} ${symbol}`
  );
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

