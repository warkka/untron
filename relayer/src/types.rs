use serde::Deserialize;

#[derive(Deserialize, Debug)]
pub struct Config {
    pub zksync: ZkSync,
    pub tron: Tron,
    pub relay: Relay,
}

#[derive(Deserialize, Debug)]
pub struct ZkSync {
    pub rpc: String,
    pub private_key: String,
    pub untron_contract_address: String,
}

#[derive(Deserialize, Debug)]
pub struct Tron {
    pub rpc: String,
}

#[derive(Deserialize, Debug)]
pub struct Relay {
    pub proof_interval: u64,
    pub min_orders_to_relay: usize,
    pub mock: bool,
}
