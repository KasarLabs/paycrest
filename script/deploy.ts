import { CallData} from "starknet";
import { execSync } from 'child_process';
import {
  assertEnvironment,
  confirmContinue,
  getDeployerAccount,
  getProvider,
  loadCompiledContract,
  updateConfigFile,
  waitForTransaction,
  getExplorerUrl,
  getContractExplorerUrl,
} from "./utils";
import dotenv from "dotenv";

dotenv.config();

// Get network from command line args or default to SN_SEPOLIA
const network = process.argv[2] || "SN_MAIN";

assertEnvironment();

async function deployGateway() {
  console.log("\n=== Deploying Paycrest Gateway to Starknet ===");
  console.log(`Network: ${network}\n`);

  await confirmContinue({
    Contract: "Gateway",
    Network: network,
    "Deployer Address": process.env.DEPLOYER_ADDRESS,
    "Treasury Address": process.env.TREASURY_ADDRESS,
    "Aggregator Address": process.env.AGGREGATOR_ADDRESS,
  });

  try {
    // Load compiled contract
    console.log("[1/4] Loading compiled contract...");
    const { sierra, casm } = await loadCompiledContract("Gateway");

    // Get provider and account
    const provider = getProvider(network);
    const account = getDeployerAccount(network);

    // Prepare constructor calldata
    // Gateway constructor takes only owner address
    const ownerAddress = process.env.DEPLOYER_ADDRESS!;
    
    const constructorCalldata = CallData.compile({
      owner: ownerAddress,
    });

    console.log("[2/4] Constructor parameters:");
    console.log(`   Owner: ${ownerAddress}`);

    // Declare the contract (if not already declared)
    console.log("[3/4] Declaring contract...");

    const declareResponse = await account.declareIfNot(
      {
        contract: sierra,
        casm: casm,
      },
      {
        version: 3,
      }
    );

    if (declareResponse.transaction_hash) {
      console.log(`   Declaration TX: ${declareResponse.transaction_hash}`);
      console.log(`   Explorer: ${getExplorerUrl(network, declareResponse.transaction_hash)}`);
      await waitForTransaction(provider, declareResponse.transaction_hash);
    }

    const classHash = declareResponse.class_hash;
    console.log(`   Class Hash: ${classHash}`);

    // Deploy the contract
    console.log("[4/4] Deploying contract...");
    
    const deployResponse = await account.deployContract(
      {
        classHash: classHash,
        constructorCalldata,
      },
      {
        version: 3,
      }
    );

    console.log(`   Deployment TX: ${deployResponse.transaction_hash}`);
    console.log(`   Explorer: ${getExplorerUrl(network, deployResponse.transaction_hash)}`);
    
    await waitForTransaction(provider, deployResponse.transaction_hash);

    const contractAddress = deployResponse.contract_address;

    console.log("\n=== Gateway deployed successfully! ===");
    console.log(`   Contract Address: ${contractAddress}`);
    console.log(`   Explorer: ${getContractExplorerUrl(network, contractAddress)}`);

    // Update config file
    await updateConfigFile(network, contractAddress);

    const networkName = network === "SN_MAIN" ? "mainnet" : "sepolia";

    const verifyCommand = `sncast verify --class-hash ${classHash} --contract-name Gateway --verifier voyager --network ${networkName}`;
      
    console.log(`Running: ${verifyCommand}\n`);

    execSync(verifyCommand, { stdio: 'inherit' });

    console.log("\n✅ Contract verified successfully!");
    const explorerUrl = network === "SN_MAIN" 
      ? `https://voyager.online/contract/${contractAddress}`
      : `https://sepolia.voyager.online/contract/${contractAddress}`;
    console.log(`   View on Voyager: ${explorerUrl}`);

    console.log("\n=== Next steps ===");
    console.log("   1. Run 'npm run update-addresses' to set treasury and aggregator");
    console.log("   2. Run 'npm run set-tokens' to whitelist supported tokens");
    console.log("   3. Run 'npm run set-fee-settings' to configure token fee settings");

    return {
      contractAddress,
      classHash,
      transactionHash: deployResponse.transaction_hash,
    };
  } catch (error) {
    console.error("\n[ERROR] Deployment failed:", error);
    throw error;
  }
}

// Execute deployment
deployGateway()
  .then((result) => {
    console.log("\n=== Deployment complete! ===");
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

