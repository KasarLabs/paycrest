import dotenv from "dotenv";

dotenv.config();

// MAX BPS = 100000
const SENDER_TO_PROVIDER_FEE = 50000; // 50%
const LOCAL_PROVIDER_TO_AGGREGATOR_FEE = 50000; // 50%
const SENDER_TO_AGGREGATOR_FEE = 0; // 0%
const FX_PROVIDER_TO_AGGREGATOR_FEE = 500; // 0.5%

export interface TokenConfig {
  address: string;
  local: {
    senderToProvider: number;
    providerToAggregator: number;
  };
  fx: {
    senderToAggregator: number;
    providerToAggregator: number;
  };
}

export interface NetworkConfig {
  rpcUrl: string;
  explorerUrl: string;
  supportedTokens: {
    [key: string]: TokenConfig;
  };
  gatewayContract?: string; // Will be set after deployment
}

export const NETWORKS: { [chainId: string]: NetworkConfig } = {
  /**
   * @dev Starknet Mainnet
   * Chain ID: SN_MAIN (0x534e5f4d41494e)
   */
  "SN_MAIN": {
    rpcUrl: process.env.STARKNET_MAINNET_RPC_URL || "",
    explorerUrl: "https://starkscan.co",
    supportedTokens: {
      USDC: {
        address: "0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8", // Starknet USDC
        local: {
          senderToProvider: SENDER_TO_PROVIDER_FEE,
          providerToAggregator: LOCAL_PROVIDER_TO_AGGREGATOR_FEE,
        },
        fx: {
          senderToAggregator: SENDER_TO_AGGREGATOR_FEE,
          providerToAggregator: FX_PROVIDER_TO_AGGREGATOR_FEE,
        },
      },
      USDT: {
        address: "0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8", // Starknet USDT
        local: {
          senderToProvider: SENDER_TO_PROVIDER_FEE,
          providerToAggregator: LOCAL_PROVIDER_TO_AGGREGATOR_FEE,
        },
        fx: {
          senderToAggregator: SENDER_TO_AGGREGATOR_FEE,
          providerToAggregator: FX_PROVIDER_TO_AGGREGATOR_FEE,
        },
      },
      DAI: {
        address: "0x00da114221cb83fa859dbdb4c44beeaa0bb37c7537ad5ae66fe5e0efd20e6eb3", // Starknet DAI
        local: {
          senderToProvider: SENDER_TO_PROVIDER_FEE,
          providerToAggregator: LOCAL_PROVIDER_TO_AGGREGATOR_FEE,
        },
        fx: {
          senderToAggregator: SENDER_TO_AGGREGATOR_FEE,
          providerToAggregator: FX_PROVIDER_TO_AGGREGATOR_FEE,
        },
      },
    },
    gatewayContract: "0x06ff3a3b1532da65594fc98f9ca7200af6c3dbaf37e7339b0ebd3b3f2390c583",
  },

  /**
   * @dev Starknet Sepolia Testnet
   * Chain ID: SN_SEPOLIA (0x534e5f5345504f4c4941)
   */
  "SN_SEPOLIA": {
    rpcUrl: process.env.STARKNET_SEPOLIA_RPC_URL || "https://starknet-sepolia.public.blastapi.io",
    explorerUrl: "https://sepolia.starkscan.co",
    supportedTokens: {
      STRK: {
        address: "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d", // Sepolia STRK
        local: {
          senderToProvider: SENDER_TO_PROVIDER_FEE,
          providerToAggregator: LOCAL_PROVIDER_TO_AGGREGATOR_FEE,
        },
        fx: {
          senderToAggregator: SENDER_TO_AGGREGATOR_FEE,
          providerToAggregator: FX_PROVIDER_TO_AGGREGATOR_FEE,
        },
      },
      ETH: {
        address: "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7", // Sepolia ETH
        local: {
          senderToProvider: SENDER_TO_PROVIDER_FEE,
          providerToAggregator: LOCAL_PROVIDER_TO_AGGREGATOR_FEE,
        },
        fx: {
          senderToAggregator: SENDER_TO_AGGREGATOR_FEE,
          providerToAggregator: FX_PROVIDER_TO_AGGREGATOR_FEE,
        },
      },
    },
  },
};

/**
 * Get network configuration by network identifier
 */
export function getNetworkConfig(network: string): NetworkConfig {
  const config = NETWORKS[network];
  if (!config) {
    throw new Error(`Network ${network} not found in configuration`);
  }
  return config;
}

