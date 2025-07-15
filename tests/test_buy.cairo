use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const};
use store::contract::store::Store;
use store::interfaces::Istore::{IStoreDispatcher, IStoreDispatcherTrait};
use store::structs::Struct::Items;

// Constants for token amounts
const TOKENS_PER_UNIT: u256 = 1000000000000000000; // 1 token in wei
const ONE_TOKEN: u256 = TOKENS_PER_UNIT;
const TEN_TOKENS: u256 = ONE_TOKEN * 10;
const HUNDRED_TOKENS: u256 = ONE_TOKEN * 100;

const PRICE_SCALING_FACTOR: u32 = 1000;

fn setup_with_token() -> (ContractAddress, ContractAddress, ContractAddress) {
    // create default admin address
    let owner: ContractAddress = contract_address_const::<'1'>();

    // Deploy mock token for payment
    let token_class = declare("Olowotoken").unwrap().contract_class();
    let (token_address, _) = token_class
        .deploy(@array![owner.into(), // recipient
        owner.into() // owner
        ])
        .unwrap();

    // deploy store contract
    let declare_result = declare("Store");
    assert(declare_result.is_ok(), 'contract declaration failed');

    let contract_class = declare_result.unwrap().contract_class();
    let mut calldata = array![owner.into(), token_address.into()];

    let deploy_result = contract_class.deploy(@calldata);
    assert(deploy_result.is_ok(), 'contract deployment failed');

    let (contract_address, _) = deploy_result.unwrap();

    (contract_address, owner, token_address)
}

#[test]
fn test_buy_product() {
    // Deploy the contracts
    let (contract_address, owner, token_address) = setup_with_token();
    let dispatcher = IStoreDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Add an item as admin
    start_cheat_caller_address(contract_address, owner);

    let product_name = 'Apple';
    // Price stored as scaled value: 1000 = 1 token (1000/1000 = 1)
    let scaled_price: u32 = 1000; // This represents 1 token when scaled
    let initial_quantity = 100;
    let img = 'apple_img';

    dispatcher.add_item(product_name, scaled_price, initial_quantity, img);
    stop_cheat_caller_address(contract_address);

    // Create a buyer
    let buyer_address = contract_address_const::<'3'>();

    // Transfer tokens from owner to buyer
    start_cheat_caller_address(token_address, owner);
    token_dispatcher.transfer(buyer_address, HUNDRED_TOKENS);
    stop_cheat_caller_address(token_address);

    // Check buyer's initial balance
    let buyer_balance_before = token_dispatcher.balance_of(buyer_address);
    assert(buyer_balance_before == HUNDRED_TOKENS, 'Initial should be 100 tokens');

    // Approve the contract to spend buyer's tokens
    // For 1 quantity at scaled price 1000, we need 1 token
    start_cheat_caller_address(token_address, buyer_address);
    token_dispatcher.approve(contract_address, TEN_TOKENS); // Approve more than needed
    stop_cheat_caller_address(token_address);

    // Test purchase parameters
    let product_id: u32 = 1;
    let purchase_quantity: u32 = 1;
    let expected_price: u32 = scaled_price * purchase_quantity; // 1000 * 1 = 1000

    // Make the purchase
    start_cheat_caller_address(contract_address, buyer_address);
    dispatcher.buy_product(product_id, purchase_quantity, expected_price);
    stop_cheat_caller_address(contract_address);

    // Verify buyer's balance after purchase
    let buyer_balance_after = token_dispatcher.balance_of(buyer_address);
    let expected_balance_after = HUNDRED_TOKENS - ONE_TOKEN; // 100 - 1 = 99 tokens
    assert(buyer_balance_after == expected_balance_after, ' balance should be 99 tokens');

    // Verify contract's balance
    let contract_balance = token_dispatcher.balance_of(contract_address);
    assert(contract_balance == ONE_TOKEN, 'Contract should have 1 token');

    // Verify item quantity was updated
    let item = dispatcher.get_item(product_id);
    assert(item.quantity == initial_quantity - purchase_quantity, 'Item quantity should be 99');
}

#[test]
fn test_buy_product_multiple_quantity() {
    // Deploy the contracts
    let (contract_address, owner, token_address) = setup_with_token();
    let dispatcher = IStoreDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Add an item as admin
    start_cheat_caller_address(contract_address, owner);

    let product_name = 'Orange';
    // Price stored as scaled value: 2000 = 2 tokens when scaled
    let scaled_price: u32 = 2000;
    let initial_quantity = 50;
    let img = 'orange_img';

    dispatcher.add_item(product_name, scaled_price, initial_quantity, img);
    stop_cheat_caller_address(contract_address);

    // Create a buyer
    let buyer_address = contract_address_const::<'4'>();

    // Transfer tokens from owner to buyer
    start_cheat_caller_address(token_address, owner);
    token_dispatcher.transfer(buyer_address, HUNDRED_TOKENS);
    stop_cheat_caller_address(token_address);

    // Approve the contract to spend buyer's tokens
    start_cheat_caller_address(token_address, buyer_address);
    token_dispatcher.approve(contract_address, TEN_TOKENS);
    stop_cheat_caller_address(token_address);

    // Test purchase parameters
    let product_id: u32 = 1;
    let purchase_quantity: u32 = 3;
    let expected_price: u32 = scaled_price * purchase_quantity; // 2000 * 3 = 6000

    // Make the purchase
    start_cheat_caller_address(contract_address, buyer_address);
    dispatcher.buy_product(product_id, purchase_quantity, expected_price);
    stop_cheat_caller_address(contract_address);

    // Verify buyer's balance after purchase
    // 6000 scaled price = 6 tokens (6000/1000 = 6)
    let buyer_balance_after = token_dispatcher.balance_of(buyer_address);
    let expected_balance_after = HUNDRED_TOKENS - (ONE_TOKEN * 6); // 100 - 6 = 94 tokens
    assert(buyer_balance_after == expected_balance_after, ' balance should be 94 tokens');

    // Verify contract's balance
    let contract_balance = token_dispatcher.balance_of(contract_address);
    assert(contract_balance == ONE_TOKEN * 6, 'Contract should have 6 tokens');

    // Verify item quantity was updated
    let item = dispatcher.get_item(product_id);
    assert(item.quantity == initial_quantity - purchase_quantity, 'Item quantity should be 47');
}

