use openzeppelin_token::erc20::interface::ERC20ABIDispatcherTrait;
use paycrest::contracts::GatewaySettingManager::IGatewaySettingManagerDispatcherTrait;
use paycrest::interfaces::IGateway::IGatewayDispatcherTrait;
use snforge_std::{
    DeclareResultTrait, declare, map_entry_address, start_cheat_caller_address,
    stop_cheat_caller_address, store,
};
use starknet::ContractAddress;
use crate::test_utils::{
    AGGREGATOR_ADDRESS, DEFAULT_AMOUNT, DEFAULT_FEE, LIQUIDITY_PROVIDER_ADDRESS, MAX_BPS,
    OWNER_ADDRESS, REFUND_ADDRESS, SENDER_ADDRESS, SENDER_FEE_RECIPIENT_ADDRESS, TREASURY_ADDRESS,
    setup_complete, setup_erc20, setup_gateway, setup_token_support,
};

#[starknet::interface]
trait IPausable<TContractState> {
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
}

// ##################################################################
//                    CONSTRUCTOR TESTS
// ##################################################################
#[test]
fn test_constructor() {
    let (_gateway_address, _gateway_dispatcher, _) = setup_gateway();
    // Constructor initializes MAX_BPS to 100_000 internally
// Ownership is set correctly (tested via other owner functions)
}

// ##################################################################
//                    OWNER FUNCTIONS TESTS
// ##################################################################

#[test]
fn test_update_treasury_address() {
    let (gateway_address, _, setting_manager) = setup_gateway();

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    setting_manager.update_protocol_address('treasury', TREASURY_ADDRESS());
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('Gateway: zero address',))]
fn test_update_treasury_zero_address() {
    let (gateway_address, _, setting_manager) = setup_gateway();
    let zero_address: starknet::ContractAddress = 0.try_into().unwrap();

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    setting_manager.update_protocol_address('treasury', zero_address);
    stop_cheat_caller_address(gateway_address);
}

#[test]
fn test_setting_manager_bool_token_support() {
    let (gateway_address, gateway_dispatcher, setting_manager) = setup_gateway();
    let (token_address, _) = setup_erc20();

    // Enable token support
    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    setting_manager.setting_manager_bool('token', token_address, 1);
    stop_cheat_caller_address(gateway_address);

    assert(gateway_dispatcher.is_token_supported(token_address), 'Token should be supported');

    // Disable token support
    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    setting_manager.setting_manager_bool('token', token_address, 2);
    stop_cheat_caller_address(gateway_address);

    assert(!gateway_dispatcher.is_token_supported(token_address), 'Token should not be supported');
}

#[test]
#[should_panic(expected: ('Gateway: invalid status',))]
fn test_setting_manager_bool_invalid_status() {
    let (gateway_address, _, setting_manager) = setup_gateway();
    let (token_address, _) = setup_erc20();

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    setting_manager.setting_manager_bool('token', token_address, 3); // Invalid status
    stop_cheat_caller_address(gateway_address);
}

// ##################################################################
//                    PAUSE/UNPAUSE TESTS
// ##################################################################

#[test]
fn test_pause_by_owner() {
    let (gateway_address, _, _) = setup_gateway();
    let pausable_dispatcher = IPausableDispatcher { contract_address: gateway_address };

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    pausable_dispatcher.pause();
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_pause_not_owner() {
    let (gateway_address, _, _) = setup_gateway();
    let pausable_dispatcher = IPausableDispatcher { contract_address: gateway_address };

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    pausable_dispatcher.pause();
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_create_order_when_paused() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();
    let pausable_dispatcher = IPausableDispatcher { contract_address: gateway_address };

    // Mint and approve tokens
    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    pausable_dispatcher.pause();
    stop_cheat_caller_address(gateway_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test_message_hash",
        );
    stop_cheat_caller_address(gateway_address);
}

#[test]
fn test_unpause_by_owner() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();
    let pausable_dispatcher = IPausableDispatcher { contract_address: gateway_address };

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    pausable_dispatcher.pause();
    stop_cheat_caller_address(gateway_address);

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    pausable_dispatcher.unpause();
    stop_cheat_caller_address(gateway_address);

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    assert(order_id != 0, 'Order should be created');
}

