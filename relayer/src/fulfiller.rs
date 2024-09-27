use crate::zksync::ZkSyncClient;
use std::error::Error;
use std::sync::Arc;
use tokio::sync::mpsc::Receiver;
use tracing::warn;
use untron_program::OrderState;

pub struct Fulfiller {
    zksync_client: Arc<ZkSyncClient>,
    closed_orders_rx: Receiver<Vec<([u8; 32], OrderState)>>,
}

impl Fulfiller {
    pub fn new(
        zksync_client: Arc<ZkSyncClient>,
        closed_orders_rx: Receiver<Vec<([u8; 32], OrderState)>>,
    ) -> Self {
        Self {
            zksync_client,
            closed_orders_rx,
        }
    }

    pub async fn run(mut self) -> Result<(), Box<dyn Error>> {
        let mut order_buffer = vec![];

        while let Some(mut closed_orders) = self.closed_orders_rx.recv().await {
            // only keep those orders that have inflow == size
            closed_orders.retain(|(_, order_state)| order_state.inflow == order_state.size);

            // push order ids to the buffer
            order_buffer.extend(closed_orders.iter().map(|(order_id, _)| order_id));

            // Calculate how many orders we can fulfill with our funds

            let mut ngmi_orders = vec![];
            let mut fulfiller_total;
            loop {
                fulfiller_total = self
                    .zksync_client
                    .calculate_fulfiller_total(&order_buffer)
                    .await?;
                if fulfiller_total <= self.zksync_client.get_usdt_balance().await? {
                    // Handle insufficient funds or other errors
                    break;
                }
                if let Some(order_id) = order_buffer.pop() {
                    ngmi_orders.push(order_id);
                } else {
                    break;
                }
            }

            // Fulfill orders

            if !order_buffer.is_empty() {
                self.zksync_client
                    .fulfill_orders(order_buffer, fulfiller_total)
                    .await?;
            } else {
                warn!("Relayer EOA has no USDT to fulfill at least 1 order. Skipping all orders.");
            }

            order_buffer = ngmi_orders;
        }

        Ok(())
    }
}
