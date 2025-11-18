/**
 * DStockCompliance_getFlags.ts
 * ----------------------------
 * Reads global flags + per-token override (if WRAPPER env is set).
 *
 * Run:
 *   npx ts-node script/ts/DStockCompliance_getFlags.ts
 */

import { getProvider, getContract } from "./utils.ts";

const COMPLIANCE_ABI = [
  "function globalFlags() view returns (tuple(bool set,bool enforceSanctions,bool transferRestricted,bool wrapToCustodyOnly,bool unwrapFromCustodyOnly,bool kycOnWrap,bool kycOnUnwrap))",
  "function getFlags(address token) view returns (tuple(bool set,bool enforceSanctions,bool transferRestricted,bool wrapToCustodyOnly,bool unwrapFromCustodyOnly,bool kycOnWrap,bool kycOnUnwrap))",
];

async function main() {
  const provider = getProvider();
  const compliance = getContract("COMPLIANCE", COMPLIANCE_ABI, provider);

  const globalFlags = await compliance.globalFlags();
  console.log("=== DStockCompliance.globalFlags ===");
  console.log(globalFlags);

  if (process.env.WRAPPER) {
    const flags = await compliance.getFlags(process.env.WRAPPER);
    console.log(`\nFlags for ${process.env.WRAPPER}:`);
    console.log(flags);
  } else {
    console.log("\n(WRAPPER not set; skipping per-token flags)");
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

