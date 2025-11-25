use starknet::ContractAddress;

/// Struct representing token-specific fee settings.
#[derive(Drop, Serde, starknet::Store, Copy)]
pub struct TokenFeeSettings {
    pub sender_to_provider: u64,
    pub provider_to_aggregator: u64,
    pub sender_to_aggregator: u64,
    pub provider_to_aggregator_fx: u64,
}

/// Interface for the GatewaySettingManager component.
#[starknet::interface]
pub trait IGatewaySettingManager<TContractState> {
    fn setting_manager_bool(
        ref self: TContractState, what: felt252, value: ContractAddress, status: u256,
    );
    fn update_protocol_address(ref self: TContractState, what: felt252, value: ContractAddress);
    fn set_token_fee_settings(
        ref self: TContractState,
        token: ContractAddress,
        sender_to_provider: u64,
        provider_to_aggregator: u64,
        sender_to_aggregator: u64,
        provider_to_aggregator_fx: u64,
    );
}

/// Component that manages the settings and configurations for the Gateway protocol.
#[starknet::component]
pub mod GatewaySettingManagerComponent {
    use core::num::traits::Zero;
    use starknet::ContractAddress;
    use starknet::storage::*;
    use super::TokenFeeSettings;

    #[storage]
    pub struct Storage {
        pub max_bps: u256,
        pub treasury_address: ContractAddress,
        pub aggregator_address: ContractAddress,
        pub is_token_supported: Map<ContractAddress, u256>,
        pub token_fee_settings: Map<ContractAddress, TokenFeeSettings>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        SettingManagerBool: SettingManagerBool,
        ProtocolAddressUpdated: ProtocolAddressUpdated,
        TokenFeeSettingsUpdated: TokenFeeSettingsUpdated,
    }

    /// Emitted when a setting is updated.
    #[derive(Drop, starknet::Event)]
    pub struct SettingManagerBool {
        #[key]
        pub what: felt252,
        #[key]
        pub value: ContractAddress,
        pub status: u256,
    }

    /// Emitted when a protocol address is updated.
    #[derive(Drop, starknet::Event)]
    pub struct ProtocolAddressUpdated {
        #[key]
        pub what: felt252,
        #[key]
        pub address: ContractAddress,
    }

    /// Emitted when token fee settings are updated.
    #[derive(Drop, starknet::Event)]
    pub struct TokenFeeSettingsUpdated {
        #[key]
        pub token: ContractAddress,
        pub sender_to_provider: u64,
        pub provider_to_aggregator: u64,
        pub sender_to_aggregator: u64,
        pub provider_to_aggregator_fx: u64,
    }

    // ##################################################################
    //                        PUBLIC FUNCTIONS
    // ##################################################################
    #[embeddable_as(GatewaySettingManagerImpl)]
    pub impl GatewaySettingManager<
        TContractState, +HasComponent<TContractState>,
    > of super::IGatewaySettingManager<ComponentState<TContractState>> {
        /// Sets the boolean value for a specific setting.
        /// Requirements:
        /// - The value must not be a zero address.
        fn setting_manager_bool(
            ref self: ComponentState<TContractState>,
            what: felt252,
            value: ContractAddress,
            status: u256,
        ) {
            assert(!value.is_zero(), 'Gateway: zero address');
            assert(status == 1 || status == 2, 'Gateway: invalid status');
            if what == 'token' {
                self.is_token_supported.entry(value).write(status);
                self.emit(SettingManagerBool { what, value, status });
            }
        }

        /// Sets token-specific fee settings.
        /// Requirements:
        /// - The token must be supported.
        /// - Fee percentages must be within valid ranges (<=MAX_BPS).
        fn set_token_fee_settings(
            ref self: ComponentState<TContractState>,
            token: ContractAddress,
            sender_to_provider: u64,
            provider_to_aggregator: u64,
            sender_to_aggregator: u64,
            provider_to_aggregator_fx: u64,
        ) {
            let is_supported = self.is_token_supported.entry(token).read();
            assert(is_supported == 1, 'Gateway: token not supported');

            let max_bps: u64 = self.max_bps.read().try_into().unwrap();
            assert(sender_to_provider <= max_bps, 'Invalid sender_to_provider');
            assert(provider_to_aggregator <= max_bps, 'Invalid provider_to_aggregator');
            assert(sender_to_aggregator <= max_bps, 'Invalid sender_to_aggregator');
            assert(provider_to_aggregator_fx <= max_bps, 'Invalid provider_to_agg_fx');

            let fee_settings = TokenFeeSettings {
                sender_to_provider,
                provider_to_aggregator,
                sender_to_aggregator,
                provider_to_aggregator_fx,
            };
            self.token_fee_settings.entry(token).write(fee_settings);

            self
                .emit(
                    TokenFeeSettingsUpdated {
                        token,
                        sender_to_provider,
                        provider_to_aggregator,
                        sender_to_aggregator,
                        provider_to_aggregator_fx,
                    },
                );
        }

        /// Updates a protocol address.
        /// Requirements:
        /// - The value must not be a zero address.
        fn update_protocol_address(
            ref self: ComponentState<TContractState>, what: felt252, value: ContractAddress,
        ) {
            assert(!value.is_zero(), 'Gateway: zero address');
            let mut updated = false;
            if what == 'treasury' {
                let current_treasury = self.treasury_address.read();
                assert(current_treasury != value, 'Gateway: treasury already set');
                self.treasury_address.write(value);
                updated = true;
            } else if what == 'aggregator' {
                let current_aggregator = self.aggregator_address.read();
                assert(current_aggregator != value, 'Gateway: aggregator already set');
                self.aggregator_address.write(value);
                updated = true;
            }
            if updated {
                self.emit(ProtocolAddressUpdated { what, address: value });
            }
        }
    }

    // ##################################################################
    //                        INTERNAL FUNCTIONS
    // ##################################################################
    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        /// Initializes the component with max BPS value.
        fn initializer(ref self: ComponentState<TContractState>) {
            self.max_bps.write(100_000);
        }

        /// Returns the max BPS value.
        fn get_max_bps(self: @ComponentState<TContractState>) -> u256 {
            self.max_bps.read()
        }

        /// Returns the treasury address.
        fn get_treasury_address(self: @ComponentState<TContractState>) -> ContractAddress {
            self.treasury_address.read()
        }

        /// Returns the aggregator address.
        fn get_aggregator_address(self: @ComponentState<TContractState>) -> ContractAddress {
            self.aggregator_address.read()
        }

        /// Checks if a token is supported.
        fn is_token_supported_internal(
            self: @ComponentState<TContractState>, token: ContractAddress,
        ) -> bool {
            let status = self.is_token_supported.entry(token).read();
            status == 1
        }

        /// Gets token-specific fee settings.
        fn get_token_fee_settings(
            self: @ComponentState<TContractState>, token: ContractAddress,
        ) -> TokenFeeSettings {
            self.token_fee_settings.entry(token).read()
        }
    }
}
