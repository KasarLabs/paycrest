use starknet::ContractAddress;

// ##################################################################
//                            EVENTS
// ##################################################################

/// Emitted when a deposit is made.
#[derive(Drop, starknet::Event)]
pub struct OrderCreated {
    #[key]
    pub sender: ContractAddress,
    #[key]
    pub token: ContractAddress,
    #[key]
    pub amount: u256,
    pub protocol_fee: u256,
    pub order_id: felt252,
    pub rate: u128,
    pub message_hash: ByteArray,
}

/// Emitted when an aggregator settles an offramp transaction.
#[derive(Drop, starknet::Event)]
pub struct SettleOut {
    pub split_order_id: felt252,
    #[key]
    pub order_id: felt252,
    #[key]
    pub liquidity_provider: ContractAddress,
    pub settle_percent: u64,
    pub rebate_percent: u64,
}

/// Emitted when an onramp order is successfully processed.
#[derive(Drop, starknet::Event)]
pub struct SettleIn {
    #[key]
    pub order_id: felt252,
    #[key]
    pub liquidity_provider: ContractAddress,
    #[key]
    pub recipient: ContractAddress,
    pub amount: u256,
    pub token: ContractAddress,
    pub aggregator_fee: u256,
    pub rate: u128,
}

/// Emitted when an aggregator refunds a transaction.
#[derive(Drop, starknet::Event)]
pub struct OrderRefunded {
    pub fee: u256,
    #[key]
    pub order_id: felt252,
}

/// Emitted when a local transfer fee is split.
#[derive(Drop, starknet::Event)]
pub struct LocalTransferFeeSplit {
    #[key]
    pub order_id: felt252,
    pub sender_amount: u256,
    pub provider_amount: u256,
    pub aggregator_amount: u256,
}

/// Emitted when an FX transfer fee is split.
#[derive(Drop, starknet::Event)]
pub struct FxTransferFeeSplit {
    #[key]
    pub order_id: felt252,
    pub sender_amount: u256,
    pub aggregator_amount: u256,
}

/// Emitted when the sender's fee is transferred.
#[derive(Drop, starknet::Event)]
pub struct SenderFeeTransferred {
    #[key]
    pub order_id: felt252,
    #[key]
    pub sender: ContractAddress,
    #[key]
    pub amount: u256,
}

// ##################################################################
//                            STRUCTS
// ##################################################################

/// Struct representing an order.
#[derive(Drop, Serde, starknet::Store)]
pub struct Order {
    pub sender: ContractAddress,
    pub token: ContractAddress,
    pub sender_fee_recipient: ContractAddress,
    pub sender_fee: u256,
    pub protocol_fee: u256,
    pub is_fulfilled: bool,
    pub is_refunded: bool,
    pub refund_address: ContractAddress,
    pub current_bps: u64,
    pub amount: u256,
}

/// Interface for the Gateway contract.
#[starknet::interface]
pub trait IGateway<TContractState> {
    // ##################################################################
    //                        EXTERNAL CALLS
    // ##################################################################

    /// Creates an order for the sender and returns the order id.
    fn create_order(
        ref self: TContractState,
        token: ContractAddress,
        amount: u256,
        rate: u128,
        sender_fee_recipient: ContractAddress,
        sender_fee: u256,
        refund_address: ContractAddress,
        message_hash: ByteArray,
    ) -> felt252;

    /// Settles an offramp transaction and distributes rewards accordingly.
    fn settle_out(
        ref self: TContractState,
        split_order_id: felt252,
        order_id: felt252,
        liquidity_provider: ContractAddress,
        settle_percent: u64,
        rebate_percent: u64,
    ) -> bool;

    /// Processes an onramp settlement. Open to any caller.
    fn settle_in(
        ref self: TContractState,
        order_id: felt252,
        token: ContractAddress,
        amount: u256,
        sender_fee_recipient: ContractAddress,
        sender_fee: u256,
        recipient: ContractAddress,
        rate: u128,
    ) -> bool;

    /// Refunds to the specified refundable address.
    fn refund(ref self: TContractState, fee: u256, order_id: felt252) -> bool;

    /// Checks if a token is supported by Gateway.
    fn is_token_supported(self: @TContractState, token: ContractAddress) -> bool;

    /// Gets the details of an order.
    fn get_order_info(self: @TContractState, order_id: felt252) -> Order;

    /// Gets the address of the aggregator.
    fn get_aggregator(self: @TContractState) -> ContractAddress;
}
