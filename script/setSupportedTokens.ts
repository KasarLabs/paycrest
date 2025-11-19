import {
  assertEnvironment,
  getGatewayContract,
  toShortString,
  waitForTransaction,
  getProvider,
  getExplorerUrl,
  confirmContinue,
  formatAddress,
} from "./utils";
import { getNetworkConfig } from "./config";
import dotenv from "dotenv";

dotenv.config();

// Get network from command line args or default to SN_SEPOLIA
const network = process.argv[2] || "SN_SEPOLIA";

assertEnvironment();

async function setSupportedTokens() {
  console.log("\n Setting Supported Tokens");
  console.log(` Network: ${network}\n`);

  const networkConfig = getNetworkConfig(network);
  const tokenList = Object.entries(networkConfig.supportedTokens).map(([name, token]) => ({
    name,
    address: formatAddress(token.address),
  }));

  await confirmContinue({
    Network: network,
    "Tokens to whitelist": tokenList.length,
    Tokens: tokenList,
  });

  try {
    const gatewayContract = await getGatewayContract(network);
    const provider = getProvider(network);

    console.log(` Connected to Gateway: ${gatewayContract.address}\n`);

    const tokenIdentifier = toShortString("token");

    // Whitelist each token
    for (const [tokenName, tokenConfig] of Object.entries(networkConfig.supportedTokens)) {
      try {
        console.log(` Whitelisting ${tokenName} (${formatAddress(tokenConfig.address)})...`);

        const tx = await gatewayContract.setting_manager_bool(
          tokenIdentifier,
          tokenConfig.address,
          1 // status = 1 means supported
        );

        console.log(`   Transaction hash: ${tx.transaction_hash}`);
        console.log(`   Explorer: ${getExplorerUrl(network, tx.transaction_hash)}`);
        await waitForTransaction(provider, tx.transaction_hash);
        console.log(` ${tokenName} whitelisted successfully!\n`);

      } catch (error) {
        console.error(` Failed to whitelist ${tokenName}:`, error);
      }
    }

    console.log(" All tokens processed!");
    console.log("\n Next step: Run 'npm run set-fee-settings' to configure token fee settings");

  } catch (error) {
    console.error("\n Failed to set supported tokens:", error);
    throw error;
  }
}

// Execute
setSupportedTokens()
  .then(() => {
    console.log("\n Token whitelisting complete!");
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

