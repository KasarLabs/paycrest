import {
  assertEnvironment,
  getGatewayContract,
  waitForTransaction,
  getProvider,
  getExplorerUrl,
  confirmContinue,
  formatAddress,
} from "./utils";
import { getNetworkConfig } from "./config";
import dotenv from "dotenv";

dotenv.config();

// Get network from command line args or default to SN_MAIN
const network = process.argv[2] || "SN_MAIN";

assertEnvironment();

async function setTokenFeeSettings() {
  console.log("\n  Setting Token Fee Settings");
  console.log(` Network: ${network}\n`);

  const networkConfig = getNetworkConfig(network);
  const tokenList = Object.entries(networkConfig.supportedTokens).map(([name, token]) => ({
    name,
    address: formatAddress(token.address),
    "Local (Sender→Provider)": `${token.local.senderToProvider / 1000}%`,
    "Local (Provider→Aggregator)": `${token.local.providerToAggregator / 1000}%`,
    "FX (Sender→Aggregator)": `${token.fx.senderToAggregator / 1000}%`,
    "FX (Provider→Aggregator)": `${token.fx.providerToAggregator / 1000}%`,
  }));

  await confirmContinue({
    Network: network,
    "Tokens to configure": tokenList.length,
    "Fee Settings": tokenList,
  });

  try {
    const gatewayContract = await getGatewayContract(network);
    const provider = getProvider(network);

    console.log(` Connected to Gateway: ${gatewayContract.address}\n`);

    // Configure fee settings for each token
    for (const [tokenName, tokenConfig] of Object.entries(networkConfig.supportedTokens)) {
      try {
        console.log(` Setting fee settings for ${tokenName} (${formatAddress(tokenConfig.address)})...`);
        console.log(`   Local Transfer:`);
        console.log(`     - Sender→Provider: ${tokenConfig.local.senderToProvider / 1000}% (${tokenConfig.local.senderToProvider} BPS)`);
        console.log(`     - Provider→Aggregator: ${tokenConfig.local.providerToAggregator / 1000}% (${tokenConfig.local.providerToAggregator} BPS)`);
        console.log(`   FX Transfer:`);
        console.log(`     - Sender→Aggregator: ${tokenConfig.fx.senderToAggregator / 1000}% (${tokenConfig.fx.senderToAggregator} BPS)`);
        console.log(`     - Provider→Aggregator: ${tokenConfig.fx.providerToAggregator / 1000}% (${tokenConfig.fx.providerToAggregator} BPS)`);

        const tx = await gatewayContract.set_token_fee_settings(
          tokenConfig.address,
          tokenConfig.local.senderToProvider,
          tokenConfig.local.providerToAggregator,
          tokenConfig.fx.senderToAggregator,
          tokenConfig.fx.providerToAggregator
        );

        console.log(`   Transaction hash: ${tx.transaction_hash}`);
        console.log(`   Explorer: ${getExplorerUrl(network, tx.transaction_hash)}`);
        await waitForTransaction(provider, tx.transaction_hash);
        console.log(` Fee settings configured for ${tokenName}!\n`);

      } catch (error) {
        console.error(` Failed to set fee settings for ${tokenName}:`, error);
        // Continue with next token
      }
    }

    console.log(" All token fee settings configured successfully!");

  } catch (error) {
    console.error("\n Failed to set token fee settings:", error);
    throw error;
  }
}

// Execute
setTokenFeeSettings()
  .then(() => {
    console.log("\n Token fee settings configuration complete!");
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

