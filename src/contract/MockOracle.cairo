// SPDX-License-Identifier: MIT
// Mock Oracle for Testing

use pragma_lib::types::{DataType, PragmaPricesResponse};

#[starknet::interface]
trait IMockOracle<TContractState> {
    fn get_data_median(self: @TContractState, data_type: DataType) -> PragmaPricesResponse;
}

#[starknet::contract]
mod MockOracle {
    use pragma_lib::types::{DataType, PragmaPricesResponse};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use super::IMockOracle;

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
        fn get_data_median(self: @ContractState, data_type: DataType) -> PragmaPricesResponse {
            // Return fixed price for testing: $1.50 = 150000000 (with 8 decimals)
            let price = self.mock_price.read();

            PragmaPricesResponse {
                price: price,
                decimals: 8,
                last_updated_timestamp: 1234567890_u64,
                num_sources_aggregated: 1,
                expiration_timestamp: Option::None,
            }
        }
    }
}
