use store::structs::Struct::Items;


#[starknet::interface]
pub trait IStore<TContractState> {
    fn add_item(
        ref self: TContractState, productname: felt252, price: u32, quantity: u32, Img: felt252,
    );
    fn get_item(self: @TContractState, productId: u32) -> Items;
    fn get_total_items(self: @TContractState) -> u32;
    fn get_all_items(self: @TContractState) -> Array<Items>;
    fn buy_product(
        ref self: TContractState, productId: u32, quantity: u32, expected_price: u32,
    ) -> bool;
}
