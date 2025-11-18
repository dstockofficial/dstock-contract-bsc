/**
 * DStockCompliance_isTransferAllowed.ts
 * -------------------------------------
 * Calls `isTransferAllowed(token, from, to, amount, action)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockCompliance_isTransferAllowed.ts
 */

import { getProvider, getContract, requireEnv } from "./utils.ts";

const COMPLIANCE_ABI = [
  "function isTransferAllowed(address token,address from,address to,uint256 amount,uint8 action) view returns (bool)",
];

async function main() {
  const provider = getProvider();
  const compliance = getContract("COMPLIANCE", COMPLIANCE_ABI, provider);
  const token = requireEnv("COMPLIANCE_TOKEN");
  const from = requireEnv("TRANSFER_FROM");
  const to = requireEnv("TRANSFER_TO");
  const amount = BigInt(requireEnv("TRANSFER_AMOUNT_WEI"));
  const action = Number(requireEnv("TRANSFER_ACTION"));

  const allowed = await compliance.isTransferAllowed(token, from, to, amount, action);

  console.log("=== DStockCompliance.isTransferAllowed ===");
  console.log("Compliance:", compliance.target);
  console.log("Token     :", token);
  console.log("From      :", from);
  console.log("To        :", to);
  console.log("AmountWei :", amount.toString());
  console.log("Action    :", action);
  console.log("Allowed   :", allowed);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

