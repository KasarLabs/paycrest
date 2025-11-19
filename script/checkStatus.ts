import {
  assertEnvironment,
  getGatewayContract,
  fromShortString,
  formatAddress,
} from "./utils";
import { getNetworkConfig } from "./config";
import dotenv from "dotenv";

dotenv.config();

const network = process.argv[2] || "SN_SEPOLIA";

async function checkStatus() {
  console.log("\n Checking Gateway Contract Status");
  console.log(` Network: ${network}\n`);

  try {
    const networkConfig = getNetworkConfig(network);
    
    if (!networkConfig.gatewayContract) {
      console.log(" No gateway contract deployed on this network yet.");
      console.log("   Run 'npm run deploy' to deploy the contract first.\n");
      return;
    }

    const gatewayContract = await getGatewayContract(network);
    
    console.log(" Contract Information:");
    console.log(`   Address: ${gatewayContract.address}`);
    console.log(`   Explorer: ${networkConfig.explorerUrl}/contract/${gatewayContract.address}\n`);

    try {
      if (process.env.DEPLOYER_ADDRESS) {
        const owner = await gatewayContract.owner();
        console.log("👤 Ownership:");
        console.log(`   Owner: ${formatAddress(owner)}`);
        console.log(`   Is Deployer: ${owner.toString().toLowerCase() === process.env.DEPLOYER_ADDRESS.toLowerCase()}\n`);
      }
    } catch (error) {
      console.log("  Could not fetch owner (method may not exist)\n");
    }

    console.log("Token Support Status:");
    for (const [tokenName, tokenConfig] of Object.entries(networkConfig.supportedTokens)) {
      try {
        const isSupported = await gatewayContract.is_token_supported(tokenConfig.address);
        console.log(`   ${tokenName} (${formatAddress(tokenConfig.address)}): ${isSupported ? ' Supported' : ' Not Supported'}`);
      } catch (error) {
        console.log(`   ${tokenName}:   Could not check (${error instanceof Error ? error.message : 'unknown error'})`);
      }
    }

    console.log("\n Status check complete!");

  } catch (error) {
    console.error("\n Failed to check status:", error);
    throw error;
  }
}

checkStatus()
  .then(() => {
    console.log("\n Done!");
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

