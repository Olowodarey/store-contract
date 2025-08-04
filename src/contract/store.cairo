// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^1.0.0

const PAUSER_ROLE: felt252 = selector!("PAUSER_ROLE");
const UPGRADER_ROLE: felt252 = selector!("UPGRADER_ROLE");
const STRK_USD_ASSET_ID: felt252 = 6004514686061859652; // STRK/USD pair ID for Pragma Oracle


#[starknet::contract]
pub mod Store {
    use openzeppelin::access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::security::pausable::PausableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use pragma_lib::abi::{IPragmaABIDispatcher, IPragmaABIDispatcherTrait};
    use pragma_lib::types::{DataType, PragmaPricesResponse};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{
        ClassHash, ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
    };
    use store::Events::Events::PurchaseMade;


    // incontract calls
    use store::interfaces::Istore::IStore;
    use store::structs::Struct::Items;
    use super::{PAUSER_ROLE, STRK_USD_ASSET_ID, UPGRADER_ROLE};


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
        //pragma oracle
        pragma_oracle_address: ContractAddress,
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
        PurchaseMade: PurchaseMade,
    }


    #[constructor]
    fn constructor(
        ref self: ContractState,
        default_admin: ContractAddress,
        token_address: ContractAddress,
        oracle_address: ContractAddress,
    ) {
        self.accesscontrol.initializer();

        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, default_admin);
        self.accesscontrol._grant_role(PAUSER_ROLE, default_admin);
        self.accesscontrol._grant_role(UPGRADER_ROLE, default_admin);

        // Setting the payment token address
        self.payment_token_address.write(token_address);

        // Setting the pragma oracle address
        self.pragma_oracle_address.write(oracle_address);
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

        // Getter functions for debugging and verification
        fn get_token_address(self: @ContractState) -> ContractAddress {
            self.payment_token_address.read()
        }

        fn get_oracle_address(self: @ContractState) -> ContractAddress {
            self.pragma_oracle_address.read()
        }

        fn buy_product(
            ref self: ContractState,
            productId: u32,
            quantity: u32,
            expected_price: u32,
            payment_amount: u256,
        ) -> bool {
            let buyer = get_caller_address();

            // Verify the product exists
            assert(productId <= self.store_count.read(), 'Product does not exist');

            // Get the item from storage
            let item = self.store.read(productId);

            // Calculate the total price
            let total_price = item.price * quantity;
            assert(total_price == expected_price, 'Invalid price provided');

            // Verify there's enough quantity
            assert(item.quantity >= quantity, 'Not enough quantity available');

            // Handle payment
            let payment_token_address = self.payment_token_address.read();
            let contract_address = get_contract_address();

            // Get live STRK/USD price from Pragma Oracle
            let oracle_dispatcher = IPragmaABIDispatcher {
                contract_address: self.pragma_oracle_address.read(),
            };

            // Get STRK/USD price (returns price with 8 decimals)
            let price_response: PragmaPricesResponse = oracle_dispatcher
                .get_data_median(DataType::SpotEntry(STRK_USD_ASSET_ID));
            let strk_usd_price = price_response
                .price; // Price in USD with 8 decimals (e.g., 150000000 = $1.50)

            // Convert price from USD cents to STRK tokens using live oracle price
            // Frontend shows $1.50, backend stores 150 (cents)
            // Oracle returns price with 8 decimals, STRK has 18 decimals

            const CENTS_TO_DOLLARS: u32 = 100; // 100 cents = 1 dollar
            const ORACLE_DECIMALS: u256 = 100000000; // 1e8 (oracle price decimals)
            const STRK_DECIMALS: u256 = 1000000000000000000; // 1e18 (STRK token decimals)

            // Convert: cents -> dollars -> STRK tokens using live price
            // Example: 150 cents, STRK price = $1.50 -> need 1 STRK token
            // Formula: (price_in_dollars * STRK_DECIMALS) / (strk_usd_price / ORACLE_DECIMALS)
            let price_in_dollars: u256 = total_price.into() / CENTS_TO_DOLLARS.into();
            let price_in_tokens: u256 = (price_in_dollars * STRK_DECIMALS * ORACLE_DECIMALS)
                / strk_usd_price.into();

            // Verify payment amount is sufficient
            assert(payment_amount >= price_in_tokens, 'Insufficient payment amount');

            // Create token dispatcher
            let token_dispatcher = IERC20Dispatcher { contract_address: payment_token_address };

            // Check buyer's balance
            let buyer_balance = token_dispatcher.balance_of(buyer);
            assert(buyer_balance >= payment_amount, 'Insufficient balance');

            // Transfer tokens from buyer to contract
            // Use transfer_from to move tokens from buyer's wallet to the contract
            let transfer_result = token_dispatcher.transfer_from(buyer, contract_address, payment_amount);
            assert(transfer_result, 'Token transfer failed');

            // Update item quantity
            let mut updated_item = item;
            updated_item.quantity -= quantity;
            self.store.write(productId, updated_item);

            // Emit purchase event
            self
                .emit(
                    PurchaseMade {
                        buyer,
                        product_id: productId,
                        product_name: item.productname,
                        quantity,
                        total_price_cents: total_price,
                        total_price_tokens: price_in_tokens,
                        timestamp: get_block_timestamp(),
                    },
                );

            true
        }
    }
}
