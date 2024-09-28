use crate::config::Config;
use tokio::fs;

mod config;
mod fulfiller;
mod prover;
mod relayer;
mod tron;
mod zksync;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();

    loop {
        tracing::info!("Starting Untron relayer");

        let config_data = fs::read_to_string("config.toml").await?;
        let config: Config = toml::from_str(&config_data)?;

        tracing::info!("Config: {:?}", config);

        let relayer = relayer::UntronRelayer::new(config).await?;
        tracing::info!("Untron relayer initialized");

        tracing::info!("UNTRON THE FINANCE 2024 H00K SOLUTIONS WORLDWIDE");
        if let Err(e) = relayer.run().await {
            tracing::error!("Relayer has crashed: {}", e);
        }

        tracing::info!("Relayer has crashed, restarting...");
    }
}
