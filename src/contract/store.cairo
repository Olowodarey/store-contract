// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^1.0.0

const PAUSER_ROLE: felt252 = selector!("PAUSER_ROLE");
const UPGRADER_ROLE: felt252 = selector!("UPGRADER_ROLE");


#[starknet::contract]
pub mod Store {
    use openzeppelin::access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::security::pausable::PausableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{
        ClassHash, ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
    };


    // incontract calls
    use store::interfaces::Istore::IStore;
    use store::structs::Struct::Items;
    use super::{PAUSER_ROLE, UPGRADER_ROLE};


    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    // External
    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    #[abi(embed_v0)]
    impl AccessControlMixinImpl =
        AccessControlComponent::AccessControlMixinImpl<ContractState>;

    // Internal
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        // contract storage
        store_count: u32,
        store: Map<u32, Items>,
        // Map product names to product IDs
        product_name_to_id: Map<felt252, u32>,
        //payment
        payment_token_address: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, default_admin: ContractAddress, token_address: ContractAddress,
    ) {
        self.accesscontrol.initializer();

        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, default_admin);
        self.accesscontrol._grant_role(PAUSER_ROLE, default_admin);
        self.accesscontrol._grant_role(UPGRADER_ROLE, default_admin);

        // seting the payment token address
        self.payment_token_address.write(token_address);
    }

    #[generate_trait]
    #[abi(per_item)]
    impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn pause(ref self: ContractState) {
            self.accesscontrol.assert_only_role(PAUSER_ROLE);
            self.pausable.pause();
        }

        #[external(v0)]
        fn unpause(ref self: ContractState) {
            self.accesscontrol.assert_only_role(PAUSER_ROLE);
            self.pausable.unpause();
        }
    }

    //
    // Upgradeable
    //

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(UPGRADER_ROLE);
            self.upgradeable.upgrade(new_class_hash);
        }
    }


    #[abi(embed_v0)]
    impl StoreImpl of IStore<ContractState> {
        fn add_item(
            ref self: ContractState, productname: felt252, price: u32, quantity: u32, Img: felt252,
        ) {
            //  only the default admin can call this function
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);

            assert!(productname != 0, " productname cannot be empty");
            assert!(price > 0, "price should be more than zero");
            assert!(quantity > 0, "price should be more than zero");

            let productId = self.store_count.read() + 1;

            let new_item = Items { id: productId, productname, price, quantity, Img };

            // update the store mappings
            self.store.write(productId, new_item);
            // Update the store count
            self.store_count.write(productId);
            // Map product name to ID
            self.product_name_to_id.write(productname, productId);
        }

        fn get_item(self: @ContractState, productId: u32) -> Items {
            self.store.read(productId)
        }

        fn get_total_items(self: @ContractState) -> u32 {
            self.store_count.read()
        }

        fn get_all_items(self: @ContractState) -> Array<Items> {
            let total_items = self.store_count.read();
            let mut all_items = ArrayTrait::new();

            // Iterate through all items and add them to the array
            let mut i: u32 = 1;
            while i <= total_items {
                let item = self.store.read(i);
                all_items.append(item);
                i += 1;
            }

            all_items
        }

        fn buy_item(ref self: ContractState, productId: u32, quantity: u32) -> bool {
            assert!(productId <= self.store_count.read(), "Product does not exist");

            let mut item = self.store.read(productId);

            assert!(item.quantity >= quantity, "Not enough quantity available");

            item.quantity -= quantity;

            self.store.write(productId, item);

            true
        }

        fn buy_item_by_name(ref self: ContractState, productname: felt252, quantity: u32) -> bool {
            let productId = self.product_name_to_id.read(productname);

            assert!(productId != 0, "Product does not exist");

            let mut item = self.store.read(productId);

            assert!(item.quantity >= quantity, "Not enough quantity available");

            item.quantity -= quantity;

            self.store.write(productId, item);

            true
        }

        fn buy_product(ref self: ContractState, productId: u32, quantity: u32, price: u32) -> bool {
            let buyer = get_caller_address();
            let mut cost: u32 = 0;
            let mut i: u32 = 1;

            // check if the product exists and get the price without modifying the storage

            // verify the product exists
            assert!(productId <= self.store_count.read(), "Product does not exist");

            // get the item from storage
            let item = self.store.read(productId);

            //get the price
            let item_price = item.price * quantity;

            assert!(item_price == price, "Invalid price");

            //lets handle payment
            let payment_token_address = self.payment_token_address.read();
            let contract_address = get_contract_address();

            // we need to convert u32 to u256 for the ERC20 interface
            // We divide by PRICE_SCALING_FACTOR to get the actual token amount
            // decimal scaling factor for price representation
            // 1000 means prices are stored with 3 decimal places (e.g., 2343 = 2.343)
            const PRICE_SCALING_FACTOR: u32 = 1000;
            let total_price_u256: u256 = price.into() / PRICE_SCALING_FACTOR.into();
            // going to divide the Price scaling factor to get the actual token amount
            let total_price_u256: u256 = price.into() / PRICE_SCALING_FACTOR.into();

            // we need to convert to wei (10^18)  for strk token
            let total_price_in_wei: u256 = total_price_u256 * 1000000000000000000;

            // create a dispatcher to interact with the token contract
            let token_dispatcher = IERC20Dispatcher { contract_address: payment_token_address };

            // check if the buyer has enough balance
            let balance = token_dispatcher.balance_of(buyer);
            assert!(balance >= total_price_in_wei, "Insufficient balance");

            // check if the contract has enough allowance the buyer must approve the contract to
            // spend their tokens
            let allowance = token_dispatcher.allowance(buyer, contract_address);
            assert!(allowance >= total_price_in_wei, "Insufficient allowance");

            // transfer the tokens from the buyer to the contract
            token_dispatcher.transfer_from(buyer, contract_address, total_price_in_wei);

            // update the item quantity
            let mut item = self.store.read(productId);
            item.quantity -= quantity;
            self.store.write(productId, item);

            true
        }
    }
}