// ##################################################################
//                    CREATE ORDER TESTS
// ##################################################################
#[test]
fn test_create_order_success() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100, // rate
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test_message_hash",
        );
    stop_cheat_caller_address(gateway_address);

    // Verify order was created
    assert(order_id != 0, 'Order ID should not be zero');

    // Get order info
    let order = gateway_dispatcher.get_order_info(order_id);
    assert(order.sender == SENDER_ADDRESS(), 'Wrong sender');
    assert(order.token == token_address, 'Wrong token');
    assert(order.amount == DEFAULT_AMOUNT, 'Wrong amount');
    assert(order.sender_fee == DEFAULT_FEE, 'Wrong sender fee');
    assert(order.refund_address == REFUND_ADDRESS(), 'Wrong refund address');
    assert(!order.is_fulfilled, 'Should not be fulfilled');
    assert(!order.is_refunded, 'Should not be refunded');
    assert(order.current_bps == MAX_BPS.try_into().unwrap(), 'Wrong current BPS');
}

#[test]
#[should_panic(expected: ('TokenNotSupported',))]
fn test_create_order_token_not_supported() {
    let (gateway_address, gateway_dispatcher, _, _, _) = setup_complete();
    let unsupported_token: starknet::ContractAddress = 'unsupported'.try_into().unwrap();

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    gateway_dispatcher
        .create_order(
            unsupported_token,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('AmountIsZero',))]
fn test_create_order_zero_amount() {
    let (gateway_address, gateway_dispatcher, _, token_address, _) = setup_complete();

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    gateway_dispatcher
        .create_order(
            token_address,
            0,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('ThrowZeroAddress',))]
fn test_create_order_zero_refund_address() {
    let (gateway_address, gateway_dispatcher, _, token_address, _) = setup_complete();
    let zero_address: starknet::ContractAddress = 0.try_into().unwrap();

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            zero_address,
            "test",
        );
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('InvalidSenderFeeRecipient',))]
fn test_create_order_invalid_sender_fee_recipient() {
    let (gateway_address, gateway_dispatcher, _, token_address, _) = setup_complete();
    let zero_address: starknet::ContractAddress = 0.try_into().unwrap();

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    gateway_dispatcher
        .create_order(
            token_address, DEFAULT_AMOUNT, 100, zero_address, DEFAULT_FEE, REFUND_ADDRESS(), "test",
        );
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('InvalidMessageHash',))]
fn test_create_order_empty_message_hash() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "" // Empty message hash
        );
    stop_cheat_caller_address(gateway_address);
}

// ##################################################################
//                    ESCROW & NONCE TESTS
// ##################################################################

#[test]
fn test_escrow_holds_tokens() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;

    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    let initial_gateway_balance = token_dispatcher.balance_of(gateway_address);
    let initial_user_balance = token_dispatcher.balance_of(SENDER_ADDRESS());

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    let final_gateway_balance = token_dispatcher.balance_of(gateway_address);
    let final_user_balance = token_dispatcher.balance_of(SENDER_ADDRESS());

    assert(
        final_gateway_balance == initial_gateway_balance + total_amount,
        'Gateway didnt receive tokens',
    );
    assert(final_user_balance == initial_user_balance - total_amount, 'User didnt pay tokens');
    assert(order_id != 0, 'Order ID should not be zero');
}

#[test]
fn test_nonce_increment() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;

    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![(total_amount * 3).low.into(), (total_amount * 3).high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount * 3);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id_1 = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test_1",
        );
    stop_cheat_caller_address(gateway_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id_2 = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test_2",
        );
    stop_cheat_caller_address(gateway_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id_3 = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test_3",
        );
    stop_cheat_caller_address(gateway_address);

    assert(order_id_1 != order_id_2, 'Order IDs 1&2 must differ');
    assert(order_id_2 != order_id_3, 'Order IDs 2&3 must differ');
    assert(order_id_1 != order_id_3, 'Order IDs 1&3 must differ');

    let order_1 = gateway_dispatcher.get_order_info(order_id_1);
    let order_2 = gateway_dispatcher.get_order_info(order_id_2);
    let order_3 = gateway_dispatcher.get_order_info(order_id_3);

    assert(order_1.sender == SENDER_ADDRESS(), 'Order 1 wrong sender');
    assert(order_2.sender == SENDER_ADDRESS(), 'Order 2 wrong sender');
    assert(order_3.sender == SENDER_ADDRESS(), 'Order 3 wrong sender');
}

