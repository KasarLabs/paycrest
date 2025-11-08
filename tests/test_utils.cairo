use core::traits::TryInto;
use openzeppelin_token::erc20::interface::ERC20ABIDispatcher;
use paycrest::contracts::GatewaySettingManager::{
    IGatewaySettingManagerDispatcher, IGatewaySettingManagerDispatcherTrait,
};
use paycrest::interfaces::IGateway::IGatewayDispatcher;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;


// ##################################################################
//                        CONSTANTS
// ##################################################################
pub const ONE_ETH: u128 = 1_000_000_000_000_000_000;
pub const DEFAULT_AMOUNT: u256 = 1_000_000_000_000_000_000; // 1 ETH
pub const DEFAULT_FEE: u256 = 10_000_000_000_000_000; // 0.01 ETH
pub const MAX_BPS: u256 = 100_000;
pub const PROTOCOL_FEE_PERCENT: u64 = 500; // 0.5%

// ##################################################################
//                        ADDRESSES
// ##################################################################
pub fn OWNER_ADDRESS() -> ContractAddress {
    'owner'.try_into().unwrap()
}

pub fn TREASURY_ADDRESS() -> ContractAddress {
    'treasury'.try_into().unwrap()
}

pub fn AGGREGATOR_ADDRESS() -> ContractAddress {
    'aggregator'.try_into().unwrap()
}

pub fn SENDER_ADDRESS() -> ContractAddress {
    'sender'.try_into().unwrap()
}

pub fn LIQUIDITY_PROVIDER_ADDRESS() -> ContractAddress {
    'liquidity_provider'.try_into().unwrap()
}

pub fn REFUND_ADDRESS() -> ContractAddress {
    'refund_address'.try_into().unwrap()
}

pub fn SENDER_FEE_RECIPIENT_ADDRESS() -> ContractAddress {
    'sender_fee_recipient'.try_into().unwrap()
}

pub fn TOKEN_ADDRESS() -> ContractAddress {
    'token'.try_into().unwrap()
}

pub fn GATEWAY_ADDRESS() -> ContractAddress {
    'gateway'.try_into().unwrap()
}

// ##################################################################
//                    DEPLOYMENT FUNCTIONS
// ##################################################################
pub fn deploy_erc20() -> ContractAddress {
    let contract = declare("MyToken").unwrap().contract_class();
    let constructor_args = array![];
    let (contract_address, _) = contract.deploy_at(@constructor_args, TOKEN_ADDRESS()).unwrap();
    contract_address
}

pub fn setup_erc20() -> (ContractAddress, ERC20ABIDispatcher) {
    let contract_address = deploy_erc20();
    let dispatcher = ERC20ABIDispatcher { contract_address };
    (contract_address, dispatcher)
}

pub fn deploy_gateway() -> ContractAddress {
    let contract = declare("Gateway").unwrap().contract_class();
    let constructor_args = array![OWNER_ADDRESS().into()];
    let (contract_address, _) = contract.deploy_at(@constructor_args, GATEWAY_ADDRESS()).unwrap();
    contract_address
}

pub fn setup_gateway() -> (ContractAddress, IGatewayDispatcher, IGatewaySettingManagerDispatcher) {
    let contract_address = deploy_gateway();
    let gateway_dispatcher = IGatewayDispatcher { contract_address };
    let setting_manager_dispatcher = IGatewaySettingManagerDispatcher { contract_address };
    (contract_address, gateway_dispatcher, setting_manager_dispatcher)
}

pub fn setup_gateway_with_config() -> (
    ContractAddress, IGatewayDispatcher, IGatewaySettingManagerDispatcher,
) {
    let (contract_address, gateway_dispatcher, setting_manager_dispatcher) = setup_gateway();

    // Configure protocol fee
    start_cheat_caller_address(contract_address, OWNER_ADDRESS());
    setting_manager_dispatcher.update_protocol_fee(PROTOCOL_FEE_PERCENT);
    stop_cheat_caller_address(contract_address);

    // Configure treasury address
    start_cheat_caller_address(contract_address, OWNER_ADDRESS());
    setting_manager_dispatcher.update_protocol_address('treasury', TREASURY_ADDRESS());
    stop_cheat_caller_address(contract_address);

    // Configure aggregator address
    start_cheat_caller_address(contract_address, OWNER_ADDRESS());
    setting_manager_dispatcher.update_protocol_address('aggregator', AGGREGATOR_ADDRESS());
    stop_cheat_caller_address(contract_address);

    (contract_address, gateway_dispatcher, setting_manager_dispatcher)
}

pub fn setup_token_support(
    gateway_address: ContractAddress,
    setting_manager: IGatewaySettingManagerDispatcher,
    token: ContractAddress,
) {
    start_cheat_caller_address(gateway_address, OWNER_ADDRESS());
    setting_manager.setting_manager_bool('token', token, 1);
    stop_cheat_caller_address(gateway_address);
}

pub fn setup_complete() -> (
    ContractAddress,
    IGatewayDispatcher,
    IGatewaySettingManagerDispatcher,
    ContractAddress,
    ERC20ABIDispatcher,
) {
    let (gateway_address, gateway_dispatcher, setting_manager_dispatcher) =
        setup_gateway_with_config();
    let (token_address, token_dispatcher) = setup_erc20();

    // Whitelist token
    setup_token_support(gateway_address, setting_manager_dispatcher, token_address);

    (
        gateway_address,
        gateway_dispatcher,
        setting_manager_dispatcher,
        token_address,
        token_dispatcher,
    )
}

