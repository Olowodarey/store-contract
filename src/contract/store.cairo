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
    use openzeppelin::token::erc721::{ERC721Component, ERC721HooksEmptyImpl};
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
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
    use store::structs::Struct::{CartItem, Items, PurchaseReceipt};
    use super::{PAUSER_ROLE, UPGRADER_ROLE};


    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: ERC721Component, storage: erc721, event: ERC721Event);

    // External
    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    #[abi(embed_v0)]
    impl AccessControlMixinImpl =
        AccessControlComponent::AccessControlMixinImpl<ContractState>;

    // Add ERC721 metadata implementation
    #[abi(embed_v0)]
    impl ERC721MetadataImpl = ERC721Component::ERC721MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;

    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;

    // Internal
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;


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
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        // contract storage
        store_count: u32,
        store: Map<u32, Items>,
        // Map product names to product IDs
        product_name_to_id: Map<felt252, u32>,
        //payment
        payment_token_address: ContractAddress,
        //receipt NFT storage
        receipt_count: u256,
        receipts: Map<u256, PurchaseReceipt>,
        user_receipts: Map<(ContractAddress, u256), u256>, // (user, index) -> receipt_id
        user_receipt_count: Map<ContractAddress, u256>, // user -> number of receipts
        // Track purchases that can be minted as receipts
        purchase_count: u256,
        purchases: Map<u256, PurchaseReceipt>, // purchase_id -> purchase data
        user_purchases: Map<(ContractAddress, u256), u256>, // (user, index) -> purchase_id
        user_purchase_count: Map<ContractAddress, u256>, // user -> number of purchases
        purchase_minted: Map<u256, bool> // purchase_id -> is_minted as NFT
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
        #[flat]
        ERC721Event: ERC721Component::Event,
        PurchaseMade: PurchaseMade,
    }


    #[constructor]
    fn constructor(
        ref self: ContractState,
        default_admin: ContractAddress,
        token_address: ContractAddress,
    ) {
        // Initialize ERC721 with metadata
        self
            .erc721
            .initializer(
                "Store Purchase Receipts",
                "RECEIPT",
                "https://web3-ecommerce-roan.vercel.app/api/nft-metadata/",
            );

        self.accesscontrol.initializer();

        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, default_admin);
        self.accesscontrol._grant_role(PAUSER_ROLE, default_admin);
        self.accesscontrol._grant_role(UPGRADER_ROLE, default_admin);

        // Setting the payment token address
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

        #[external(v0)]
        fn add_admin(ref self: ContractState, new_admin: ContractAddress) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, new_admin);
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
            ref self: ContractState,
            productname: felt252,
            price: u32,
            quantity: u32,
            Img: ByteArray,
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
            let end_index = total_items + 1;
            while i != end_index {
                let item = self.store.read(i);
                all_items.append(item);
                i += 1;
            }

            all_items
        }


        fn get_token_address(self: @ContractState) -> ContractAddress {
            self.payment_token_address.read()
        }

     

        fn buy_product(
            ref self: ContractState,
            productId: u32,
            quantity: u32,
            expected_price: u32,
            payment_amount: u256,
        ) -> bool {
            let buyer = get_caller_address();

            assert(productId <= self.store_count.read(), 'Product does not exist');

            let item = self.store.read(productId);

            let total_price = item.price * quantity;
            assert(total_price == expected_price, 'Invalid price provided');

            assert(item.quantity >= quantity, 'Not enough quantity available');

            let payment_token_address = self.payment_token_address.read();
            let contract_address = get_contract_address();

            // Payment amount validation - frontend handles price conversion
            assert(payment_amount > 0, 'Payment amount must be > 0');

            let token_dispatcher = IERC20Dispatcher { contract_address: payment_token_address };

            let buyer_balance = token_dispatcher.balance_of(buyer);
            assert(buyer_balance >= payment_amount, 'Insufficient balance');

            let allowance = token_dispatcher.allowance(buyer, contract_address);
            assert(allowance >= payment_amount, 'Insufficient allowance');

            let _transfer_result = token_dispatcher;
            let transfer_result = token_dispatcher
                .transfer_from(buyer, contract_address, payment_amount);
            assert(transfer_result, 'Token transfer failed');

            let product_name = item.productname;
            let mut updated_item = item;
            updated_item.quantity -= quantity;
            self.store.write(productId, updated_item);

            let purchase_id = self.purchase_count.read() + 1;
            self.purchase_count.write(purchase_id);

            let purchase_data = PurchaseReceipt {
                receipt_id: 0, // Will be set when minted
                buyer,
                product_id: productId,
                product_name,
                quantity,
                total_price_cents: total_price,
                total_price_tokens: 0, // Frontend handles price conversion
                timestamp: get_block_timestamp(),
            };

            self.purchases.write(purchase_id, purchase_data);

            self._add_purchase_to_user(buyer, purchase_id);

            self
                .emit(
                    PurchaseMade {
                        buyer,
                        product_id: productId,
                        product_name,
                        quantity,
                        total_price_cents: total_price,
                        total_price_tokens: payment_amount,
                        timestamp: get_block_timestamp(),
                    },
                );

            true
        }


        fn buy_multiple_products(
            ref self: ContractState, cart_items: Array<CartItem>, total_payment_amount: u256,
        ) -> bool {
            let buyer = get_caller_address();

            assert(cart_items.len() > 0, 'Cart cannot be empty');

            // Payment amount validation - frontend handles price conversion
            assert(total_payment_amount > 0, 'Payment amount must be > 0');

            let mut total_price_cents: u32 = 0;
            let mut i = 0;
            let cart_items_len = cart_items.len();

            // First pass: validate all items and calculate total price
            while i != cart_items_len {
                let cart_item = cart_items.at(i);
                let product_id = *cart_item.product_id;
                let quantity = *cart_item.quantity;
                let expected_price = *cart_item.expected_price;

                // Verify the product exists
                assert(product_id <= self.store_count.read(), 'Product does not exist');

                let item = self.store.read(product_id);

                assert(item.price == expected_price, 'Price mismatch');

                // Verify there's enough quantity
                assert(item.quantity >= quantity, 'Not enough quantity available');

                // Add to total price
                total_price_cents += item.price * quantity;

                i += 1;
            }

            // Frontend handles price conversion, just validate payment amount
            // We still calculate total_price_cents for validation purposes
            // but payment validation is handled by frontend

            let payment_token_address = self.payment_token_address.read();
            let contract_address = get_contract_address();
            let token_dispatcher = IERC20Dispatcher { contract_address: payment_token_address };

            let buyer_balance = token_dispatcher.balance_of(buyer);
            assert(buyer_balance >= total_payment_amount, 'Insufficient balance');

            let allowance = token_dispatcher.allowance(buyer, contract_address);
            assert(allowance >= total_payment_amount, 'Insufficient allowance');

            // Transfer tokens from buyer to contract
            let transfer_result = token_dispatcher
                .transfer_from(buyer, contract_address, total_payment_amount);
            assert(transfer_result, 'Token transfer failed');

            // Second pass: update quantities and emit events
            let mut j = 0;
            let cart_items_len = cart_items.len();
            while j != cart_items_len {
                let cart_item = cart_items.at(j);
                let product_id = *cart_item.product_id;
                let quantity = *cart_item.quantity;

                // Get and update item quantity
                let item = self.store.read(product_id);
                let mut updated_item = item;
                updated_item.quantity -= quantity;
                self.store.write(product_id, updated_item);

                // Calculate individual item total price
                let item = self.store.read(product_id);
                let item_total_price = item.price * quantity;
                // Frontend handles price conversion, so we set tokens to 0
                let item_price_tokens: u256 = 0;

                // Store purchase data for receipt minting
                let purchase_id = self.purchase_count.read() + 1;
                self.purchase_count.write(purchase_id);

                let purchase_data = PurchaseReceipt {
                    receipt_id: 0, // Will be set when minted
                    buyer,
                    product_id,
                    product_name: item.productname,
                    quantity,
                    total_price_cents: item_total_price,
                    total_price_tokens: item_price_tokens,
                    timestamp: get_block_timestamp(),
                };

                self.purchases.write(purchase_id, purchase_data);

                self._add_purchase_to_user(buyer, purchase_id);

                self
                    .emit(
                        PurchaseMade {
                            buyer,
                            product_id,
                            product_name: item.productname,
                            quantity,
                            total_price_cents: item_total_price,
                            total_price_tokens: item_price_tokens,
                            timestamp: get_block_timestamp(),
                        },
                    );

                j += 1;
            }
            true
        }

        fn get_contract_balance(self: @ContractState) -> u256 {
            let token_dispatcher = IERC20Dispatcher {
                contract_address: self.payment_token_address.read(),
            };
            token_dispatcher.balance_of(get_contract_address())
        }

        fn withdraw_tokens(
            ref self: ContractState, amount: u256, recipient: ContractAddress,
        ) -> bool {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);

            assert(amount > 0, 'Amount must be greater than 0');

            let contract_balance = self.get_contract_balance();
            assert(amount <= contract_balance, 'Insufficient contract balance');

            let token_dispatcher = IERC20Dispatcher {
                contract_address: self.payment_token_address.read(),
            };
            let transfer_success = token_dispatcher.transfer(recipient, amount);
            assert(transfer_success, 'Token transfer failed');

            true
        }

        fn get_user_receipts(self: @ContractState, user: ContractAddress) -> Array<u256> {
            let receipt_count = self.user_receipt_count.read(user);
            let mut receipts = ArrayTrait::new();
            let mut i: u256 = 0;

            while i != receipt_count {
                let receipt_id = self.user_receipts.read((user, i));
                receipts.append(receipt_id);
                i += 1;
            }

            receipts
        }

        fn mint_receipt(ref self: ContractState, purchase_id: u256) -> bool {
            let buyer = get_caller_address();

            assert(purchase_id <= self.purchase_count.read(), 'Purchase does not exist');

            assert(!self.purchase_minted.read(purchase_id), 'Purchase already minted');

            let mut purchase_data = self.purchases.read(purchase_id);

            assert(purchase_data.buyer == buyer, 'Not purchase owner');

            let receipt_id = self.receipt_count.read() + 1;
            self.receipt_count.write(receipt_id);
            purchase_data.receipt_id = receipt_id;
            self.receipts.write(receipt_id, purchase_data);
            self._add_receipt_to_user(buyer, receipt_id);

            self.purchase_minted.write(purchase_id, true);

            self.erc721.mint(buyer, receipt_id);

            true
        }

        fn get_user_purchases(self: @ContractState, user: ContractAddress) -> Array<u256> {
            let purchase_count = self.user_purchase_count.read(user);
            let mut purchases = ArrayTrait::new();
            let mut i: u256 = 0;

            while i != purchase_count {
                let purchase_id = self.user_purchases.read((user, i));
                purchases.append(purchase_id);
                i += 1;
            }

            purchases
        }

        fn get_purchase_count(self: @ContractState) -> u256 {
            self.purchase_count.read()
        }

        fn is_purchase_minted(self: @ContractState, purchase_id: u256) -> bool {
            self.purchase_minted.read(purchase_id)
        }


        fn get_purchase_details(self: @ContractState, purchase_id: u256) -> PurchaseReceipt {
            assert(purchase_id <= self.purchase_count.read(), 'Purchase does not exist');
            self.purchases.read(purchase_id)
        }
    }


    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _add_receipt_to_user(ref self: ContractState, user: ContractAddress, receipt_id: u256) {
            let current_count = self.user_receipt_count.read(user);
            self.user_receipts.write((user, current_count), receipt_id);
            self.user_receipt_count.write(user, current_count + 1);
        }

        fn _add_purchase_to_user(
            ref self: ContractState, user: ContractAddress, purchase_id: u256,
        ) {
            let current_count = self.user_purchase_count.read(user);
            self.user_purchases.write((user, current_count), purchase_id);
            self.user_purchase_count.write(user, current_count + 1);
        }
    }
}