#[test]
fn test_different_users_different_order_ids() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    let user_2: ContractAddress = 'user_2'.try_into().unwrap();

    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![user_2.into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id_user_1 = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test_user_1",
        );
    stop_cheat_caller_address(gateway_address);

    start_cheat_caller_address(token_address, user_2);
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, user_2);
    let order_id_user_2 = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test_user_2",
        );
    stop_cheat_caller_address(gateway_address);

    assert(order_id_user_1 != order_id_user_2, 'Order IDs must differ');

    let order_1 = gateway_dispatcher.get_order_info(order_id_user_1);
    let order_2 = gateway_dispatcher.get_order_info(order_id_user_2);

    assert(order_1.sender == SENDER_ADDRESS(), 'Order 1 wrong sender');
    assert(order_2.sender == user_2, 'Order 2 wrong sender');
}

// ##################################################################
//                    SETTLE TESTS
// ##################################################################
#[test]
fn test_settle_order_full() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    let split_order_id: felt252 = 'split_123';
    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    let result = gateway_dispatcher
        .settle(
            split_order_id,
            order_id,
            LIQUIDITY_PROVIDER_ADDRESS(),
            MAX_BPS.try_into().unwrap(),
            0 // rebate_percent
        );
    stop_cheat_caller_address(gateway_address);

    assert(result, 'Settle should succeed');

    let order = gateway_dispatcher.get_order_info(order_id);
    assert(order.is_fulfilled, 'Order should be fulfilled');
    assert(order.current_bps == 0, 'Current BPS should be 0');
}

#[test]
fn test_settle_order_partial() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    let half_bps: u64 = (MAX_BPS / 2).try_into().unwrap();
    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    gateway_dispatcher.settle('split_1', order_id, LIQUIDITY_PROVIDER_ADDRESS(), half_bps, 0);
    stop_cheat_caller_address(gateway_address);

    let order = gateway_dispatcher.get_order_info(order_id);
    assert(!order.is_fulfilled, 'Order should not be fulfilled');
    assert(order.current_bps == half_bps, 'Current BPS should be half');
}

#[test]
#[should_panic(expected: ('OnlyAggregator',))]
fn test_settle_not_aggregator() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    gateway_dispatcher
        .settle('split_1', order_id, LIQUIDITY_PROVIDER_ADDRESS(), MAX_BPS.try_into().unwrap(), 0);
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('OrderFulfilled',))]
fn test_settle_already_fulfilled() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    gateway_dispatcher
        .settle('split_1', order_id, LIQUIDITY_PROVIDER_ADDRESS(), MAX_BPS.try_into().unwrap(), 0);
    stop_cheat_caller_address(gateway_address);

    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    gateway_dispatcher
        .settle('split_2', order_id, LIQUIDITY_PROVIDER_ADDRESS(), MAX_BPS.try_into().unwrap(), 0);
    stop_cheat_caller_address(gateway_address);
}

// ##################################################################
//                    BPS ARITHMETIC TESTS
// ##################################################################

