use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub tron: Tron,
    pub zksync: ZkSync,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tron {
    pub rpc: String,
    pub private_key: String,
    pub auto_creator: bool,
    pub min_fee: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZkSync {
    pub rpc: String,
    pub private_key: String,
    pub untron_contract_address: String,
    pub run_fulfiller: bool,
    pub fulfillment_buffer: u64,
}
