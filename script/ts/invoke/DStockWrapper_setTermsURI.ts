/**
 * DStockWrapper_setTermsURI.ts
 * ----------------------------
 * Calls `setTermsURI(newURI)`.
 *
 * Run:
 *   npx ts-node script/ts/DStockWrapper_setTermsURI.ts
 */

import { getProvider, getWallet, getContract, requireEnv } from "./utils.ts";

const WRAPPER_ABI = ["function setTermsURI(string uri)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
  const uri = requireEnv("TERMS_URI_NEW");

  console.log("=== DStockWrapper.setTermsURI ===");
  console.log("Wrapper :", wrapper.target);
  console.log("Operator:", wallet.address);
  console.log("URI     :", uri);

  const tx = await wrapper.setTermsURI(uri);
  console.log("Tx sent :", tx.hash);
  await tx.wait();
  console.log("Tx confirmed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

