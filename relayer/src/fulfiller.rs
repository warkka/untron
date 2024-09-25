use crate::config::Config;
use crate::zksync::ZkSyncClient;
use std::error::Error;
use std::sync::Arc;
use tokio::sync::mpsc::Receiver;
use tokio::sync::Mutex;
use untron_program::State;

pub struct Fulfiller {
    zksync_client: Arc<ZkSyncClient>,
    state: Arc<Mutex<State>>,
    closed_orders_rx: Receiver<Vec<untron_program::Order>>,
}

impl Fulfiller {
    pub fn new(
        zksync_client: Arc<ZkSyncClient>,
        state: Arc<Mutex<State>>,
        closed_orders_rx: Receiver<Vec<untron_program::Order>>,
    ) -> Self {
        Self {
            zksync_client,
            state,
            closed_orders_rx,
        }
    }

    pub async fn run(mut self) -> Result<(), Box<dyn Error>> {
        while let Some(closed_orders) = self.closed_orders_rx.recv().await {
            // For each closed order, advance funds to the beneficiary
            // Handle insufficient funds or other errors
        }

        Ok(())
    }
}
