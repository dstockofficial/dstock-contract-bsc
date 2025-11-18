import { config as loadEnv } from "dotenv";
import fs from "fs";
import path from "path";
import {
  JsonRpcProvider,
  Wallet,
  Contract,
  formatEther,
  parseUnits,
} from "ethers";
import type { InterfaceAbi, ContractRunner } from "ethers";

const repoRoot = path.resolve(new URL(".", import.meta.url).pathname, "..", "..", "..");

// Load .env and .env.local (if present) once.
loadDotEnvFiles();

export function requireEnv(key: string): string {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing environment variable: ${key}`);
  }
  return value;
}

export function getProvider(): JsonRpcProvider {
  const rpc =
    process.env.BSC_TESTNET_RPC ||
    process.env.BSC_RPC ||
    process.env.RPC_URL ||
    "";
  if (!rpc) {
    throw new Error(
      "RPC URL not set; set BSC_TESTNET_RPC / BSC_RPC / RPC_URL in .env"
    );
  }
  return new JsonRpcProvider(rpc);
}

export function getWallet(provider: JsonRpcProvider): Wallet {
  const pk =
    process.env.PRIVATE_KEY ||
    process.env.ADMIN_PK ||
    process.env.DEPLOYER_PK;
  if (!pk) {
    throw new Error("Missing PRIVATE_KEY / ADMIN_PK for signing transactions");
  }
  return new Wallet(pk, provider);
}

export function getContract<T extends Contract>(
  addressEnv: string,
  abi: InterfaceAbi,
  runner?: ContractRunner
): T {
  const address = requireEnv(addressEnv);
  return new Contract(address, abi, runner) as T;
}

export function requireBool(key: string): boolean {
  const value = process.env[key];
  if (value === undefined) {
    throw new Error(`Missing boolean env: ${key}`);
  }
  return ["true", "1", "yes"].includes(value.toLowerCase());
}

export function parseAddressList(value: string): string[] {
  if (!value) return [];
  try {
    if (value.trim().startsWith("[")) {
      return JSON.parse(value);
    }
  } catch {
    // fall back to comma split
  }
  return value
    .split(",")
    .map((v) => v.trim())
    .filter(Boolean);
}

export function resolveAmountWei(
  decimals: number | bigint = 18,
  amountWeiEnv = "AMOUNT_WEI",
  amountHumanEnv = "AMOUNT"
): bigint {
  const d = normalizeDecimals(decimals);
  const rawWei = process.env[amountWeiEnv];
  if (rawWei && rawWei !== "") {
    return BigInt(rawWei);
  }
  const rawHuman = process.env[amountHumanEnv];
  if (rawHuman && rawHuman !== "") {
    return parseUnits(rawHuman, d);
  }
  throw new Error(
    `Set ${amountWeiEnv} (wei) or ${amountHumanEnv} (human-readable) to specify amount`
  );
}

export function formatTokenAmount(amount: bigint, decimals: number | bigint = 18): string {
  const d = normalizeDecimals(decimals);
  if (d === 18) {
    return formatEther(amount);
  }
  return (Number(amount) / 10 ** d).toString();
}

function loadDotEnvFiles() {
  const files = [".env", ".env.local"];
  for (const file of files) {
    const abs = path.join(repoRoot, file);
    if (fs.existsSync(abs)) {
      loadEnv({ path: abs, override: false });
    }
  }
}

function normalizeDecimals(decimals: number | bigint): number {
  if (typeof decimals === "bigint") {
    return Number(decimals);
  }
  return decimals;
}

