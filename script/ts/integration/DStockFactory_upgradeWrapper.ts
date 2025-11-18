/**
 * DStockFactory_upgradeWrapper.ts
 * -------------------------------
 * Integration flow:
 *   1. Read the current beacon implementation used by all wrappers.
 *   2. Call `setWrapperImplementation(NEW_WRAPPER_IMPL)` on the factory.
 *   3. Verify the beacon now points to the new implementation.
 *
 * Run:
 *   npx ts-node --esm script/ts/integration/DStockFactory_upgradeWrapper.ts
 */

import { Contract } from "ethers";
import { getProvider, getWallet, getContract, requireEnv } from "../invoke/utils.ts";

const FACTORY_ABI = [
  "function setWrapperImplementation(address newImplementation)",
  "function beacon() view returns (address)",
];

const BEACON_ABI = ["function implementation() view returns (address)"];

async function main() {
  const provider = getProvider();
  const wallet = getWallet(provider);
  const factory = getContract("FACTORY", FACTORY_ABI, wallet);
  const beaconAddr = await factory.beacon();
  const beacon = new Contract(beaconAddr, BEACON_ABI, provider);
  const oldImpl = await beacon.implementation();
  const newImpl = requireEnv("WRAPPER_IMPL_NEW");

  console.log("=== Factory wrapper upgrade ===");
  console.log("Factory :", factory.target);
  console.log("Beacon  :", beaconAddr);
  console.log("Operator:", wallet.address);
  console.log("Old impl:", oldImpl);
  console.log("New impl:", newImpl);

  if (oldImpl.toLowerCase() === newImpl.toLowerCase()) {
    console.log("New implementation equals current implementation; skipping upgrade.");
    return;
  }

  const tx = await factory.setWrapperImplementation(newImpl);
  console.log("Tx sent :", tx.hash);
  await tx.wait();

  const afterImpl = await beacon.implementation();
  console.log("Updated impl:", afterImpl);
  if (afterImpl.toLowerCase() !== newImpl.toLowerCase()) {
    throw new Error("Beacon implementation mismatch after upgrade.");
  }
  console.log("Upgrade successful.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

