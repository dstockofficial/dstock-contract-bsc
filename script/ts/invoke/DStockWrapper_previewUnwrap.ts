/**
 * DStockWrapper_previewUnwrap.ts
 * ------------------------------
 * Calls `previewUnwrap(token, amount)` to see released value and fees.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_previewUnwrap.ts
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
  "function previewUnwrap(address token, uint256 amountToken) view returns (uint256 released18, uint256 fee18)",
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

  console.log("=== DStockWrapper.previewUnwrap ===");
  console.log("Wrapper    :", wrapper.target);
  console.log("Underlying :", underlying);
  console.log("Amount     :", formatTokenAmount(amountWei, decimals), symbol);

  const { released18, fee18 } = await wrapper.previewUnwrap(
    underlying,
    amountWei
  );
  console.log("Released 18-dec:", formatEther(released18));
  console.log("Fee 18-dec     :", formatEther(fee18));
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