/// Test multiple partial settlements adding up to 100%
#[test]
fn test_multiple_settlements_complete_order() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    let bps_30: u64 = 30_000; // Settle 30%
    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    gateway_dispatcher.settle('split_1', order_id, LIQUIDITY_PROVIDER_ADDRESS(), bps_30, 0);
    stop_cheat_caller_address(gateway_address);

    let order = gateway_dispatcher.get_order_info(order_id);
    assert(!order.is_fulfilled, 'Should not be fulfilled yet');
    assert(order.current_bps == MAX_BPS.try_into().unwrap() - bps_30, 'Wrong BPS after 30%');

    let bps_40: u64 = 40_000; // Settle another 40%
    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    gateway_dispatcher.settle('split_2', order_id, LIQUIDITY_PROVIDER_ADDRESS(), bps_40, 0);
    stop_cheat_caller_address(gateway_address);

    let order = gateway_dispatcher.get_order_info(order_id);
    assert(!order.is_fulfilled, 'Should not be fulfilled yet');
    assert(
        order.current_bps == MAX_BPS.try_into().unwrap() - bps_30 - bps_40, 'Wrong BPS after 70%',
    );

    let bps_30_final: u64 = 30_000; // Settle final 30% to complete
    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    gateway_dispatcher.settle('split_3', order_id, LIQUIDITY_PROVIDER_ADDRESS(), bps_30_final, 0);
    stop_cheat_caller_address(gateway_address);

    // Verify order is fulfilled
    let order = gateway_dispatcher.get_order_info(order_id);
    assert(order.is_fulfilled, 'Should be fulfilled');
    assert(order.current_bps == 0, 'BPS should be 0');
}

#[test]
fn test_bps_arithmetic_precision() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    let bps_25: u64 = 25_000; // Settle 25%

    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    gateway_dispatcher.settle('split_1', order_id, LIQUIDITY_PROVIDER_ADDRESS(), bps_25, 0);
    stop_cheat_caller_address(gateway_address);

    let order = gateway_dispatcher.get_order_info(order_id);
    assert(order.current_bps == 75_000, 'BPS after 1st 25% wrong');

    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    gateway_dispatcher.settle('split_2', order_id, LIQUIDITY_PROVIDER_ADDRESS(), bps_25, 0);
    stop_cheat_caller_address(gateway_address);

    let order = gateway_dispatcher.get_order_info(order_id);
    assert(order.current_bps == 50_000, 'BPS after 2nd 25% wrong');

    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    gateway_dispatcher.settle('split_3', order_id, LIQUIDITY_PROVIDER_ADDRESS(), bps_25, 0);
    stop_cheat_caller_address(gateway_address);

    let order = gateway_dispatcher.get_order_info(order_id);
    assert(order.current_bps == 25_000, 'BPS after 3rd 25% wrong');

    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    gateway_dispatcher.settle('split_4', order_id, LIQUIDITY_PROVIDER_ADDRESS(), bps_25, 0);
    stop_cheat_caller_address(gateway_address);

    let order = gateway_dispatcher.get_order_info(order_id);
    assert(order.is_fulfilled, 'Order should be fulfilled');
    assert(order.current_bps == 0, 'BPS should be 0');
}

// ##################################################################
//                    REFUND TESTS
// ##################################################################
#[test]
fn test_refund_order_no_fee() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    let result = gateway_dispatcher.refund(0, order_id);
    stop_cheat_caller_address(gateway_address);

    assert(result, 'Refund should succeed');

    let order = gateway_dispatcher.get_order_info(order_id);
    assert(order.is_refunded, 'Order should be refunded');
    assert(order.current_bps == 0, 'Current BPS should be 0');
}

#[test]
fn test_refund_order_with_fee() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            150, // FX transfer rate (not 100), so protocol_fee will be calculated
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    let refund_fee: u256 = 100; // Fee should be <= protocol_fee
    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    let result = gateway_dispatcher.refund(refund_fee, order_id);
    stop_cheat_caller_address(gateway_address);

    assert(result, 'Refund should succeed');

    let order = gateway_dispatcher.get_order_info(order_id);
    assert(order.is_refunded, 'Order should be refunded');
}

#[test]
#[should_panic(expected: ('OnlyAggregator',))]
fn test_refund_not_aggregator() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    gateway_dispatcher.refund(0, order_id);
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('OrderRefunded',))]
fn test_refund_already_refunded() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    gateway_dispatcher.refund(0, order_id);
    stop_cheat_caller_address(gateway_address);

    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    gateway_dispatcher.refund(0, order_id);
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('FeeExceedsProtocolFee',))]
fn test_refund_fee_exceeds_protocol_fee() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            100,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    let excessive_fee = DEFAULT_AMOUNT * 2; // Way more than protocol fee
    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    gateway_dispatcher.refund(excessive_fee, order_id);
    stop_cheat_caller_address(gateway_address);
}

