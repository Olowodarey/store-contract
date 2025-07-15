use store::structs::Struct::Items;


#[starknet::interface]
pub trait IStore<TContractState> {
    fn add_item(
        ref self: TContractState, productname: felt252, price: u32, quantity: u32, Img: felt252,
    );
    fn get_item(self: @TContractState, productId: u32) -> Items;
    fn get_total_items(self: @TContractState) -> u32;
    // fn purchase_item(ref self: TContractState, productname: felt252, quantity: u8) -> bool;
    fn get_all_items(self: @TContractState) -> Array<Items>;
    fn buy_item(ref self: TContractState, productId: u32, quantity: u32) -> bool;
    fn buy_item_by_name(ref self: TContractState, productname: felt252, quantity: u32) -> bool;
    fn buy_product(ref self: TContractState, productId: u32, quantity: u32, price: u32) -> bool;
}
