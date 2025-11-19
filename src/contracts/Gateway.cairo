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
        OrderSettled, SenderFeeTransferred,
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
        OrderSettled: OrderSettled,
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

            let protocol_fee = if rate == 100 {
                // Local transfer (rate = 1 or 100 for percentage representation)
                assert(sender_fee > 0, 'SenderFeeIsZero');
                0
            } else {
                // FX transfer - use token-specific providerToAggregatorFx
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

        fn settle(
            ref self: ContractState,
            split_order_id: felt252,
            order_id: felt252,
            liquidity_provider: ContractAddress,
            settle_percent: u64,
            rebate_percent: u64,
        ) -> bool {
            self._assert_only_aggregator();

            let mut order_data = self.order.entry(order_id).read();

            assert(!order_data.is_fulfilled, 'OrderFulfilled');
            assert(!order_data.is_refunded, 'OrderRefunded');

            let max_bps = self.gateway_setting_manager.get_max_bps();
            assert(rebate_percent <= max_bps.try_into().unwrap(), 'InvalidRebatePercent');

            let current_order_bps = order_data.current_bps;
            assert(
                settle_percent > 0 && settle_percent <= current_order_bps, 'InvalidSettlePercent',
            );

            order_data.current_bps -= settle_percent;

            if order_data.current_bps == 0 {
                order_data.is_fulfilled = true;

                if order_data.sender_fee != 0 && order_data.protocol_fee != 0 {
                    // FX transfer - sender keeps all fee
                    self._handle_fx_transfer_fee_splitting(order_id);
                }
            }

            if order_data.sender_fee != 0 && order_data.protocol_fee == 0 {
                // Local transfer - split sender fee
                self
                    ._handle_local_transfer_fee_splitting(
                        order_id, liquidity_provider, settle_percent,
                    );
            }

            let mut liquidity_provider_amount = (order_data.amount * settle_percent.into())
                / current_order_bps.into();
            order_data.amount -= liquidity_provider_amount;

            if order_data.protocol_fee != 0 {
                // FX transfer - use token-specific providerToAggregatorFx
                let settings = self
                    .gateway_setting_manager
                    .get_token_fee_settings(order_data.token);
                let mut protocol_fee = (liquidity_provider_amount
                    * settings.provider_to_aggregator_fx.into())
                    / max_bps;
                liquidity_provider_amount -= protocol_fee;

                if rebate_percent != 0 {
                    // Calculate rebate amount
                    let rebate_amount = (protocol_fee * rebate_percent.into()) / max_bps;
                    protocol_fee -= rebate_amount;
                    liquidity_provider_amount += rebate_amount;
                }

                // Transfer protocol fee to treasury
                let erc20 = IERC20Dispatcher { contract_address: order_data.token };
                let treasury = self.gateway_setting_manager.get_treasury_address();
                erc20.transfer(treasury, protocol_fee);
            }

            // Transfer to liquidity provider
            let erc20 = IERC20Dispatcher { contract_address: order_data.token };
            erc20.transfer(liquidity_provider, liquidity_provider_amount);

            self.order.entry(order_id).write(order_data);

            self
                .emit(
                    OrderSettled {
                        split_order_id,
                        order_id,
                        liquidity_provider,
                        settle_percent,
                        rebate_percent,
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

            if fee > 0 {
                let erc20 = IERC20Dispatcher { contract_address: order_data.token };
                let treasury = self.gateway_setting_manager.get_treasury_address();
                erc20.transfer(treasury, fee);
            }

            order_data.is_refunded = true;
            order_data.current_bps = 0;

            let refund_amount = order_data.amount - fee;

            let erc20 = IERC20Dispatcher { contract_address: order_data.token };
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

        /// Handles fee splitting for local transfers (rate = 100).
        fn _handle_local_transfer_fee_splitting(
            ref self: ContractState,
            order_id: felt252,
            liquidity_provider: ContractAddress,
            settle_percent: u64,
        ) {
            let mut order_data = self.order.entry(order_id).read();
            let settings = self.gateway_setting_manager.get_token_fee_settings(order_data.token);
            let sender_fee = order_data.sender_fee;
            let max_bps = self.gateway_setting_manager.get_max_bps();

            // Calculate splits based on config
            let provider_amount = (sender_fee * settings.sender_to_provider.into()) / max_bps;
            let current_provider_amount = (provider_amount * settle_percent.into()) / max_bps;
            let aggregator_amount = (current_provider_amount
                * settings.provider_to_aggregator.into())
                / max_bps;
            let sender_amount = sender_fee - provider_amount;

            let erc20 = IERC20Dispatcher { contract_address: order_data.token };
            let treasury = self.gateway_setting_manager.get_treasury_address();

            // Transfer sender portion
            if sender_amount != 0 && order_data.current_bps == 0 {
                erc20.transfer(order_data.sender_fee_recipient, sender_amount);
            }

            // Transfer aggregator portion to treasury
            if aggregator_amount != 0 {
                erc20.transfer(treasury, aggregator_amount);
            }

            // Transfer provider portion to the liquidity provider who fulfilled the order
            let final_provider_amount = current_provider_amount - aggregator_amount;
            if final_provider_amount != 0 {
                erc20.transfer(liquidity_provider, final_provider_amount);
            }

            // Emit events
            self
                .emit(
                    SenderFeeTransferred {
                        sender: order_data.sender_fee_recipient, amount: sender_amount,
                    },
                );
            self
                .emit(
                    LocalTransferFeeSplit {
                        order_id,
                        sender_amount,
                        provider_amount: final_provider_amount,
                        aggregator_amount,
                    },
                );
        }

        /// Handles fee splitting for FX transfers (rate != 100).
        fn _handle_fx_transfer_fee_splitting(ref self: ContractState, order_id: felt252) {
            let order_data = self.order.entry(order_id).read();
            let settings = self.gateway_setting_manager.get_token_fee_settings(order_data.token);
            let sender_fee = order_data.sender_fee;
            let max_bps = self.gateway_setting_manager.get_max_bps();

            // Calculate sender portion based on senderToAggregator setting
            let sender_amount = (sender_fee * (max_bps - settings.sender_to_aggregator.into()))
                / max_bps;
            let aggregator_amount = sender_fee - sender_amount;

            let erc20 = IERC20Dispatcher { contract_address: order_data.token };
            let treasury = self.gateway_setting_manager.get_treasury_address();

            // Transfer sender portion
            if sender_amount > 0 {
                erc20.transfer(order_data.sender_fee_recipient, sender_amount);
            }

            // Transfer aggregator portion to treasury
            if aggregator_amount > 0 {
                erc20.transfer(treasury, aggregator_amount);
            }

            // Emit events
            self
                .emit(
                    SenderFeeTransferred {
                        sender: order_data.sender_fee_recipient, amount: sender_amount,
                    },
                );
            self.emit(FxTransferFeeSplit { order_id, sender_amount, aggregator_amount });
        }
    }
}

