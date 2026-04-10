#[starknet::contract]
pub mod Gateway {
    use core::hash::{HashStateExTrait, HashStateTrait};
    use core::num::traits::Zero;
    use core::poseidon::PoseidonTrait;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_security::pausable::PausableComponent;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_upgrades::UpgradeableComponent;
    use openzeppelin_upgrades::interface::IUpgradeable;
    use paycrest::contracts::GatewaySettingManager::GatewaySettingManagerComponent;
    use paycrest::interfaces::IGateway::{
        FxTransferFeeSplit, IGateway, LocalTransferFeeSplit, Order, OrderCreated, OrderRefunded,
        SenderFeeTransferred, SettleIn, SettleOut,
    };
    use starknet::storage::*;
    use starknet::{ContractAddress, get_caller_address};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(
        path: GatewaySettingManagerComponent,
        storage: gateway_setting_manager,
        event: GatewaySettingManagerEvent,
    );

    // Ownable Two-Step Mixin
    #[abi(embed_v0)]
    impl OwnableTwoStepMixinImpl =
        OwnableComponent::OwnableTwoStepMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // Pausable
    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;

    // Upgradeable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    // GatewaySettingManager
    impl GatewaySettingManagerImpl =
        GatewaySettingManagerComponent::GatewaySettingManagerImpl<ContractState>;
    impl GatewaySettingManagerInternalImpl =
        GatewaySettingManagerComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        gateway_setting_manager: GatewaySettingManagerComponent::Storage,
        order: Map<felt252, Order>,
        nonce: Map<ContractAddress, u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        GatewaySettingManagerEvent: GatewaySettingManagerComponent::Event,
        OrderCreated: OrderCreated,
        SettleOut: SettleOut,
        SettleIn: SettleIn,
        OrderRefunded: OrderRefunded,
        SenderFeeTransferred: SenderFeeTransferred,
        LocalTransferFeeSplit: LocalTransferFeeSplit,
        FxTransferFeeSplit: FxTransferFeeSplit,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.gateway_setting_manager.initializer();
        self.ownable.initializer(owner);
    }

    /// Pause the contract.
    #[external(v0)]
    fn pause(ref self: ContractState) {
        self.ownable.assert_only_owner();
        self.pausable.pause();
    }

    /// Unpause the contract.
    #[external(v0)]
    fn unpause(ref self: ContractState) {
        self.ownable.assert_only_owner();
        self.pausable.unpause();
    }

    /// Wrapper for setting_manager_bool with owner check.
    #[external(v0)]
    fn setting_manager_bool(
        ref self: ContractState, what: felt252, value: ContractAddress, status: u256,
    ) {
        self.ownable.assert_only_owner();
        self.gateway_setting_manager.setting_manager_bool(what, value, status);
    }

    /// Wrapper for update_protocol_address with owner check.
    #[external(v0)]
    fn update_protocol_address(ref self: ContractState, what: felt252, value: ContractAddress) {
        self.ownable.assert_only_owner();
        self.gateway_setting_manager.update_protocol_address(what, value);
    }

    /// Wrapper for set_token_fee_settings with owner check.
    #[external(v0)]
    fn set_token_fee_settings(
        ref self: ContractState,
        token: ContractAddress,
        sender_to_provider: u64,
        provider_to_aggregator: u64,
        sender_to_aggregator: u64,
        provider_to_aggregator_fx: u64,
    ) {
        self.ownable.assert_only_owner();
        self
            .gateway_setting_manager
            .set_token_fee_settings(
                token,
                sender_to_provider,
                provider_to_aggregator,
                sender_to_aggregator,
                provider_to_aggregator_fx,
            );
    }

    // ##################################################################
    //                     UPGRADEABLE IMPLEMENTATION
    // ##################################################################
    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        /// Upgrades the contract to a new implementation.
        fn upgrade(ref self: ContractState, new_class_hash: starknet::ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    // ##################################################################
    //                     GATEWAY IMPLEMENTATION
    // ##################################################################
    #[abi(embed_v0)]
    impl GatewayImpl of IGateway<ContractState> {
        fn create_order(
            ref self: ContractState,
            token: ContractAddress,
            amount: u256,
            rate: u128,
            sender_fee_recipient: ContractAddress,
            sender_fee: u256,
            refund_address: ContractAddress,
            message_hash: ByteArray,
        ) -> felt252 {
            self.pausable.assert_not_paused();

            self._handler(token, amount, refund_address, sender_fee_recipient, sender_fee);

            assert(message_hash.len() != 0, 'InvalidMessageHash');

            let caller = get_caller_address();
            let this_contract = starknet::get_contract_address();
            let total_amount = amount + sender_fee;

            let erc20 = IERC20Dispatcher { contract_address: token };
            erc20.transfer_from(caller, this_contract, total_amount);

            let current_nonce = self.nonce.entry(caller).read();
            let new_nonce = current_nonce + 1;
            self.nonce.entry(caller).write(new_nonce);

            let chain_id: felt252 = starknet::get_execution_info().unbox().tx_info.unbox().chain_id;
            let order_id = PoseidonTrait::new()
                .update_with(caller)
                .update_with(new_nonce)
                .update_with(chain_id)
                .finalize();

            let existing_order = self.order.entry(order_id).read();
            assert(existing_order.sender.is_zero(), 'OrderAlreadyExists');

            let max_bps = self.gateway_setting_manager.get_max_bps();

            // Determine protocol fee based on rate
            let protocol_fee = if rate == 100 {
                // Local transfer (rate = 1 encoded as 100): no protocol fee
                assert(sender_fee > 0, 'SenderFeeIsZero');
                0_u256
            } else {
                // FX transfer: use token-specific providerToAggregatorFx
                let settings = self.gateway_setting_manager.get_token_fee_settings(token);
                assert(settings.provider_to_aggregator_fx > 0, 'TokenFeeSettingsNotConfigured');
                (amount * settings.provider_to_aggregator_fx.into()) / max_bps
            };

            let new_order = Order {
                sender: caller,
                token,
                sender_fee_recipient,
                sender_fee,
                protocol_fee,
                is_fulfilled: false,
                is_refunded: false,
                refund_address,
                current_bps: max_bps.try_into().unwrap(),
                amount,
            };
            self.order.entry(order_id).write(new_order);

            self
                .emit(
                    OrderCreated {
                        sender: refund_address,
                        token,
                        amount,
                        protocol_fee,
                        order_id,
                        rate,
                        message_hash,
                    },
                );

            order_id
        }

        fn settle_out(
            ref self: ContractState,
            split_order_id: felt252,
            order_id: felt252,
            liquidity_provider: ContractAddress,
            settle_percent: u64,
            rebate_percent: u64,
        ) -> bool {
            self._assert_only_aggregator();

            let mut order_data = self.order.entry(order_id).read();
            let max_bps = self.gateway_setting_manager.get_max_bps();

            assert(!order_data.is_fulfilled, 'OrderFulfilled');
            assert(!order_data.is_refunded, 'OrderRefunded');
            assert(rebate_percent <= max_bps.try_into().unwrap(), 'InvalidRebatePercent');

            let current_order_bps = order_data.current_bps;
            assert(
                settle_percent > 0 && settle_percent <= current_order_bps, 'InvalidSettlePercent',
            );
            order_data.current_bps -= settle_percent;

            // Save fields before consuming order_data (Order is not Copy)
            let order_token = order_data.token;
            let order_protocol_fee = order_data.protocol_fee;
            let order_sender_fee = order_data.sender_fee;
            let order_sender_fee_recipient = order_data.sender_fee_recipient;
            let order_amount = order_data.amount;
            let order_current_bps = order_data.current_bps;

            if order_current_bps == 0 {
                order_data.is_fulfilled = true;
            }

            let mut lp_amount = (order_amount * settle_percent.into()) / current_order_bps.into();
            order_data.amount -= lp_amount;

            self.order.entry(order_id).write(order_data);

            // Fee splitting (after state write, using saved fields)
            if order_current_bps == 0 {
                if order_sender_fee != 0 && order_protocol_fee != 0 {
                    // FX transfer — split sender fee
                    self
                        ._handle_fx_transfer_fee_splitting(
                            order_id, order_token, order_sender_fee_recipient, order_sender_fee,
                        );
                }
            }

            if order_sender_fee != 0 && order_protocol_fee == 0 {
                // Local transfer — split sender fee
                self
                    ._handle_local_transfer_fee_splitting(
                        order_id, liquidity_provider, order_sender_fee_recipient, settle_percent,
                    );
            }

            if order_protocol_fee != 0 {
                // FX transfer: use token-specific providerToAggregatorFx
                let settings = self.gateway_setting_manager.get_token_fee_settings(order_token);
                let mut aggregator_fee = (lp_amount * settings.provider_to_aggregator_fx.into()) / max_bps;
                lp_amount -= aggregator_fee;

                if rebate_percent != 0 {
                    let rebate_amount = (aggregator_fee * rebate_percent.into()) / max_bps;
                    aggregator_fee -= rebate_amount;
                    lp_amount += rebate_amount;
                }

                let treasury = self.gateway_setting_manager.get_treasury_address();
                let erc20 = IERC20Dispatcher { contract_address: order_token };
                erc20.transfer(treasury, aggregator_fee);
            }

            let erc20 = IERC20Dispatcher { contract_address: order_token };
            erc20.transfer(liquidity_provider, lp_amount);

            self
                .emit(
                    SettleOut {
                        split_order_id,
                        order_id,
                        liquidity_provider,
                        settle_percent,
                        rebate_percent,
                    },
                );

            true
        }

        fn settle_in(
            ref self: ContractState,
            order_id: felt252,
            token: ContractAddress,
            amount: u256,
            sender_fee_recipient: ContractAddress,
            sender_fee: u256,
            recipient: ContractAddress,
            rate: u128,
        ) -> bool {
            self.pausable.assert_not_paused();

            let existing_order = self.order.entry(order_id).read();
            assert(existing_order.sender.is_zero(), 'OrderAlreadyExists');

            let max_bps = self.gateway_setting_manager.get_max_bps();
            assert(amount > max_bps, 'InvalidAmount');

            self._handler(token, amount, recipient, sender_fee_recipient, sender_fee);

            let caller = get_caller_address();
            let this_contract = starknet::get_contract_address();
            let erc20 = IERC20Dispatcher { contract_address: token };
            erc20.transfer_from(caller, this_contract, amount + sender_fee);

            let mut amount_to_settle = amount;
            let mut aggregator_fee: u256 = 0;

            if rate == 100 {
                assert(sender_fee > 0, 'SenderFeeIsZero');
            } else {
                let settings = self.gateway_setting_manager.get_token_fee_settings(token);
                assert(settings.provider_to_aggregator_fx > 0, 'TokenFeeSettingsNotConfigured');

                aggregator_fee = (amount * settings.provider_to_aggregator_fx.into()) / max_bps;

                if aggregator_fee > 0 {
                    amount_to_settle -= aggregator_fee;
                    let treasury = self.gateway_setting_manager.get_treasury_address();
                    erc20.transfer(treasury, aggregator_fee);
                }
            }

            let new_order = Order {
                sender: recipient,
                token,
                sender_fee_recipient,
                sender_fee,
                protocol_fee: aggregator_fee,
                is_fulfilled: true,
                is_refunded: false,
                refund_address: caller,
                current_bps: 0,
                amount: amount_to_settle,
            };
            self.order.entry(order_id).write(new_order);

            erc20.transfer(recipient, amount_to_settle);

            // Handle fee splitting after order state is recorded
            if sender_fee != 0 {
                if aggregator_fee == 0 {
                    self
                        ._handle_local_transfer_fee_splitting(
                            order_id, caller, sender_fee_recipient, max_bps.try_into().unwrap(),
                        );
                } else {
                    self
                        ._handle_fx_transfer_fee_splitting(
                            order_id, token, sender_fee_recipient, sender_fee,
                        );
                }
            }

            self
                .emit(
                    SettleIn {
                        order_id,
                        liquidity_provider: caller,
                        recipient,
                        amount: amount_to_settle,
                        token,
                        aggregator_fee,
                        rate,
                    },
                );

            true
        }

        fn refund(ref self: ContractState, fee: u256, order_id: felt252) -> bool {
            self._assert_only_aggregator();

            let mut order_data = self.order.entry(order_id).read();

            assert(!order_data.is_fulfilled, 'OrderFulfilled');
            assert(!order_data.is_refunded, 'OrderRefunded');
            assert(order_data.protocol_fee >= fee, 'FeeExceedsProtocolFee');

            let erc20 = IERC20Dispatcher { contract_address: order_data.token };
            if fee > 0 {
                let treasury = self.gateway_setting_manager.get_treasury_address();
                erc20.transfer(treasury, fee);
            }

            order_data.is_refunded = true;
            order_data.current_bps = 0;

            let refund_amount = order_data.amount - fee;

            let total_refund = refund_amount + order_data.sender_fee;
            erc20.transfer(order_data.refund_address, total_refund);

            self.order.entry(order_id).write(order_data);

            self.emit(OrderRefunded { fee, order_id });

            true
        }

        fn is_token_supported(self: @ContractState, token: ContractAddress) -> bool {
            self.gateway_setting_manager.is_token_supported_internal(token)
        }

        fn get_order_info(self: @ContractState, order_id: felt252) -> Order {
            self.order.entry(order_id).read()
        }

        fn get_aggregator(self: @ContractState) -> ContractAddress {
            self.gateway_setting_manager.get_aggregator_address()
        }
    }

    // ##################################################################
    //                     INTERNAL FUNCTIONS
    // ##################################################################
    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        /// Internal function to handle order creation validation.
        fn _handler(
            self: @ContractState,
            token: ContractAddress,
            amount: u256,
            refund_address: ContractAddress,
            sender_fee_recipient: ContractAddress,
            sender_fee: u256,
        ) {
            assert(
                self.gateway_setting_manager.is_token_supported_internal(token),
                'TokenNotSupported',
            );
            assert(amount != 0, 'AmountIsZero');
            assert(!refund_address.is_zero(), 'ThrowZeroAddress');

            if sender_fee != 0 {
                assert(!sender_fee_recipient.is_zero(), 'InvalidSenderFeeRecipient');
            }
        }

        /// Modifier that allows only the aggregator to call a function.
        fn _assert_only_aggregator(self: @ContractState) {
            let caller = get_caller_address();
            let aggregator = self.gateway_setting_manager.get_aggregator_address();
            assert(caller == aggregator, 'OnlyAggregator');
        }

        /// Handles local transfer fee splitting between sender, provider, and aggregator.
        fn _handle_local_transfer_fee_splitting(
            ref self: ContractState,
            order_id: felt252,
            liquidity_provider: ContractAddress,
            sender_fee_recipient: ContractAddress,
            settle_percent: u64,
        ) {
            let order_data = self.order.entry(order_id).read();
            let settings = self.gateway_setting_manager.get_token_fee_settings(order_data.token);
            let max_bps = self.gateway_setting_manager.get_max_bps();
            let sender_fee = order_data.sender_fee;
            let token = order_data.token;

            let provider_amount = (sender_fee * settings.sender_to_provider.into()) / max_bps;
            let current_provider_amount = (provider_amount * settle_percent.into()) / max_bps;
            let aggregator_amount = (current_provider_amount * settings.provider_to_aggregator.into())
                / max_bps;
            let sender_amount = sender_fee - provider_amount;

            let erc20 = IERC20Dispatcher { contract_address: token };
            let treasury = self.gateway_setting_manager.get_treasury_address();

            if sender_amount != 0 && order_data.current_bps == 0 {
                erc20.transfer(sender_fee_recipient, sender_amount);
            }

            if aggregator_amount != 0 {
                erc20.transfer(treasury, aggregator_amount);
            }

            let lp_fee_amount = current_provider_amount - aggregator_amount;
            if lp_fee_amount != 0 {
                erc20.transfer(liquidity_provider, lp_fee_amount);
            }

            self
                .emit(
                    SenderFeeTransferred {
                        order_id, sender: sender_fee_recipient, amount: sender_amount,
                    },
                );
            self
                .emit(
                    LocalTransferFeeSplit {
                        order_id, sender_amount, provider_amount: lp_fee_amount, aggregator_amount,
                    },
                );
        }

        /// Handles FX transfer fee splitting between sender and aggregator.
        fn _handle_fx_transfer_fee_splitting(
            ref self: ContractState,
            order_id: felt252,
            token: ContractAddress,
            sender_fee_recipient: ContractAddress,
            sender_fee: u256,
        ) {
            let settings = self.gateway_setting_manager.get_token_fee_settings(token);
            let max_bps = self.gateway_setting_manager.get_max_bps();
            let treasury = self.gateway_setting_manager.get_treasury_address();

            let sender_amount = (sender_fee * (max_bps - settings.sender_to_aggregator.into())) / max_bps;
            let aggregator_amount = sender_fee - sender_amount;

            let erc20 = IERC20Dispatcher { contract_address: token };

            if sender_amount > 0 {
                erc20.transfer(sender_fee_recipient, sender_amount);
            }

            if aggregator_amount > 0 {
                erc20.transfer(treasury, aggregator_amount);
            }

            self
                .emit(
                    SenderFeeTransferred {
                        order_id, sender: sender_fee_recipient, amount: sender_amount,
                    },
                );
            self.emit(FxTransferFeeSplit { order_id, sender_amount, aggregator_amount });
        }
    }
}
