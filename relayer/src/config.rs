use serde::Deserialize;

#[derive(Deserialize, Debug)]
pub struct Config {
    pub zksync: ZkSyncConfig,
    pub tron: TronConfig,
    pub relay: RelayConfig,
    pub telegram: TelegramConfig,
}

#[derive(Deserialize, Debug)]
pub struct ZkSyncConfig {
    pub rpc: String,
    pub private_key: String,
    pub core_address: String,
    pub usdt_address: String,
    pub fulfill: bool,
}

#[derive(Deserialize, Debug)]
pub struct TronConfig {
    pub rpc: String,
}

#[derive(Deserialize, Debug)]
pub struct RelayConfig {
    pub proof_interval: u64,
    pub min_orders_to_relay: usize,
}

#[derive(Deserialize, Debug)]
pub struct TelegramConfig {
    pub token: String,
    pub chat_id: String,
    pub topic_id: String,
    pub critical_prefix: String,
}
