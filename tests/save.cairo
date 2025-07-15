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
//     fn buy_product(ref self: ContractState, productId: u32, quantity: u32, price: u32) -> bool {
//         let buyer = get_caller_address();

//         // check if the product exists and get the price without modifying the storage

//         // verify the product exists
//         assert!(productId <= self.store_count.read(), "Product does not exist");

//         // get the item from storage
//         let item = self.store.read(productId);

//         //get the price
//         let item_price = item.price * quantity;

//         assert!(item_price == price, "Invalid price");

//           // verify there's enough quantity
//           assert!(item.quantity >= quantity, "Not enough quantity available");

//         //lets handle payment
//         let payment_token_address = self.payment_token_address.read();
//         let contract_address = get_contract_address();

//         // we need to convert u32 to u256 for the ERC20 interface
//         // We divide by PRICE_SCALING_FACTOR to get the actual token amount
//         // decimal scaling factor for price representation
//         // 1000 means prices are stored with 3 decimal places (e.g., 2343 = 2.343)
//         const PRICE_SCALING_FACTOR: u32 = 1000;

//         // going to divide the Price scaling factor to get the actual token amount
//         let total_price_u256: u256 = price.into() / PRICE_SCALING_FACTOR.into();

//         // we need to convert to wei (10^18)  for strk token
//         let total_price_in_wei: u256 = total_price_u256 * 1000000000000000000;

//         // create a dispatcher to interact with the token contract
//         let token_dispatcher = IERC20Dispatcher { contract_address: payment_token_address };

//         // check if the buyer has enough balance
//         let balance = token_dispatcher.balance_of(buyer);
//         assert!(balance >= total_price_in_wei, "Insufficient balance");

//         // check if the contract has enough allowance the buyer must approve the contract to
//         // spend their tokens
//         let allowance = token_dispatcher.allowance(buyer, contract_address);
//         assert!(allowance >= total_price_in_wei, "Insufficient allowance");

//         // transfer the tokens from the buyer to the contract
//         token_dispatcher.transfer_from(buyer, contract_address, total_price_in_wei);

//         // update the item quantity
//         let mut item = self.store.read(productId);
//         item.quantity -= quantity;
//         self.store.write(productId, item);

//         true
//     }
// }

//     fn buy_product(ref self: ContractState, productId: u32, quantity: u32, price: u32) -> bool {
//         let buyer = get_caller_address();

//         // verify the product exists
//         assert!(productId <= self.store_count.read(), "Product does not exist");

//         // get the item from storage
//         let item = self.store.read(productId);

//         // calculate the total price
//         let item_price = item.price * quantity;
//         assert!(item_price == price, "Invalid price");

//         // verify there's enough quantity
//         assert!(item.quantity >= quantity, "Not enough quantity available");

//         // handle payment
//         let payment_token_address = self.payment_token_address.read();
//         let contract_address = get_contract_address();

//         // convert price to u256 and scale it
//         let total_price_u256: u256 = price.into() * 1000000000000000000; // convert to wei

//         // create token dispatcher
//         let token_dispatcher = IERC20Dispatcher { contract_address: payment_token_address };

//         // check balance
//         let balance = token_dispatcher.balance_of(buyer);
//         assert!(balance >= total_price_u256, "Insufficient balance");

//         // check allowance
//         let allowance = token_dispatcher.allowance(buyer, contract_address);
//         assert!(allowance >= total_price_u256, "Insufficient allowance");

//         // transfer tokens
//         token_dispatcher.transfer_from(buyer, contract_address, total_price_u256);

//         // update item quantity
//         let mut item = self.store.read(productId);
//         item.quantity -= quantity;
//         self.store.write(productId, item);

//         true
//     }
// }