// ##################################################################
//                    VIEW FUNCTIONS TESTS
// ##################################################################
#[test]
fn test_is_token_supported() {
    let (gateway_address, gateway_dispatcher, setting_manager) = setup_gateway();
    let (token_address, _) = setup_erc20();

    assert(!gateway_dispatcher.is_token_supported(token_address), 'Should not be supported');

    // Enable token support
    setup_token_support(gateway_address, setting_manager, token_address);

    // Token should be supported now
    assert(gateway_dispatcher.is_token_supported(token_address), 'Should be supported');
}

#[test]
fn test_get_order_info_nonexistent() {
    let (_, gateway_dispatcher, _) = setup_gateway();

    let fake_order_id: felt252 = 'nonexistent';
    let order = gateway_dispatcher.get_order_info(fake_order_id);

    // Should return empty order
    let zero_address: starknet::ContractAddress = 0.try_into().unwrap();
    assert(order.sender == zero_address, 'Sender should be zero');
}

// ##################################################################
//                    UPGRADEABILITY TESTS
// ##################################################################

#[starknet::interface]
trait IUpgradeable<TContractState> {
    fn upgrade(ref self: TContractState, new_class_hash: starknet::ClassHash);
}

#[starknet::interface]
trait IOwnableTwoStep<TContractState> {
    fn owner(self: @TContractState) -> ContractAddress;
    fn pending_owner(self: @TContractState) -> ContractAddress;
    fn accept_ownership(ref self: TContractState);
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);
    fn renounce_ownership(ref self: TContractState);
}

#[test]
fn test_upgrade_by_owner() {
    let (gateway_address, _, _) = setup_gateway();

    let contract_class = declare("Gateway").unwrap().contract_class();
    let new_class_hash = *contract_class.class_hash;
    let upgradeable_dispatcher = IUpgradeableDispatcher { contract_address: gateway_address };

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    upgradeable_dispatcher.upgrade(new_class_hash);
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_upgrade_not_owner() {
    let (gateway_address, _, _) = setup_gateway();

    let contract_class = declare("Gateway").unwrap().contract_class();
    let new_class_hash = *contract_class.class_hash;
    let upgradeable_dispatcher = IUpgradeableDispatcher { contract_address: gateway_address };

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    upgradeable_dispatcher.upgrade(new_class_hash);
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('Class hash cannot be zero',))]
fn test_upgrade_zero_class_hash() {
    let (gateway_address, _, _) = setup_gateway();
    let zero_class_hash: starknet::ClassHash = 0.try_into().unwrap();
    let upgradeable_dispatcher = IUpgradeableDispatcher { contract_address: gateway_address };

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    upgradeable_dispatcher.upgrade(zero_class_hash);
    stop_cheat_caller_address(gateway_address);
}

// ##################################################################
//                    TWO-STEP OWNERSHIP TESTS
// ##################################################################

#[test]
fn test_two_step_transfer_ownership() {
    let (gateway_address, _, _) = setup_gateway();
    let ownable_dispatcher = IOwnableTwoStepDispatcher { contract_address: gateway_address };

    let new_owner: ContractAddress = 0x999.try_into().unwrap();
    let zero_address: ContractAddress = 0.try_into().unwrap();

    assert(ownable_dispatcher.owner() == OWNER_ADDRESS(), 'Initial owner incorrect');
    assert(ownable_dispatcher.pending_owner() == zero_address, 'Pending owner should be zero');

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    ownable_dispatcher.transfer_ownership(new_owner);
    stop_cheat_caller_address(gateway_address);

    assert(ownable_dispatcher.owner() == OWNER_ADDRESS(), 'Owner should not change yet');
    assert(ownable_dispatcher.pending_owner() == new_owner, 'Pending owner incorrect');

    start_cheat_caller_address(gateway_address, new_owner);
    ownable_dispatcher.accept_ownership();
    stop_cheat_caller_address(gateway_address);

    assert(ownable_dispatcher.owner() == new_owner, 'New owner not set');
    assert(ownable_dispatcher.pending_owner() == zero_address, 'Pending owner should be zero');
}

