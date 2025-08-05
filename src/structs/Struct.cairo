use starknet::ContractAddress;


#[derive(Clone, PartialEq, Debug, Drop, Serde, starknet::Store)]
pub struct Items {
    pub id: u32,
    pub productname: felt252,
    pub price: u32,
    pub quantity: u32,
    pub Img: ByteArray,
}


#[derive(Clone, PartialEq, Debug, Drop, Serde)]
pub struct CartItem {
    pub product_id: u32,
    pub quantity: u32,
    pub expected_price: u32 // Price per unit in cents
}


#[derive(Drop, Serde, Debug, PartialEq, starknet::Event, starknet::Store)]
pub struct PurchaseReceipt {
    pub buyer: ContractAddress,
    pub product_id: u32,
    pub product_name: felt252,
    pub quantity: u32,
    pub total_price_cents: u32,
    pub total_price_tokens: u256,
    pub timestamp: u64,
    pub receipt_id: u256,
}
