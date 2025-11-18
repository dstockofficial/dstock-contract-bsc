/**
 * DStockCompliance_upgradeScenario.ts
 * -----------------------------------
 * Integration flow for migrating to a new compliance module:
 *   1. Copy global flags from OLD_COMPLIANCE to NEW_COMPLIANCE.
 *   2. Optionally copy per-token flags (`FLAGS_COPY_TOKENS`).
 *   3. Optionally copy KYC / custody / sanctions state for supplied address lists.
 *   4. Point the factory (`FACTORY`) and/or wrapper (`WRAPPER`) to the new compliance.
 *
 * Run:
 *   npx ts-node --esm script/ts/integration/DStockCompliance_upgradeScenario.ts
 */

import {
  getProvider,
  getWallet,
  getContract,
  requireEnv,
  parseAddressList,
} from "../invoke/utils.ts";

const COMPLIANCE_ABI = [
  "function globalFlags() view returns (tuple(bool set,bool enforceSanctions,bool transferRestricted,bool wrapToCustodyOnly,bool unwrapFromCustodyOnly,bool kycOnWrap,bool kycOnUnwrap))",
  "function getFlags(address token) view returns (tuple(bool set,bool enforceSanctions,bool transferRestricted,bool wrapToCustodyOnly,bool unwrapFromCustodyOnly,bool kycOnWrap,bool kycOnUnwrap))",
  "function setFlagsGlobal((bool set,bool enforceSanctions,bool transferRestricted,bool wrapToCustodyOnly,bool unwrapFromCustodyOnly,bool kycOnWrap,bool kycOnUnwrap) flags)",
  "function setFlagsForToken(address token,(bool set,bool enforceSanctions,bool transferRestricted,bool wrapToCustodyOnly,bool unwrapFromCustodyOnly,bool kycOnWrap,bool kycOnUnwrap) flags)",
  "function clearFlagsForToken(address token)",
  "function kyc(address user) view returns (bool)",
  "function custody(address user) view returns (bool)",
  "function sanctioned(address user) view returns (bool)",
  "function setKyc(address user, bool ok)",
  "function setCustody(address user, bool ok)",
  "function setSanctioned(address user, bool bad)",
];

const FACTORY_ABI = ["function setGlobalCompliance(address c)"];
const WRAPPER_ABI = ["function setCompliance(address c)"];

async function copyFlags(
  source: any,
  target: any,
  tokens: string[]
) {
  const globalFlags = await source.globalFlags();
  // Build an explicit struct object to avoid missing components when encoding
  const globalFlagsStruct = {
    set: true,
    enforceSanctions: globalFlags.enforceSanctions,
    transferRestricted: globalFlags.transferRestricted,
    wrapToCustodyOnly: globalFlags.wrapToCustodyOnly,
    unwrapFromCustodyOnly: globalFlags.unwrapFromCustodyOnly,
    kycOnWrap: globalFlags.kycOnWrap,
    kycOnUnwrap: globalFlags.kycOnUnwrap,
  };
  await target.setFlagsGlobal(globalFlagsStruct);
  console.log("Copied global flags.");
  for (const token of tokens) {
    if (!token) continue;
    const flags = await source.getFlags(token);
    const flagsStruct = {
      set: true,
      enforceSanctions: flags.enforceSanctions,
      transferRestricted: flags.transferRestricted,
      wrapToCustodyOnly: flags.wrapToCustodyOnly,
      unwrapFromCustodyOnly: flags.unwrapFromCustodyOnly,
      kycOnWrap: flags.kycOnWrap,
      kycOnUnwrap: flags.kycOnUnwrap,
    };
    await target.setFlagsForToken(token, flagsStruct);
    console.log(`Copied token flags for ${token}`);
  }
}

async function copyEntityStates(
  source: any,
  target: any,
  addresses: string[],
  getterName: "kyc" | "custody" | "sanctioned",
  setterName: "setKyc" | "setCustody" | "setSanctioned"
) {
  for (const addr of addresses) {
    if (!addr) continue;
    const current = await source[getterName](addr);
    const tx = await target[setterName](addr, current);
    await tx.wait();
    console.log(`Copied ${getterName}(${addr}) -> ${current}`);
  }
}

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const oldCompliance = getContract("OLD_COMPLIANCE", COMPLIANCE_ABI, wallet);
  const newCompliance = getContract("NEW_COMPLIANCE", COMPLIANCE_ABI, wallet);

  const tokensToCopy = parseAddressList(process.env.FLAGS_COPY_TOKENS || "");
  await copyFlags(oldCompliance, newCompliance, tokensToCopy);

  await copyEntityStates(
    oldCompliance,
    newCompliance,
    parseAddressList(process.env.KYC_COPY_ADDRESSES || ""),
    "kyc",
    "setKyc"
  );
  await copyEntityStates(
    oldCompliance,
    newCompliance,
    parseAddressList(process.env.CUSTODY_COPY_ADDRESSES || ""),
    "custody",
    "setCustody"
  );
  await copyEntityStates(
    oldCompliance,
    newCompliance,
    parseAddressList(process.env.SANCTION_COPY_ADDRESSES || ""),
    "sanctioned",
    "setSanctioned"
  );

  const newAddr: string =
    (newCompliance.target as string | undefined) ??
    (newCompliance.address as string);

  if (process.env.FACTORY) {
    const factory = getContract("FACTORY", FACTORY_ABI, wallet);
    await factory.setGlobalCompliance(newAddr);
    console.log(`Factory ${factory.target} now points to new compliance.`);
  }

  if (process.env.WRAPPER) {
    const wrapper = getContract("WRAPPER", WRAPPER_ABI, wallet);
    await wrapper.setCompliance(newAddr);
    console.log(`Wrapper ${wrapper.target} now points to new compliance.`);
  }

  console.log("Compliance upgrade scenario completed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

