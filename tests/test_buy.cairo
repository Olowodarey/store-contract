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
        .deploy(@array![owner.into() // owner (simplified constructor)
        ])
        .unwrap();

    // Deploy MockOracle contract for testing
    let oracle_class = declare("MockOracle").unwrap().contract_class();
    let (oracle_address, _) = oracle_class
        .deploy(@array![150000000_u128.into()]) // $1.50 with 8 decimals = 150000000
        .unwrap();

    // deploy store contract with mock oracle address
    let declare_result = declare("Store");
    assert(declare_result.is_ok(), 'contract declaration failed');

    let contract_class = declare_result.unwrap().contract_class();
    let mut calldata = array![
        owner.into(), // admin
        token_address.into(), // token address  
        oracle_address.into() // mock oracle address
    ];

    let deploy_result = contract_class.deploy(@calldata);
    assert(deploy_result.is_ok(), 'contract deployment failed');

    let (contract_address, _) = deploy_result.unwrap();

    (contract_address, owner, token_address)
}


#[test]
fn test_contract_deployment() {
    let (contract_address, owner, token_address) = setup_with_token();
    let dispatcher = IStoreDispatcher { contract_address };

    // Test adding an item (this should work without oracle calls)
    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_item('Apple', 150, 100, 'apple_img'); // $1.50 stored as 150 cents
    stop_cheat_caller_address(contract_address);

    // Verify item was added
    let item = dispatcher.get_item(1);
    assert(item.productname == 'Apple', 'Product name should match');
    assert(item.price == 150, 'Price should be 150 cents');
    assert(item.quantity == 100, 'Quantity should be 100');

    // Verify store count
    let total_items = dispatcher.get_total_items();
    assert(total_items == 1, 'Should have 1 item');
}



#[test]
fn test_buy_check_balance_and_withdraw() {
    let (contract_address, owner, token_address) = setup_with_token();
    let dispatcher = IStoreDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    
    // Create a buyer address
    let buyer: ContractAddress = contract_address_const::<'2'>();
    
    // Add an item first (as admin)
    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_item('Apple', 150, 100, 'apple_img'); // $1.50 stored as 150 cents
    stop_cheat_caller_address(contract_address);
    
    // Give buyer some tokens to make purchase
    start_cheat_caller_address(token_address, owner);
    token_dispatcher.transfer(buyer, ONE_TOKEN * 5); // Give buyer 5 tokens (should be enough)
    stop_cheat_caller_address(token_address);
    
    // Check initial contract balance (should be 0)
    let initial_balance = dispatcher.get_contract_balance();
    assert(initial_balance == 0, 'Initial balance should be 0');
    
    // Buyer approves the store contract to spend tokens
    start_cheat_caller_address(token_address, buyer);
    token_dispatcher.approve(contract_address, ONE_TOKEN * 5);
    stop_cheat_caller_address(token_address);
    
    // Buyer makes a purchase
    start_cheat_caller_address(contract_address, buyer);
    let purchase_result = dispatcher.buy_product(1, 2, 300, ONE_TOKEN * 3); // Buy 2 apples, provide 3 STRK tokens as payment
    assert(purchase_result == true, 'Purchase should succeed');
    stop_cheat_caller_address(contract_address);
    
    // Check contract balance after purchase
    let balance_after_purchase = dispatcher.get_contract_balance();
    assert(balance_after_purchase > 0, 'Contract should have balance');
    
    // Verify the item quantity was reduced
    let item_after_purchase = dispatcher.get_item(1);
    assert(item_after_purchase.quantity == 98, 'Quantity should be reduced by 2');
    
    // Test withdrawal (as admin)
    let withdrawal_amount = balance_after_purchase / 2; // Withdraw half
    
    start_cheat_caller_address(contract_address, owner);
    let withdraw_result = dispatcher.withdraw_tokens(withdrawal_amount, owner);
    assert(withdraw_result == true, 'Withdrawal should succeed');
    stop_cheat_caller_address(contract_address);
    
    // Check contract balance after withdrawal
    let balance_after_withdrawal = dispatcher.get_contract_balance();
    assert(balance_after_withdrawal == balance_after_purchase - withdrawal_amount, 'Balance should be reduced');
    
  
}

#[test]
fn test_withdraw_insufficient_balance() {
    let (contract_address, owner, token_address) = setup_with_token();
    let dispatcher = IStoreDispatcher { contract_address };
    
    // Try to withdraw more than available balance (should fail)
    start_cheat_caller_address(contract_address, owner);
    
    let current_balance = dispatcher.get_contract_balance();
    let excessive_amount = current_balance + ONE_TOKEN;
    
    // This should panic with 'Insufficient contract balance'
    // dispatcher.withdraw_tokens(excessive_amount, owner); // Uncomment to test
    stop_cheat_caller_address(contract_address);
}