#[derive(Clone, PartialEq, Debug, Drop, Serde, starknet::Store)]
pub struct Items {
    pub id: u32,
    pub productname: felt252,
    pub price: u32,
    pub quantity: u32,
    pub Img: ByteArray,
}
