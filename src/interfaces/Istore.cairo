use store::structs::Struct::{CartItem, Items, PurchaseReceipt};


#[starknet::interface]
pub trait IStore<TContractState> {
    fn add_item(
        ref self: TContractState, productname: felt252, price: u32, quantity: u32, Img: ByteArray,
    );
    fn get_item(self: @TContractState, productId: u32) -> Items;
    fn get_total_items(self: @TContractState) -> u32;
    fn get_all_items(self: @TContractState) -> Array<Items>;
    fn buy_product(
        ref self: TContractState,
        productId: u32,
        quantity: u32,
        expected_price: u32,
        payment_amount: u256,
    ) -> bool;
    fn buy_multiple_products(
        ref self: TContractState, cart_items: Array<CartItem>, total_payment_amount: u256,
    ) -> bool;
    // Getter functions for debugging and verification
    fn get_token_address(self: @TContractState) -> starknet::ContractAddress;
    fn get_oracle_address(self: @TContractState) -> starknet::ContractAddress;
    fn get_contract_balance(self: @TContractState) -> u256;
    fn withdraw_tokens(
        ref self: TContractState, amount: u256, recipient: starknet::ContractAddress,
    ) -> bool;


    // NFT Receipt functions

    fn get_user_receipts(self: @TContractState, user: starknet::ContractAddress) -> Array<u256>;
    fn mint_receipt(ref self: TContractState, purchase_id: u256) -> bool;
    fn get_user_purchases(self: @TContractState, user: starknet::ContractAddress) -> Array<u256>;
    fn get_purchase_count(self: @TContractState) -> u256;
    fn is_purchase_minted(self: @TContractState, purchase_id: u256) -> bool;
    fn get_purchase_details(self: @TContractState, purchase_id: u256) -> PurchaseReceipt;
}
