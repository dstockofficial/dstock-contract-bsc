/**
 * DStockWrapper_testWrapFlow.ts
 * -----------------------------
 * Integration flow:
 *   1. Optionally set KYC / custody on the compliance module (if enabled via env).
 *   2. Preview wrap output & fees.
 *   3. Ensure ERC20 allowance and balances.
 *   4. Execute `wrap`, wait for confirmation, then verify shares/balances deltas.
 *
 * Run:
 *   npx ts-node --esm script/ts/integration/DStockWrapper_testWrapFlow.ts
 */

import { Contract, formatEther } from "ethers";
import {
  getProvider,
  getWallet,
  getContract,
  requireEnv,
  resolveAmountWei,
  formatTokenAmount,
} from "../invoke/utils.ts";

const WRAPPER_ABI = [
  "function wrap(address token, uint256 amount, address to) returns (uint256 net18, uint256 shares)",
  "function previewWrap(address token, uint256 amountToken) view returns (uint256 mintedAmount18, uint256 fee18)",
  "function balanceOf(address user) view returns (uint256)",
  "function sharesOf(address user) view returns (uint256)",
];

const ERC20_ABI = [
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function balanceOf(address user) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
];

const COMPLIANCE_ABI = [
  "function kyc(address user) view returns (bool)",
  "function custody(address user) view returns (bool)",
  "function setKyc(address user, bool ok)",
  "function setCustody(address user, bool ok)",
];

function envBool(key: string, fallback = false): boolean {
  const value = process.env[key];
  if (value === undefined) return fallback;
  return ["true", "1", "yes"].includes(value.toLowerCase());
}

async function ensureCompliance(
  complianceAddr: string | undefined,
  signer: Contract["runner"]
) {
  if (!complianceAddr || !signer) return;
  const compliance = new Contract(complianceAddr, COMPLIANCE_ABI, signer);
  const addr = await signer.getAddress();
  if (envBool("TEST_AUTO_KYC", true)) {
    const already = await compliance.kyc(addr);
    if (!already) {
      const tx = await compliance.setKyc(addr, true);
      await tx.wait();
      console.log("→ Set KYC true for", addr);
    }
  }
  if (envBool("TEST_AUTO_CUSTODY", false)) {
    const already = await compliance.custody(addr);
    if (!already) {
      const tx = await compliance.setCustody(addr, true);
      await tx.wait();
      console.log("→ Set custody true for", addr);
    }
  }
}

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const underlying = requireEnv("UNDERLYING");
  const erc20 = new Contract(underlying, ERC20_ABI, wallet);
  const complianceAddr = process.env.COMPLIANCE;

  await ensureCompliance(complianceAddr, wallet);

  const [symbol, decimals] = await Promise.all([
    erc20.symbol().catch(() => "TOKEN"),
    erc20.decimals(),
  ]);
  const amountWei = resolveAmountWei(decimals);
  const to = process.env.TO || wallet.address;

  console.log("=== Wrap Integration Flow ===");
  console.log("Signer         :", wallet.address);
  console.log("Wrapper        :", wrapper.target);
  console.log("Underlying     :", underlying);
  console.log("Recipient (to) :", to);
  console.log("Amount (token) :", formatTokenAmount(amountWei, decimals), symbol);

  const preview = await wrapper.previewWrap(underlying, amountWei);
  console.log("Preview net18  :", formatEther(preview.mintedAmount18 || preview[0]));
  console.log("Preview fee18  :", formatEther(preview.fee18 || preview[1]));

  const [allowance, beforeToken, beforeShares, beforeWrapperBal] = await Promise.all([
    erc20.allowance(wallet.address, wrapper.target),
    erc20.balanceOf(wallet.address),
    wrapper.sharesOf(to),
    wrapper.balanceOf(to),
  ]);
  if (beforeToken < amountWei) {
    throw new Error("Insufficient underlying balance for wrap.");
  }
  if (allowance < amountWei) {
    console.log("Allowance insufficient. Approving...");
    const approveTx = await erc20.approve(wrapper.target, amountWei);
    await approveTx.wait();
    console.log("→ Approved");
  }

  console.log("Executing wrap...");
  const tx = await wrapper.wrap(underlying, amountWei, to);
  console.log("Wrap tx        :", tx.hash);
  await tx.wait();

  const [afterToken, afterShares, afterWrapperBal] = await Promise.all([
    erc20.balanceOf(wallet.address),
    wrapper.sharesOf(to),
    wrapper.balanceOf(to),
  ]);

  console.log("\n--- Post-Checks ---");
  console.log("Token balance Δ:", formatTokenAmount(afterToken - beforeToken, decimals), symbol);
  console.log("Shares Δ       :", (afterShares - beforeShares).toString());
  console.log("Wrapper bal Δ  :", formatEther(afterWrapperBal - beforeWrapperBal));
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

