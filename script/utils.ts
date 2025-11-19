import readline from "readline";
import dotenv from "dotenv";
import { Account, Contract, RpcProvider, shortString, cairo } from "starknet";
import { getNetworkConfig } from "./config";
import { promises as fs } from "fs";
import * as path from "path";

dotenv.config();

export const assertEnvironment = () => {
  if (!process.env.DEPLOYER_PRIVATE_KEY) {
    console.error(" Please set DEPLOYER_PRIVATE_KEY in a .env file");
    process.exit(1);
  }
  if (!process.env.DEPLOYER_ADDRESS) {
    console.error(" Please set DEPLOYER_ADDRESS in a .env file");
    process.exit(1);
  }
  if (!process.env.TREASURY_ADDRESS) {
    console.error(" Please set TREASURY_ADDRESS in a .env file");
    process.exit(1);
  }
  if (!process.env.AGGREGATOR_ADDRESS) {
    console.error(" Please set AGGREGATOR_ADDRESS in a .env file");
    process.exit(1);
  }
};

export async function waitForInput(query: string): Promise<string> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) =>
    rl.question(query, (ans) => {
      rl.close();
      resolve(ans);
    })
  );
}

export async function confirmContinue(params: any) {
  console.log("\n PARAMETERS");
  console.table(params);

  const response = await waitForInput("\n❓ Do you want to continue? (y/N): ");
  if (response.toLowerCase() !== "y") {
    throw new Error(" Aborting script: User chose to exit");
  }
  console.log("\n");
}

/**
 * Get Starknet provider for the given network
 */
export function getProvider(network: string): RpcProvider {
  const networkConfig = getNetworkConfig(network);
  return new RpcProvider({ nodeUrl: networkConfig.rpcUrl });
}

/**
 * Get deployer account
 */
export function getDeployerAccount(network: string): Account {
  assertEnvironment();
  
  const provider = getProvider(network);
  const deployerAddress = process.env.DEPLOYER_ADDRESS!;
  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY!;

  return new Account(provider, deployerAddress, deployerPrivateKey, "1");
}

/**
 * Get Gateway contract instance
 */
export async function getGatewayContract(
  network: string,
  contractAddress?: string
): Promise<Contract> {
  const networkConfig = getNetworkConfig(network);
  const gatewayAddress = contractAddress || networkConfig.gatewayContract;

  if (!gatewayAddress) {
    throw new Error(" Gateway contract address not found. Please deploy first or provide address.");
  }

  const account = getDeployerAccount(network);

  // Load the compiled contract ABI
  const { sierra } = await loadCompiledContract("Gateway");

  const contract = new Contract(sierra.abi, gatewayAddress, account);
  
  return contract;
}

/**
 * Load compiled contract from target directory
 */
export async function loadCompiledContract(contractName: string) {
  const sierraPath = path.join(
    __dirname,
    `../target/dev/paycrest_${contractName}.contract_class.json`
  );
  
  const casmPath = path.join(
    __dirname,
    `../target/dev/paycrest_${contractName}.compiled_contract_class.json`
  );

  try {
    const sierra = JSON.parse(await fs.readFile(sierraPath, "utf-8"));
    const casm = JSON.parse(await fs.readFile(casmPath, "utf-8"));
    return { sierra, casm };
  } catch (error) {
    throw new Error(
      ` Failed to load compiled contract ${contractName}. Make sure you run 'scarb build' first.`
    );
  }
}

/**
 * Update config file with deployed contract address
 */
export async function updateConfigFile(
  network: string,
  contractAddress: string
): Promise<void> {
  try {
    const configFilePath = path.join(__dirname, "config.ts");
    let configContent = await fs.readFile(configFilePath, "utf-8");

    // Create a regex to find the network section and update gatewayContract
    const networkRegex = new RegExp(
      `("${network}":\\s*{[\\s\\S]*?)(\\/\\/\\s*gatewayContract:\\s*"0x\\.+"|gatewayContract\\?:\\s*string)([\\s\\S]*?})`,
      "g"
    );

    if (networkRegex.test(configContent)) {
      configContent = configContent.replace(
        networkRegex,
        `$1gatewayContract: "${contractAddress}"$3`
      );
    } else {
      const insertRegex = new RegExp(
        `("${network}":\\s*{[\\s\\S]*?)(\\s*}\,?)`,
        "g"
      );
      configContent = configContent.replace(
        insertRegex,
        `$1    gatewayContract: "${contractAddress}",\n  $2`
      );
    }

    await fs.writeFile(configFilePath, configContent, "utf-8");
    console.log(` Updated config file with gateway address: ${contractAddress}`);
  } catch (error) {
    console.error(" Error updating config file:", error);
    throw error;
  }
}

/**
 * Convert Cairo string (felt252) to shortString
 */
export function toShortString(str: string): string {
  return shortString.encodeShortString(str);
}

/**
 * Convert shortString back to regular string
 */
export function fromShortString(felt: string): string {
  return shortString.decodeShortString(felt);
}

/**
 * Wait for transaction confirmation
 */
export async function waitForTransaction(
  provider: RpcProvider,
  txHash: string
): Promise<void> {
  console.log(` Waiting for transaction: ${txHash}`);
  await provider.waitForTransaction(txHash);
  console.log(` Transaction confirmed: ${txHash}`);
}

/**
 * Format token address for display
 */
export function formatAddress(address: string): string {
  if (address.length <= 10) return address;
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

/**
 * Get explorer URL for transaction
 */
export function getExplorerUrl(network: string, txHash: string): string {
  const networkConfig = getNetworkConfig(network);
  return `${networkConfig.explorerUrl}/tx/${txHash}`;
}

/**
 * Get explorer URL for contract
 */
export function getContractExplorerUrl(network: string, address: string): string {
  const networkConfig = getNetworkConfig(network);
  return `${networkConfig.explorerUrl}/contract/${address}`;
}

