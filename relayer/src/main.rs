use crate::config::Config;
use tokio::fs;
use tracing_subscriber;

mod config;
mod fulfiller;
mod prover;
mod relayer;
mod tron;
mod zksync;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();
    tracing::info!("Starting Untron relayer");

    let config_data = fs::read_to_string("config.toml").await?;
    let config: Config = toml::from_str(&config_data)?;

    tracing::info!("Config: {:?}", config);

    let mut relayer = relayer::UntronRelayer::new(config).await?;
    tracing::info!("Untron relayer initialized");

    relayer.run().await?;

    Ok(())
}