#[test]
fn test_pending_owner_getter() {
    let (gateway_address, _, _) = setup_gateway();
    let ownable_dispatcher = IOwnableTwoStepDispatcher { contract_address: gateway_address };

    let new_owner: ContractAddress = 0x888.try_into().unwrap();
    let zero_address: ContractAddress = 0.try_into().unwrap();

    assert(ownable_dispatcher.pending_owner() == zero_address, 'Pending owner should be zero');

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    ownable_dispatcher.transfer_ownership(new_owner);
    stop_cheat_caller_address(gateway_address);

    assert(ownable_dispatcher.pending_owner() == new_owner, 'Pending owner not set');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_transfer_ownership_not_owner() {
    let (gateway_address, _, _) = setup_gateway();
    let ownable_dispatcher = IOwnableTwoStepDispatcher { contract_address: gateway_address };

    let new_owner: ContractAddress = 0x777.try_into().unwrap();

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    ownable_dispatcher.transfer_ownership(new_owner);
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('Caller is not the pending owner',))]
fn test_accept_ownership_not_pending_owner() {
    let (gateway_address, _, _) = setup_gateway();
    let ownable_dispatcher = IOwnableTwoStepDispatcher { contract_address: gateway_address };

    let new_owner: ContractAddress = 0x666.try_into().unwrap();
    let wrong_caller: ContractAddress = 0x555.try_into().unwrap();

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    ownable_dispatcher.transfer_ownership(new_owner);
    stop_cheat_caller_address(gateway_address);

    start_cheat_caller_address(gateway_address, wrong_caller);
    ownable_dispatcher.accept_ownership();
    stop_cheat_caller_address(gateway_address);
}

#[test]
fn test_cancel_ownership_transfer() {
    let (gateway_address, _, _) = setup_gateway();
    let ownable_dispatcher = IOwnableTwoStepDispatcher { contract_address: gateway_address };

    let new_owner: ContractAddress = 0x444.try_into().unwrap();
    let zero_address: ContractAddress = 0.try_into().unwrap();

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    ownable_dispatcher.transfer_ownership(new_owner);
    stop_cheat_caller_address(gateway_address);

    assert(ownable_dispatcher.pending_owner() == new_owner, 'Pending owner not set');

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    ownable_dispatcher.transfer_ownership(zero_address);
    stop_cheat_caller_address(gateway_address);

    assert(ownable_dispatcher.pending_owner() == zero_address, 'Pending owner not cancelled');
    assert(ownable_dispatcher.owner() == OWNER_ADDRESS(), 'Owner should not change');
}

#[test]
fn test_renounce_ownership_two_step() {
    let (gateway_address, _, _) = setup_gateway();
    let ownable_dispatcher = IOwnableTwoStepDispatcher { contract_address: gateway_address };

    let zero_address: ContractAddress = 0.try_into().unwrap();

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    ownable_dispatcher.renounce_ownership();
    stop_cheat_caller_address(gateway_address);

    assert(ownable_dispatcher.owner() == zero_address, 'Owner not renounced');
}

#[test]
fn test_ownership_functions_after_two_step_transfer() {
    let (gateway_address, _, setting_manager) = setup_gateway();
    let ownable_dispatcher = IOwnableTwoStepDispatcher { contract_address: gateway_address };

    let new_owner: ContractAddress = 0x333.try_into().unwrap();

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    ownable_dispatcher.transfer_ownership(new_owner);
    stop_cheat_caller_address(gateway_address);

    start_cheat_caller_address(gateway_address, new_owner);
    ownable_dispatcher.accept_ownership();
    stop_cheat_caller_address(gateway_address);

    // Test that new owner can perform owner functions
    start_cheat_caller_address(gateway_address, new_owner);
    setting_manager.update_protocol_address('treasury', TREASURY_ADDRESS());
    stop_cheat_caller_address(gateway_address);
}

