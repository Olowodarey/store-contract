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
const ONE_TOKEN: u256 = 1000000000000000000; // 1 token in wei

fn setup() -> (ContractAddress, ContractAddress, ContractAddress) {
    let admin_address: ContractAddress = contract_address_const::<'1'>();

    // Deploy mock token for payment
    let token_class = declare("Olowotoken").unwrap().contract_class();
    let (token_address, _) = token_class
        .deploy(@array![admin_address.into() // owner (simplified constructor)
        ])
        .unwrap();

    // Deploy store contract with proper parameters
    let declare_result = declare("Store");
    assert(declare_result.is_ok(), 'contract decleration failed');

    let contract_class = declare_result.unwrap().contract_class();
    let mut calldata = array![
        admin_address.into(), // admin
        token_address.into(), // token address
    ];

    let deploy_result = contract_class.deploy(@calldata);
    assert(deploy_result.is_ok(), 'contract deployment failed');

    let (contract_address, _) = deploy_result.unwrap();

    (contract_address, admin_address, token_address)
}



#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_not_owner_adding() {
    // Deploy the contract
    let (contract_address, _admin_address, _token_address) = setup();
    let non_owner = contract_address_const::<'2'>();

    let dispatcher = IStoreDispatcher { contract_address };

    start_cheat_caller_address(dispatcher.contract_address, non_owner);

    let product_name = 'Apple';
    let price = 100;
    let quantity = 10;
    let img = "fhhhchhchc";

    dispatcher.add_item(product_name, price, quantity, img);

    let item = dispatcher.get_item(1);

    assert_eq!(item.id, 1, "Item ID should be 1");
    assert_eq!(item.productname, product_name, "Product name should match");
    assert_eq!(item.price, price, "Price should match");
    assert_eq!(item.quantity, quantity, "Quantity should match");

    stop_cheat_caller_address(non_owner);

    let total_items = dispatcher.get_total_items();
    assert_eq!(total_items, 1, "Total items should be 1");
}

#[test]
fn test_buy_item_by_productId() {
    let (contract_address, admin_address, token_address) = setup();
    let buyer_address = contract_address_const::<'3'>();

    let dispatcher = IStoreDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // add an item as admin
    start_cheat_caller_address(dispatcher.contract_address, admin_address);

    let product_name = 'Apple';
    let price = 100;
    let initial_quantity = 10;
    let img = "test_image";

    dispatcher.add_item(product_name, price, initial_quantity, img);

    // Stop being admin
    stop_cheat_caller_address(admin_address);

    // Setup buyer with tokens and approval
    start_cheat_caller_address(token_address, admin_address);
    token_dispatcher.transfer(buyer_address, ONE_TOKEN * 5);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, buyer_address);
    token_dispatcher.approve(contract_address, ONE_TOKEN * 5);
    stop_cheat_caller_address(token_address);

    // buy the item as a regular user
    start_cheat_caller_address(dispatcher.contract_address, buyer_address);

    // Buy 3 units of the product using new buy_product method
    let purchase_quantity = 3;
    let expected_price = price * purchase_quantity;
    let payment_amount = ONE_TOKEN * 2; // Provide enough tokens
    let purchase_success = dispatcher.buy_product(1, purchase_quantity, expected_price, payment_amount);

    assert!(purchase_success, "Purchase should be successful");

    // Get the item and verify its quantity was reduced
    let item = dispatcher.get_item(1);
    let expected_remaining = initial_quantity - purchase_quantity;

    assert_eq!(item.quantity, expected_remaining, "Item quantity should be reduced");

    stop_cheat_caller_address(buyer_address);
}

