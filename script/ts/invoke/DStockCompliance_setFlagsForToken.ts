/**
 * DStockCompliance_setFlagsForToken.ts
 * ------------------------------------
 * Calls `setFlagsForToken(token, flags)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockCompliance_setFlagsForToken.ts
 */

import { getProvider, getWallet, getContract, requireBool, requireEnv } from "./utils.ts";

const COMPLIANCE_ABI = [
  "function setFlagsForToken(address token,(bool set,bool enforceSanctions,bool transferRestricted,bool wrapToCustodyOnly,bool unwrapFromCustodyOnly,bool kycOnWrap,bool kycOnUnwrap) flags)",
];

function buildFlags() {
  return {
    set: true,
    enforceSanctions: requireBool("FLAGS_ENFORCE_SANCTIONS"),
    transferRestricted: requireBool("FLAGS_TRANSFER_RESTRICTED"),
    wrapToCustodyOnly: requireBool("FLAGS_WRAP_TO_CUSTODY_ONLY"),
    unwrapFromCustodyOnly: requireBool("FLAGS_UNWRAP_FROM_CUSTODY_ONLY"),
    kycOnWrap: requireBool("FLAGS_KYC_ON_WRAP"),
    kycOnUnwrap: requireBool("FLAGS_KYC_ON_UNWRAP"),
  };
}

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const compliance = getContract("COMPLIANCE", COMPLIANCE_ABI, wallet);
  const token = requireEnv("FLAGS_WRAPPER");
  const flags = buildFlags();

  console.log("=== DStockCompliance.setFlagsForToken ===");
  console.log("Compliance:", compliance.target);
  console.log("Operator  :", wallet.address);
  console.log("Token     :", token);
  console.log("Flags     :", flags);

  const tx = await compliance.setFlagsForToken(token, flags);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

