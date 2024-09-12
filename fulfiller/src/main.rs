mod types;

use ethers::contract::abigen;
use ethers::middleware::SignerMiddleware;
use ethers::prelude::*;
use std::str::FromStr;
use std::time::SystemTime;
use stream::EventStream;
use tokio::fs;
use tokio::{sync::oneshot, task::JoinHandle};
use types::ZkSync;
use zksync_web3_rs::providers::{Middleware, Provider};
use zksync_web3_rs::signers::{LocalWallet, Signer};
use zksync_web3_rs::types::H160;
use zksync_web3_rs::ZKSWallet;

use untron_relayer::proto;

abigen!(
    UntronCore,
    "../contracts/zkout/UntronCore.sol/UntronCore.json"
);

#[allow(clippy::type_complexity)]
async fn run_order_listener(
    mut stream: EventStream<
        '_,
        SubscriptionStream<'_, Ws, Log>,
        OrderChainUpdatedFilter,
        ContractError<SignerMiddleware<Provider<Ws>, LocalWallet>>,
    >,
) {
    while let Some(event) = stream.next().await {
        println!("Received event: {:?}", event);
    }
}

async fn run_zksync(
    config: ZkSync,
    receiver: oneshot::Receiver<[u8; 20]>,
    sender: oneshot::Sender<[u8; 20]>,
) -> Result<(), Box<dyn std::error::Error>> {
    let wallet = {
        let era_provider = Provider::<Ws>::connect(&config.rpc).await?;

        let chain_id = era_provider.get_chainid().await?;
        let l2_wallet =
            LocalWallet::from_str(&config.private_key)?.with_chain_id(chain_id.as_u64());
        ZKSWallet::new(l2_wallet, None, Some(era_provider.clone()), None)?
    };

    let contract = UntronCore::new(
        H160::from_str(&config.untron_contract_address)?,
        wallet.get_era_provider()?,
    );

    let event = contract.event::<OrderChainUpdatedFilter>();
    let stream = event.subscribe().await?;

    run_order_listener(stream).await;

    Ok(())
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    tracing::info!("Starting order fulfiller");
}
