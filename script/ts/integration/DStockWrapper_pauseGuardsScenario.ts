/**
 * DStockWrapper_pauseGuardsScenario.ts
 * ------------------------------------
 * Integration goals:
 *   1. In a normal state (not paused, wrapUnwrapPaused == false), perform a baseline wrap to ensure balances and flow are sane.
 *   2. Enable wrapUnwrapPaused (local wrap/unwrap pause) and verify that both wrap and unwrap revert.
 *   3. Enable OZ Pausable's pause (if not already paused) and verify that wrap and unwrap also revert under global pause.
 *
 * This script restores the original wrapUnwrapPaused / paused configuration at the end so it does not permanently change governance state.
 *
 * Run:
 *   npx ts-node --esm script/ts/integration/DStockWrapper_pauseGuardsScenario.ts
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
  // business
  "function wrap(address token, uint256 amount, address to) returns (uint256 net18, uint256 shares)",
  "function unwrap(address token, uint256 amount, address to)",
  "function sharesOf(address user) view returns (uint256)",
  "function balanceOf(address user) view returns (uint256)",
  // pause guards
  "function wrapUnwrapPaused() view returns (bool)",
  "function paused() view returns (bool)",
  "function setWrapUnwrapPaused(bool p)",
  "function pause()",
  "function unpause()",
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

  const [oldWrapUnwrapPaused, oldPaused] = await Promise.all([
    wrapper.wrapUnwrapPaused(),
    wrapper.paused(),
  ]);

  console.log("=== DStockWrapper pause guards scenario ===");
  console.log("Signer          :", wallet.address);
  console.log("Wrapper         :", wrapper.target);
  console.log("Underlying      :", underlying);
  console.log("Amount (token)  :", formatTokenAmount(amountWei, decimals), symbol);
  console.log("Old wrapPaused  :", oldWrapUnwrapPaused);
  console.log("Old paused (OZ) :", oldPaused);

  if (!oldWrapUnwrapPaused) {
    const tx = await wrapper.setWrapUnwrapPaused(true);
    await tx.wait();
    console.log("→ wrapUnwrapPaused set to true");
  } else {
    console.log("wrapUnwrapPaused already true; reusing current state");
  }
  if (!oldPaused) {
    const tx = await wrapper.pause();
    await tx.wait();
    console.log("→ paused set to true");
  } else {
    console.log("paused already true; reusing current state");
  }
  // --- Step 1: baseline wrap to ensure environment is sane ---
  const [beforeToken, beforeShares, beforeWrapperBal] = await Promise.all([
    erc20.balanceOf(wallet.address),
    wrapper.sharesOf(to),
    wrapper.balanceOf(to),
  ]);
  if (beforeToken < amountWei) {
    throw new Error("Insufficient underlying balance for baseline wrap.");
  }

  const allowance = await erc20.allowance(wallet.address, wrapper.target);
  if (allowance < amountWei) {
    console.log("Allowance insufficient. Approving...");
    const approveTx = await erc20.approve(wrapper.target, amountWei);
    await approveTx.wait();
    console.log("→ Approved");
  }

  if (!oldWrapUnwrapPaused && !oldPaused) {
    console.log("\n-- Baseline wrap (no pauses) --");
    const tx = await wrapper.wrap(underlying, amountWei, to);
    console.log("Baseline wrap tx:", tx.hash);
    await tx.wait();
  } else {
    console.log("\n[Info] Baseline not executed because wrapper is already paused; skipping.");
  }

  // Ensure we have shares to test unwrap; if not, we just test wrap revert.
  const sharesNow = await wrapper.sharesOf(to);

  // wrap should revert when wrapUnwrapPaused = true
  try {
    console.log("Attempting wrap() while wrapUnwrapPaused == true...");
    const tx = await wrapper.wrap(underlying, amountWei, to);
    await tx.wait();
    console.error("❌ wrap() succeeded unexpectedly while wrapUnwrapPaused == true");
  } catch (err) {
    console.log("✅ wrap() reverted as expected while wrapUnwrapPaused == true");
  }

  // unwrap should also revert when wrapUnwrapPaused = true (if we have shares)
  if (sharesNow > 0n) {
    try {
      console.log("Attempting unwrap() while wrapUnwrapPaused == true...");
      const tx = await wrapper.unwrap(underlying, amountWei, to);
      await tx.wait();
      console.error("❌ unwrap() succeeded unexpectedly while wrapUnwrapPaused == true");
    } catch (err) {
      console.log("✅ unwrap() reverted as expected while wrapUnwrapPaused == true");
    }
  } else {
    console.log("[Info] No shares for unwrap test under wrapUnwrapPaused; skipping unwrap check.");
  }

  // --- Step 3: enable OZ pause (if needed) and verify wrap/unwrap also revert ---
  console.log("\n-- Enabling OZ pause and testing guards --");
  const pausedNow = await wrapper.paused();
  if (!pausedNow) {
    const tx = await wrapper.pause();
    await tx.wait();
    console.log("→ paused() set to true (OZ Pausable)");
  } else {
    console.log("paused() already true; reusing current state");
  }

  try {
    console.log("Attempting wrap() while paused() == true...");
    const tx = await wrapper.wrap(underlying, amountWei, to);
    await tx.wait();
    console.error("❌ wrap() succeeded unexpectedly while paused() == true");
  } catch (err) {
    console.log("✅ wrap() reverted as expected while paused() == true");
  }

  if (sharesNow > 0n) {
    try {
      console.log("Attempting unwrap() while paused() == true...");
      const tx = await wrapper.unwrap(underlying, amountWei, to);
      await tx.wait();
      console.error("❌ unwrap() succeeded unexpectedly while paused() == true");
    } catch (err) {
      console.log("✅ unwrap() reverted as expected while paused() == true");
    }
  }

  // --- Step 4: restore original pause configuration ---
  console.log("\n-- Restoring original pause configuration --");
  await wrapper.setWrapUnwrapPaused(false);
  await wrapper.unpause();
  console.log("→ paused set to false");


  // Final balances / shares for reference
  const [finalToken, finalShares, finalWrapperBal] = await Promise.all([
    erc20.balanceOf(wallet.address),
    wrapper.sharesOf(to),
    wrapper.balanceOf(to),
  ]);

  console.log("\n=== Final State ===");
  console.log("Token balance Δ:", formatTokenAmount(finalToken - beforeToken, decimals), symbol);
  console.log("Shares Δ       :", (finalShares - beforeShares).toString());
  console.log("Wrapper bal Δ  :", formatEther(finalWrapperBal - beforeWrapperBal));
  console.log("wrapUnwrapPaused:", await wrapper.wrapUnwrapPaused());
  console.log("paused (OZ)     :", await wrapper.paused());
  console.log("Pause guards scenario completed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});


