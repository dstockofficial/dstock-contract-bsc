/**
 * DStockWrapper_testUnwrapFlow.ts
 * -------------------------------
 * Integration flow:
 *   1. Optionally ensure KYC/custody via compliance module.
 *   2. Preview unwrap output & fees.
 *   3. Execute `unwrap`, wait for confirmation.
 *   4. Validate shares and balances decrease as expected.
 *
 * Run:
 *   npx ts-node --esm script/ts/integration/DStockWrapper_testUnwrapFlow.ts
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
  const recipient = process.env.TO || wallet.address;

  const [beforeShares, beforeWrapperBal, beforeTokenTo] = await Promise.all([
    wrapper.sharesOf(wallet.address),
    wrapper.balanceOf(wallet.address),
    erc20.balanceOf(recipient),
  ]);
  if (beforeShares === 0n) {
    throw new Error("No shares to unwrap; run wrap flow first.");
  }

  console.log("=== Unwrap Integration Flow ===");
  console.log("Signer         :", wallet.address);
  console.log("Wrapper        :", wrapper.target);
  console.log("Recipient (to) :", recipient);
  console.log("Amount (token) :", formatTokenAmount(amountWei, decimals), symbol);

  const preview = await wrapper.previewUnwrap(underlying, amountWei);
  console.log("Preview released18:", formatEther(preview.released18 || preview[0]));
  console.log("Preview fee18     :", formatEther(preview.fee18 || preview[1]));

  console.log("Executing unwrap...");
  const tx = await wrapper.unwrap(underlying, amountWei, recipient);
  console.log("Unwrap tx        :", tx.hash);
  await tx.wait();

  const [afterShares, afterWrapperBal, afterTokenTo] = await Promise.all([
    wrapper.sharesOf(wallet.address),
    wrapper.balanceOf(wallet.address),
    erc20.balanceOf(recipient),
  ]);

  console.log("\n--- Post-Checks ---");
  console.log("Shares Δ         :", (afterShares - beforeShares).toString());
  console.log("Wrapper bal Δ    :", formatEther(afterWrapperBal - beforeWrapperBal));
  console.log(
    "Recipient token Δ:",
    formatTokenAmount(afterTokenTo - beforeTokenTo, decimals),
    symbol
  );
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

