use crate::config::Config;
use tokio::fs;

mod config;
mod fulfiller;
mod prover;
mod relayer;
mod telegram;
mod tron;
mod zksync;
use tokio::sync::mpsc;
use tracing_subscriber::fmt::format::FmtSpan;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let (log_tx, log_rx) = mpsc::channel(100);

    let config_data = fs::read_to_string("config.toml").await?;
    let config: Config = toml::from_str(&config_data)?;

    let subscriber = tracing_subscriber::fmt()
        .with_span_events(FmtSpan::CLOSE)
        .with_writer(move || {
            let tx = log_tx.clone();
            struct Writer {
                tx: mpsc::Sender<String>,
            }
            impl std::io::Write for Writer {
                fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
                    let s = String::from_utf8_lossy(buf).to_string();
                    let _ = self.tx.try_send(s);
                    Ok(buf.len())
                }
                fn flush(&mut self) -> std::io::Result<()> {
                    Ok(())
                }
            }
            Writer { tx }
        })
        .finish();

    tracing::subscriber::set_global_default(subscriber).expect("Failed to set tracing subscriber");

    // Spawn a task to handle log messages
    tokio::spawn(async move {
        telegram::run_log_forwarder(log_rx, config.telegram).await;
    });

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
