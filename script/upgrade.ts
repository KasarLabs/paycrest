import { execSync } from 'child_process';

import {
  assertEnvironment,
  getGatewayContract,
  getDeployerAccount,
  loadCompiledContract,
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

async function upgradeGateway() {
  console.log("\n Upgrading Paycrest Gateway");
  console.log(` Network: ${network}\n`);

  try {
    const gatewayContract = await getGatewayContract(network);
    const provider = getProvider(network);
    const account = getDeployerAccount(network);

    console.log(` Current Gateway Address: ${gatewayContract.address}\n`);

    await confirmContinue({
      Network: network,
      "Gateway Address": gatewayContract.address,
      "Deployer Address": process.env.DEPLOYER_ADDRESS,
      Action: "Upgrade to new implementation",
    });

    console.log(" Loading new compiled contract...");
    const { sierra, casm } = await loadCompiledContract("Gateway");

    console.log("\n Declaring new contract class...");
    const declareResponse = await account.declareIfNot({
      contract: sierra,
      casm: casm,
    });

    if (declareResponse.transaction_hash) {
      console.log(`   Declaration TX: ${declareResponse.transaction_hash}`);
      console.log(`   Explorer: ${getExplorerUrl(network, declareResponse.transaction_hash)}`);
      await waitForTransaction(provider, declareResponse.transaction_hash);
    }

    const newClassHash = declareResponse.class_hash;
    console.log(`   New Class Hash: ${newClassHash}`);

    // Upgrade the contract to the new class hash
    console.log("\n Upgrading contract...");
    const upgradeTx = await gatewayContract.upgrade(newClassHash);

    console.log(`   Upgrade TX: ${upgradeTx.transaction_hash}`);
    console.log(`   Explorer: ${getExplorerUrl(network, upgradeTx.transaction_hash)}`);
    await waitForTransaction(provider, upgradeTx.transaction_hash);

    const networkName = network === "SN_MAIN" ? "mainnet" : "sepolia";
    
    const verifyCommand = `sncast verify --class-hash ${newClassHash} --contract-name Gateway --verifier voyager --network ${networkName}`;
      
    console.log(`Running: ${verifyCommand}\n`);

    execSync(verifyCommand, { stdio: 'inherit' });

    console.log("\n Gateway upgraded successfully!");
    console.log(`   Contract Address (unchanged): ${gatewayContract.address}`);
    console.log(`   New Class Hash: ${newClassHash}`);

    return {
      contractAddress: gatewayContract.address,
      newClassHash,
      transactionHash: upgradeTx.transaction_hash,
    };
  } catch (error) {
    console.error("\n Upgrade failed:", error);
    throw error;
  }
}

// Execute upgrade
upgradeGateway()
  .then((result) => {
    console.log("\n Upgrade complete!");
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