// ##################################################################
//                    TOKEN FEE SETTINGS TESTS
// ##################################################################

#[test]
fn test_set_token_fee_settings() {
    let (gateway_address, _, setting_manager, token_address, _) = setup_complete();

    // Set new token fee settings
    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    setting_manager.set_token_fee_settings(token_address, 90_000, 15_000, 25_000, 1000);
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('Gateway: token not supported',))]
fn test_set_token_fee_settings_unsupported_token() {
    let (gateway_address, _, setting_manager, _, _) = setup_complete();
    let unsupported_token: ContractAddress = 'unsupported'.try_into().unwrap();

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    setting_manager.set_token_fee_settings(unsupported_token, 90_000, 15_000, 25_000, 1000);
    stop_cheat_caller_address(gateway_address);
}

#[test]
#[should_panic(expected: ('Invalid sender_to_provider',))]
fn test_set_token_fee_settings_invalid_values() {
    let (gateway_address, _, setting_manager, token_address, _) = setup_complete();

    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    setting_manager
        .set_token_fee_settings(token_address, 200_000, // Exceeds MAX_BPS
        15_000, 25_000, 1000);
    stop_cheat_caller_address(gateway_address);
}

// ##################################################################
//                    REBATE FUNCTIONALITY TESTS
// ##################################################################

#[test]
fn test_settle_with_rebate() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create FX order (rate != 100)
    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            150,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    // Settle with 50% rebate
    let rebate_percent: u64 = 50_000;
    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    let result = gateway_dispatcher
        .settle(
            'split_1',
            order_id,
            LIQUIDITY_PROVIDER_ADDRESS(),
            MAX_BPS.try_into().unwrap(),
            rebate_percent,
        );
    stop_cheat_caller_address(gateway_address);

    assert(result, 'Settle should succeed');
}

#[test]
#[should_panic(expected: ('InvalidRebatePercent',))]
fn test_settle_with_invalid_rebate() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;
    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            150,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    // Try to settle with rebate > MAX_BPS
    start_cheat_caller_address(gateway_address, AGGREGATOR_ADDRESS());
    gateway_dispatcher
        .settle(
            'split_1', order_id, LIQUIDITY_PROVIDER_ADDRESS(), MAX_BPS.try_into().unwrap(), 150_000,
        );
    stop_cheat_caller_address(gateway_address);
}

// ##################################################################
//                    RATE TYPE VALIDATION TESTS
// ##################################################################

#[test]
fn test_create_order_with_max_u128_rate() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let max_u128_rate: u128 = 340282366920938463463374607431768211455;
    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;

    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            max_u128_rate,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    let order = gateway_dispatcher.get_order_info(order_id);
    assert(order.amount == DEFAULT_AMOUNT, 'Order amount incorrect');
}

#[test]
fn test_create_order_with_u96_compatible_rate() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let u96_max_rate: u128 = 79228162514264337593543950335;
    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;

    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    let order_id = gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            u96_max_rate,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);

    let order = gateway_dispatcher.get_order_info(order_id);
    assert(order.amount == DEFAULT_AMOUNT, 'Order amount incorrect');
}

#[test]
fn test_rate_type_size_validation() {
    let (gateway_address, gateway_dispatcher, _, token_address, token_dispatcher) =
        setup_complete();

    let typical_rate: u128 = 1500000;
    let total_amount = DEFAULT_AMOUNT + DEFAULT_FEE;

    store(
        token_address,
        map_entry_address(selector!("ERC20_balances"), array![SENDER_ADDRESS().into()].span()),
        array![total_amount.low.into(), total_amount.high.into()].span(),
    );

    start_cheat_caller_address(token_address, SENDER_ADDRESS());
    token_dispatcher.approve(gateway_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(gateway_address, SENDER_ADDRESS());
    gateway_dispatcher
        .create_order(
            token_address,
            DEFAULT_AMOUNT,
            typical_rate,
            SENDER_FEE_RECIPIENT_ADDRESS(),
            DEFAULT_FEE,
            REFUND_ADDRESS(),
            "test",
        );
    stop_cheat_caller_address(gateway_address);
}

