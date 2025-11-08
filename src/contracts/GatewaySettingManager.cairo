use starknet::ContractAddress;

/// Interface for the GatewaySettingManager component.
#[starknet::interface]
pub trait IGatewaySettingManager<TContractState> {
    fn setting_manager_bool(
        ref self: TContractState, what: felt252, value: ContractAddress, status: u256,
    );
    fn update_protocol_fee(ref self: TContractState, protocol_fee_percent: u64);
    fn update_protocol_address(ref self: TContractState, what: felt252, value: ContractAddress);
}

/// Component that manages the settings and configurations for the Gateway protocol.
#[starknet::component]
pub mod GatewaySettingManagerComponent {
    use core::num::traits::Zero;
    use starknet::ContractAddress;
    use starknet::storage::*;

    #[storage]
    pub struct Storage {
        pub max_bps: u256,
        pub protocol_fee_percent: u64,
        pub treasury_address: ContractAddress,
        pub aggregator_address: ContractAddress,
        pub is_token_supported: Map<ContractAddress, u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        SettingManagerBool: SettingManagerBool,
        ProtocolFeeUpdated: ProtocolFeeUpdated,
        ProtocolAddressUpdated: ProtocolAddressUpdated,
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

    /// Emitted when protocol fee is updated.
    #[derive(Drop, starknet::Event)]
    pub struct ProtocolFeeUpdated {
        pub protocol_fee: u64,
    }

    /// Emitted when a protocol address is updated.
    #[derive(Drop, starknet::Event)]
    pub struct ProtocolAddressUpdated {
        #[key]
        pub what: felt252,
        #[key]
        pub address: ContractAddress,
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

        /// Updates the protocol fee percentage.
        fn update_protocol_fee(
            ref self: ComponentState<TContractState>, protocol_fee_percent: u64,
        ) {
            self.protocol_fee_percent.write(protocol_fee_percent);
            self.emit(ProtocolFeeUpdated { protocol_fee: protocol_fee_percent });
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

        /// Returns the protocol fee percent.
        fn get_protocol_fee_percent(self: @ComponentState<TContractState>) -> u64 {
            self.protocol_fee_percent.read()
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
    }
}
