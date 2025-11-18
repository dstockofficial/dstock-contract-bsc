/**
 * DStockWrapper_underlyingInfo.ts
 * -------------------------------
 * Calls `underlyingInfo(token)` and prints decoded metadata.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_underlyingInfo.ts
 */

import { Contract } from "ethers";
import { getProvider, getContract, requireEnv, formatTokenAmount } from "./utils.ts";

const WRAPPER_ABI = [
  "function underlyingInfo(address token) view returns (bool isEnabled, uint8 tokenDecimals, uint256 liquidToken)",
  "function isUnderlyingEnabled(address token) view returns (bool)",
];

const ERC20_ABI = [
  "function symbol() view returns (string)",
];

async function main() {
  const provider = getProvider();
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, provider);
  const token = requireEnv("UNDERLYING");
  const erc20 = new Contract(token, ERC20_ABI, provider);

  const [info, enabled, symbol] = await Promise.all([
    wrapper.underlyingInfo(token),
    wrapper.isUnderlyingEnabled(token),
    erc20.symbol().catch(() => "TOKEN"),
  ]);

  console.log("=== DStockWrapper.underlyingInfo ===");
  console.log("Wrapper   :", wrapper.target);
  console.log("Underlying:", token);
  console.log("Enabled?  :", enabled);
  console.log("Decimals  :", info.tokenDecimals);
  console.log(
    "Liquid    :",
    formatTokenAmount(info.liquidToken, info.tokenDecimals),
    symbol
  );
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

