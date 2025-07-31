use starknet::ContractAddress;

#[derive(Drop, starknet::Event)]
pub struct PurchaseMade {
    pub buyer: ContractAddress,
    pub product_id: u32,
    pub product_name: felt252,
    pub quantity: u32,
    pub total_price_cents: u32,
    pub total_price_tokens: u256,
    pub timestamp: u64,
}