#[test]
#[should_panic(expected: 'Not enough quantity available')]
fn test_buy_item_insufficient_quantity() {
    let (contract_address, admin_address, token_address) = setup();
    let buyer_address = contract_address_const::<'3'>();

    let dispatcher = IStoreDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    start_cheat_caller_address(dispatcher.contract_address, admin_address);

    // Set up test data with low quantity
    let product_name = 'Apple';
    let price = 200;
    let initial_quantity = 5;
    let img = "limited_img";

    // Add an item to the store
    dispatcher.add_item(product_name, price, initial_quantity, img);

    // Stop being admin
    stop_cheat_caller_address(admin_address);

    // Setup buyer with tokens and approval
    start_cheat_caller_address(token_address, admin_address);
    token_dispatcher.transfer(buyer_address, ONE_TOKEN * 100);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, buyer_address);
    token_dispatcher.approve(contract_address, ONE_TOKEN * 100);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(dispatcher.contract_address, buyer_address);

    let excessive_quantity = 300;
    let expected_price = price * excessive_quantity;
    let payment_amount = ONE_TOKEN * 50;

    dispatcher.buy_product(1, excessive_quantity, expected_price, payment_amount);

    stop_cheat_caller_address(buyer_address);
}

#[test]
#[should_panic(expected: 'Product does not exist')]
fn test_buy_nonexistent_item() {
    let (contract_address, _admin_address, token_address) = setup();
    let buyer_address = contract_address_const::<'3'>();

    let dispatcher = IStoreDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Setup buyer with tokens and approval
    start_cheat_caller_address(token_address, _admin_address);
    token_dispatcher.transfer(buyer_address, ONE_TOKEN * 5);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, buyer_address);
    token_dispatcher.approve(contract_address, ONE_TOKEN * 5);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(dispatcher.contract_address, buyer_address);

    dispatcher.buy_product(999, 1, 100, ONE_TOKEN);

    stop_cheat_caller_address(buyer_address);
}

#[test]
fn test_buy_item_by_name() {
    let (contract_address, admin_address, token_address) = setup();
    let buyer_address = contract_address_const::<'3'>();

    let dispatcher = IStoreDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    start_cheat_caller_address(dispatcher.contract_address, admin_address);

    let product_name = 'Apple';
    let price = 100;
    let initial_quantity = 10;
    let img = "gfggfgf";

    dispatcher.add_item(product_name, price, initial_quantity, img);

    stop_cheat_caller_address(admin_address);

    // Setup buyer with tokens and approval
    start_cheat_caller_address(token_address, admin_address);
    token_dispatcher.transfer(buyer_address, ONE_TOKEN * 5);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, buyer_address);
    token_dispatcher.approve(contract_address, ONE_TOKEN * 5);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(dispatcher.contract_address, buyer_address);

    let purchase_quantity = 3;
    let expected_price = price * purchase_quantity;
    let payment_amount = ONE_TOKEN * 2;
    let purchase_success = dispatcher.buy_product(1, purchase_quantity, expected_price, payment_amount);

    // Verify purchase was successful
    assert!(purchase_success, "Purchase should be successful");

    // Get the item and verify its quantity was reduced
    let item = dispatcher.get_item(1);
    let expected_remaining = initial_quantity - purchase_quantity;

    assert_eq!(item.quantity, expected_remaining, "Item quantity should be reduced");

    stop_cheat_caller_address(buyer_address);
}

#[test]
#[should_panic(expected: 'Product does not exist')]
fn test_buy_nonexistent_item_by_name() {
    // Deploy the contract
    let (contract_address, _admin_address, token_address) = setup();
    let buyer_address = contract_address_const::<'3'>();

    let dispatcher = IStoreDispatcher { contract_address };
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Setup buyer with tokens and approval
    start_cheat_caller_address(token_address, _admin_address);
    token_dispatcher.transfer(buyer_address, ONE_TOKEN * 5);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, buyer_address);
    token_dispatcher.approve(contract_address, ONE_TOKEN * 5);
    stop_cheat_caller_address(token_address);

    // Try to buy a product that doesn't exist
    start_cheat_caller_address(dispatcher.contract_address, buyer_address);

    // Since we can't buy by name anymore, try to buy non-existent product ID
    dispatcher.buy_product(999, 1, 100, ONE_TOKEN);

    // We shouldn't reach this point
    stop_cheat_caller_address(buyer_address);
}
