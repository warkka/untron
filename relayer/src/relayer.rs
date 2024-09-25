use crate::config::Config;
use crate::prover::Prover;
use crate::tron::TronClient;
use crate::zksync::ZkSyncClient;
use std::sync::Arc;
use std::time::SystemTime;
use tokio::sync::{mpsc, Mutex};
use tokio::task;
use tracing::info;
use untron_program::{Execution, State};

pub struct UntronRelayer {
    config: Config,
    tron_client: TronClient,
    zksync_client: Arc<ZkSyncClient>,
    prover: Prover,
    state: Arc<Mutex<State>>,
}

impl UntronRelayer {
    pub async fn new(config: Config) -> Result<Self, Box<dyn std::error::Error>> {
        let tron_client = TronClient::new(&config.tron.rpc).await?;
        let zksync_client = Arc::new(ZkSyncClient::new(&config.zksync).await?);
        let prover = Prover::new(
            include_bytes!("../../program/elf/riscv32im-succinct-zkvm-elf"),
            zksync_client.clone(),
        );

        // Reconstruct initial state from the contract
        let state = Arc::new(Mutex::new(State::default())); // TODO: Replace with actual reconstruction logic

        Ok(Self {
            config,
            tron_client,
            zksync_client,
            prover,
            state,
        })
    }

    pub async fn run(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        // Channel for communication between relayer and fulfiller
        let (tx, rx) = mpsc::channel(32);

        // Spawn the fulfiller task
        let fulfiller =
            crate::fulfiller::Fulfiller::new(self.zksync_client.clone(), self.state.clone(), rx);

        task::spawn(async move {
            if let Err(e) = fulfiller.run().await {
                eprintln!("Fulfiller error: {}", e);
            }
        });

        // Main relayer loop
        loop {
            // Fetch new actions and blocks
            // Update state
            // Send closed orders to fulfiller via channel
            // Generate ZK proofs when necessary
            // Sleep or wait for events
        }
    }

    // Additional methods for state reconstruction and STF execution
}
