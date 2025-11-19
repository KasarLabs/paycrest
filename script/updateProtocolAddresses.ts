import {
  assertEnvironment,
  getGatewayContract,
  toShortString,
  waitForTransaction,
  getProvider,
  getExplorerUrl,
  confirmContinue,
} from "./utils";
import dotenv from "dotenv";

dotenv.config();

// Get network from command line args or default to SN_SEPOLIA
const network = process.argv[2] || "SN_SEPOLIA";

assertEnvironment();

async function updateProtocolAddresses() {
  console.log("\n Updating Protocol Addresses");
  console.log(` Network: ${network}\n`);

  await confirmContinue({
    Network: network,
    "Treasury Address": process.env.TREASURY_ADDRESS,
    "Aggregator Address": process.env.AGGREGATOR_ADDRESS,
  });

  try {
    const gatewayContract = await getGatewayContract(network);
    const provider = getProvider(network);

    console.log(` Connected to Gateway: ${gatewayContract.address}\n`);

    const treasury = toShortString("treasury");
    const aggregator = toShortString("aggregator");

    console.log(" Updating treasury address...");
    const treasuryTx = await gatewayContract.update_protocol_address(
      treasury,
      process.env.TREASURY_ADDRESS!
    );
    
    console.log(`   Transaction hash: ${treasuryTx.transaction_hash}`);
    console.log(`   Explorer: ${getExplorerUrl(network, treasuryTx.transaction_hash)}`);
    await waitForTransaction(provider, treasuryTx.transaction_hash);
    console.log(` Treasury address updated to: ${process.env.TREASURY_ADDRESS}\n`);

    console.log(" Updating aggregator address...");
    const aggregatorTx = await gatewayContract.update_protocol_address(
      aggregator,
      process.env.AGGREGATOR_ADDRESS!
    );
    
    console.log(`   Transaction hash: ${aggregatorTx.transaction_hash}`);
    console.log(`   Explorer: ${getExplorerUrl(network, aggregatorTx.transaction_hash)}`);
    await waitForTransaction(provider, aggregatorTx.transaction_hash);
    console.log(` Aggregator address updated to: ${process.env.AGGREGATOR_ADDRESS}\n`);

    console.log(" All protocol addresses updated successfully!");

  } catch (error) {
    console.error("\n Failed to update protocol addresses:", error);
    throw error;
  }
}

// Execute
updateProtocolAddresses()
  .then(() => {
    console.log("\n Protocol addresses updated!");
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

