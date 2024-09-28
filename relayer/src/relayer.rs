use crate::config::Config;
use crate::prover::Prover;
use crate::tron::TronClient;
use crate::zksync::ZkSyncClient;
use prost::Message;
use sp1_sdk::SP1Stdin;
use std::sync::Arc;
use std::time::SystemTime;
use tokio::task;
use tokio::{fs, sync::mpsc};
use tracing::{info, warn};
use untron_program::{block_id_to_number, Execution, RawBlock, State};

pub struct UntronRelayer {
    config: Config,
    tron_client: TronClient,
    zksync_client: Arc<ZkSyncClient>,
    prover: Prover,
    state: State,
}

impl UntronRelayer {
    pub async fn new(config: Config) -> Result<Self, Box<dyn std::error::Error>> {
        let tron_client = TronClient::new(&config.tron.rpc).await?;

        let zksync_client = Arc::new(ZkSyncClient::new(&config.zksync).await?);
        let prover = Prover::new(
            include_bytes!("../../program/elf/riscv32im-succinct-zkvm-elf"),
            zksync_client.clone(),
        );

        // Read the latest state from the latest backup file
        // TODO: Replace this with a proper state reconstruction logic.

        let state = match fs::read_dir("/state").await {
            Ok(mut entries) => {
                let mut latest_file = None;
                let mut latest_modified = None;

                while let Some(entry) = entries.next_entry().await? {
                    if let Ok(metadata) = entry.metadata().await {
                        if let Ok(modified) = metadata.modified() {
                            if latest_modified.map_or(true, |t| modified > t) {
                                latest_file = Some(entry);
                                latest_modified = Some(modified);
                            }
                        }
                    }
                }

                let latest_file = latest_file;

                if let Some(file) = latest_file {
                    let contents = fs::read(file.path()).await?;
                    info!("Loading state from backup: {:?}", file.path());
                    bincode::deserialize(&contents).unwrap_or_else(|_| State::default())
                } else {
                    warn!("No state backups found. Using default state.");
                    State::default()
                }
            }
            Err(_) => {
                warn!("Failed to read state backups directory. Using default state.");
                State::default()
            }
        };

        info!("State loaded: {:?}", state);

        Ok(Self {
            config,
            tron_client,
            zksync_client,
            prover,
            state,
        })
    }

    pub async fn run(mut self) -> Result<(), Box<dyn std::error::Error>> {
        // Channel for communication between relayer and fulfiller
        let (tx, rx) = mpsc::channel(32);

        // Spawn the fulfiller task
        if self.config.zksync.fulfill {
            let fulfiller = crate::fulfiller::Fulfiller::new(self.zksync_client.clone(), rx);

            task::spawn(async move {
                if let Err(e) = fulfiller.run().await {
                    eprintln!("Fulfiller error: {}", e);
                }
            });
        }

        // Spawn action listener
        let (pending_actions_tx, mut pending_actions_rx) = mpsc::channel(1000);
        let zksync_client_clone = self.zksync_client.clone();
        task::spawn(async move {
            if let Err(e) = zksync_client_clone.start_listener(pending_actions_tx).await {
                eprintln!("Action listener error: {}", e);
            }
        });

        let mut latest_known_block_number = block_id_to_number(self.state.latest_block_id);
        let mut latest_proof_timestamp = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let mut total_closed_orders = 0;
        let mut proven_state = self.state.clone();
        let mut pending_actions = vec![];
        let mut pending_blocks = vec![];

        // Main relayer loop
        loop {
            // Fetch new actions and blocks
            loop {
                let block = self.tron_client.get_now_block2().await?;
                let block_number = block.block_header.unwrap().raw_data.unwrap().number as u32;
                info!("Got Tron block: {}", block_number);

                if block_number != latest_known_block_number {
                    break;
                }

                tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            }

            let block = self
                .tron_client
                .get_block_by_number(latest_known_block_number + 1)
                .await?;
            let block_header = block.block_header.unwrap();
            let txs = block
                .transactions
                .into_iter()
                .map(|tx| tx.transaction.unwrap().encode_to_vec())
                .collect();

            latest_known_block_number += 1;

            // Update state

            let mut actions = vec![];
            while let Some(action) = pending_actions_rx.recv().await {
                actions.push(action.clone());
                pending_actions.push(action);
            }

            let block = RawBlock {
                raw_data: block_header.raw_data.unwrap().encode_to_vec(),
                signature: block_header.witness_signature,
                txs,
            };
            pending_blocks.push(block.clone());

            let execution = Execution {
                actions,
                blocks: vec![block],
            };

            let closed_orders = untron_program::stf(&mut self.state, execution);
            total_closed_orders += closed_orders.len();

            info!(
                "State transition executed; {} closed orders found",
                closed_orders.len()
            );

            // Send closed orders to fulfiller via channel

            if !closed_orders.is_empty() {
                tx.send(closed_orders).await?;
            }

            // Check if it's time to generate a proof
            let now = SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_secs();
            if now > latest_proof_timestamp + self.config.relay.proof_interval
                && self.config.relay.min_orders_to_relay >= total_closed_orders
            {
                info!(
                    "Requirements passed; generating a ZK proof for {} Tron blocks, {} new actions, and {} closed orders",
                    pending_blocks.len(),
                    pending_actions.len(),
                    total_closed_orders
                );

                latest_proof_timestamp = now;
                total_closed_orders = 0;
            } else {
                continue;
            }

            let mut stdin = SP1Stdin::new();
            stdin.write_vec(bincode::serialize(&proven_state).unwrap());
            stdin.write_vec(bincode::serialize(&pending_actions).unwrap());
            stdin.write_vec(bincode::serialize(&pending_blocks).unwrap());
            let (proof, public_inputs) = self.prover.generate_proof(stdin).await?;

            // Send proof to the Core contract

            self.zksync_client
                .close_orders(proof, public_inputs)
                .await?;

            proven_state = self.state.clone();

            info!("Successfully sent proof to the Core; state updated");

            // Backup state in "state" directory
            let state_backup = bincode::serialize(&proven_state).unwrap();
            let backup_name = format!("state/state-{}.bin", latest_known_block_number);
            fs::create_dir_all("state").await?;
            fs::write(backup_name, state_backup).await?;

            // Sleep

            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        }
    }

    // Additional methods for state reconstruction and STF execution
}
