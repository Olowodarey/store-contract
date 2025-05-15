use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const};
use store::contract::store::Store;
use store::interfaces::Istore::{IStoreDispatcher, IStoreDispatcherTrait};
use store::structs::Struct::Items;


fn setup() -> (ContractAddress, ContractAddress) {
    let admin_address: ContractAddress = contract_address_const::<'1'>();

    let declare_result = declare("Store");
    assert(declare_result.is_ok(), 'contract decleration failed');

    let contract_class = declare_result.unwrap().contract_class();
    let mut calldata = array![admin_address.into()];

    let deploy_result = contract_class.deploy(@calldata);
    assert(deploy_result.is_ok(), 'contract deployment failed');

    let (contract_address, _) = deploy_result.unwrap();

    (contract_address, admin_address)
}


#[test]
fn test_add_and_get_item() {
    // Deploy the contract
    let (contract_address, admin_address_) = setup();
    let owner = contract_address_const::<'1'>();

    let dispatcher = IStoreDispatcher { contract_address };

    start_cheat_caller_address(dispatcher.contract_address, owner);

    // Set up test data
    let product_name = 'Apple';
    let price = 100;
    let quantity = 10;
    let img = 'fhhhchhchc';

    // Add an item to the store
    dispatcher.add_item(product_name, price, quantity, img);
    dispatcher.add_item(product_name, price, quantity, img);

    // Get the item and verify its properties
    let item = dispatcher.get_item(1);

    // Assert that the item was added correctly
    assert_eq!(item.id, 1, "Item ID should be 1");
    assert_eq!(item.productname, product_name, "Product name should match");
    assert_eq!(item.price, price, "Price should match");
    assert_eq!(item.quantity, quantity, "Quantity should match");

    stop_cheat_caller_address(owner);

    // Verify total items count
    let total_items = dispatcher.get_total_items();
    assert_eq!(total_items, 2, "Total items should be 2");
}


#[test]
#[should_panic(expected: 'Caller not authorized to add')]
fn test_not_owner_adding() {
    // Deploy the contract
    let (contract_address, admin_address_) = setup();
    let non_owner = contract_address_const::<'2'>();

    let dispatcher = IStoreDispatcher { contract_address };

    start_cheat_caller_address(dispatcher.contract_address, non_owner);

    let product_name = 'Apple';
    let price = 100;
    let quantity = 10;
    let img = 'fhhhchhchc';

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
    let (contract_address, admin_address) = setup();
    let buyer_address = contract_address_const::<'3'>();

    let dispatcher = IStoreDispatcher { contract_address };

    // add an item as admin
    start_cheat_caller_address(dispatcher.contract_address, admin_address);

    let product_name = 'Apple';
    let price = 100;
    let initial_quantity = 10;
    let img = 'test_image';

    dispatcher.add_item(product_name, price, initial_quantity, img);

    // Stop being admin
    stop_cheat_caller_address(admin_address);

    // buy the item as a regular user
    start_cheat_caller_address(dispatcher.contract_address, buyer_address);

    // Buy 3 units of the product
    let purchase_quantity = 3;
    let purchase_success = dispatcher.buy_item(1, purchase_quantity);

    assert!(purchase_success, "Purchase should be successful");

    // Get the item and verify its quantity was reduced
    let item = dispatcher.get_item(1);
    let expected_remaining = initial_quantity - purchase_quantity;

    assert_eq!(item.quantity, expected_remaining, "Item quantity should be reduced");

    stop_cheat_caller_address(buyer_address);
}

#[test]
#[should_panic(expected: "Not enough quantity available")]
fn test_buy_item_insufficient_quantity() {
    let (contract_address, admin_address) = setup();
    let buyer_address = contract_address_const::<'3'>();

    let dispatcher = IStoreDispatcher { contract_address };

    start_cheat_caller_address(dispatcher.contract_address, admin_address);

    // Set up test data with low quantity
    let product_name = 'Apple';
    let price = 200;
    let initial_quantity = 5;
    let img = 'limited_img';

    // Add an item to the store
    dispatcher.add_item(product_name, price, initial_quantity, img);

    // Stop being admin
    stop_cheat_caller_address(admin_address);

    start_cheat_caller_address(dispatcher.contract_address, buyer_address);

    let excessive_quantity = 300;

    dispatcher.buy_item(1, excessive_quantity);

    stop_cheat_caller_address(buyer_address);
}

#[test]
#[should_panic(expected: "Product does not exist")]
fn test_buy_nonexistent_item() {
    let (contract_address, _) = setup();
    let buyer_address = contract_address_const::<'3'>();

    let dispatcher = IStoreDispatcher { contract_address };

    start_cheat_caller_address(dispatcher.contract_address, buyer_address);

    dispatcher.buy_item(999, 1);

    stop_cheat_caller_address(buyer_address);
}

#[test]
fn test_buy_item_by_name() {
    let (contract_address, admin_address) = setup();
    let buyer_address = contract_address_const::<'3'>();

    let dispatcher = IStoreDispatcher { contract_address };

    start_cheat_caller_address(dispatcher.contract_address, admin_address);

    let product_name = 'Apple';
    let price = 100;
    let initial_quantity = 10;
    let img = 'gfggfgf';

    dispatcher.add_item(product_name, price, initial_quantity, img);

    stop_cheat_caller_address(admin_address);

    start_cheat_caller_address(dispatcher.contract_address, buyer_address);

    let purchase_quantity = 3;
    let purchase_success = dispatcher.buy_item_by_name(product_name, purchase_quantity);

    // Verify purchase was successful
    assert!(purchase_success, "Purchase should be successful");

    // Get the item and verify its quantity was reduced
    let item = dispatcher.get_item(1);
    let expected_remaining = initial_quantity - purchase_quantity;

    assert_eq!(item.quantity, expected_remaining, "Item quantity should be reduced");

    stop_cheat_caller_address(buyer_address);
}

#[test]
#[should_panic(expected: "Product does not exist")]
fn test_buy_nonexistent_item_by_name() {
    // Deploy the contract
    let (contract_address, _) = setup();
    let buyer_address = contract_address_const::<'3'>();

    let dispatcher = IStoreDispatcher { contract_address };

    // Try to buy a product that doesn't exist
    start_cheat_caller_address(dispatcher.contract_address, buyer_address);

    dispatcher.buy_item_by_name('banana', 1);

    // We shouldn't reach this point
    stop_cheat_caller_address(buyer_address);
}
