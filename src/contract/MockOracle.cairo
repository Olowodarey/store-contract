// SPDX-License-Identifier: MIT
// Mock Oracle for Testing

#[starknet::interface]
trait IMockOracle<TContractState> {
    fn get_data_median(self: @TContractState, data_type: felt252) -> (u128, u64, u32, u32);
}




#[starknet::contract]
mod MockOracle {
    use super::IMockOracle;

    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };

    #[storage]
    struct Storage {
        mock_price: u128,
    }

    #[constructor]
    fn constructor(ref self: ContractState, initial_price: u128) {
        self.mock_price.write(initial_price);
    }

    #[abi(embed_v0)]
    impl MockOracleImpl of IMockOracle<ContractState> {
        fn get_data_median(self: @ContractState, data_type: felt252) -> (u128, u64, u32, u32) {
            // Return fixed price for testing: $1.50 = 150000000 (with 8 decimals)
            let price = self.mock_price.read();
            let timestamp = 1234567890_u64;
            let num_sources = 1_u32;
            let decimals = 8_u32;
            
            (price, timestamp, num_sources, decimals)
        }
    }
}