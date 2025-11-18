/**
 * DStockWrapper_previewWrap.ts
 * ----------------------------
 * Calls `previewWrap(token, amount)` to obtain minted amount and fees.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_previewWrap.ts
 *
 * Required env:
 *   - WRAPPER
 *   - UNDERLYING
 *   - AMOUNT_WEI or AMOUNT
 */

import { Contract, formatEther } from "ethers";
import {
  getProvider,
  getContract,
  requireEnv,
  resolveAmountWei,
  formatTokenAmount,
} from "./utils.ts";

const WRAPPER_ABI = [
  "function previewWrap(address token, uint256 amountToken) view returns (uint256 mintedAmount18, uint256 fee18)",
];

const ERC20_ABI = [
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
];

async function main() {
  const provider = getProvider();
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, provider);
  const underlying = requireEnv("UNDERLYING");
  const erc20 = new Contract(underlying, ERC20_ABI, provider);

  const [symbol, decimals] = await Promise.all([
    erc20.symbol().catch(() => "TOKEN"),
    erc20.decimals(),
  ]);
  const amountWei = resolveAmountWei(decimals);

  console.log("=== DStockWrapper.previewWrap ===");
  console.log("Wrapper    :", wrapper.target);
  console.log("Underlying :", underlying);
  console.log("Amount     :", formatTokenAmount(amountWei, decimals), symbol);

  const { mintedAmount18, fee18 } = await wrapper.previewWrap(
    underlying,
    amountWei
  );
  console.log("Minted 18-dec:", formatEther(mintedAmount18));
  console.log("Fee 18-dec  :", formatEther(fee18));
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

