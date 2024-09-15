mod types;

use ethers::contract::abigen;
use ethers::middleware::SignerMiddleware;
use ethers::prelude::*;
use hex_literal::hex;
use prost::Message;
use std::collections::{HashMap, HashSet};
use std::str::FromStr;
use std::sync::Arc;
use std::time::SystemTime;
use stream::EventStream;
use tokio::fs;
use tokio::sync::Mutex;
use tokio::{sync::mpsc, task::JoinHandle};
use tonic::transport::Channel;
use tonic::Request;
use types::{Tron, ZkSync};
use wallet_client::WalletClient;
use zksync_web3_rs::providers::{Middleware, Provider};
use zksync_web3_rs::signers::{LocalWallet, Signer};
use zksync_web3_rs::types::H160;
use zksync_web3_rs::ZKSWallet;

tonic::include_proto!("protocol");

abigen!(UntronV1, "../contracts/zkout/UntronV1.sol/UntronV1.json");

#[allow(clippy::type_complexity)]
async fn run_active_address_listener(
    mut stream: EventStream<
        '_,
        SubscriptionStream<'_, Ws, Log>,
        ActionChainUpdatedFilter,
        ContractError<SignerMiddleware<Provider<Ws>, LocalWallet>>,
    >,
    sender: mpsc::Sender<ActionChainUpdatedFilter>,
) {
    while let Some(event) = stream.next().await {
        let Ok(event) = event else {
            tracing::error!("Failed to get event");
            continue;
        };

        let receiver: H160 = event.receiver.to_owned();
        let timestamp = event.timestamp.as_u64();

        match sender.send(event).await {
            Ok(_) => tracing::debug!(
                "Sent new action to Tron listener thread: receiver {:?}, timestamp {}",
                receiver.to_string(),
                timestamp
            ),
            Err(_) => tracing::error!("Failed to send new action to Tron listener thread"),
        };
    }
}

async fn run_order_listener(
    contract: UntronV1<SignerMiddleware<Provider<Ws>, LocalWallet>>,
    orders: Arc<Mutex<HashMap<[u8; 32], Order>>>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let event = contract.event::<OrderCreatedFilter>();
    let order_created = event.subscribe().await?;

    Ok(())
}

async fn run_zksync(
    config: ZkSync,
    sender: mpsc::Sender<ActionChainUpdatedFilter>,
    orders: Arc<Mutex<HashMap<[u8; 32], Order>>>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let wallet = {
        let era_provider = Provider::<Ws>::connect(&config.rpc).await?;

        let chain_id = era_provider.get_chainid().await?;
        let l2_wallet =
            LocalWallet::from_str(&config.private_key)?.with_chain_id(chain_id.as_u64());
        ZKSWallet::new(l2_wallet, None, Some(era_provider.clone()), None)?
    };

    let contract = UntronV1::new(
        H160::from_str(&config.untron_contract_address)?,
        wallet.get_era_provider()?,
    );

    let event = contract.event::<ActionChainUpdatedFilter>();
    let action_chain_updates = event.subscribe().await?;

    let active_address_listener =
        tokio::spawn(run_active_address_listener(action_chain_updates, sender));
    let order_listener = tokio::spawn(run_order_listener(contract.clone(), orders.clone()));

    tokio::try_join!(active_address_listener, order_listener)?;

    Ok(())
}

async fn run_transfer_listener(
    mut client: WalletClient<Channel>,
    active_addresses: Arc<Mutex<HashMap<H160, u64>>>,
    sender: mpsc::Sender<ActionChainUpdatedFilter>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let request = Request::new(EmptyMessage {});

    let response = client.get_now_block2(request).await?;
    let block = response.into_inner();

    for transaction in block.transactions {
        let transaction = transaction.transaction.unwrap();

        let contract = transaction.raw_data.unwrap().contract[0].clone();
        if contract.r#type != 31 {
            // TriggerSmartContract
            continue;
        }

        let call =
            TriggerSmartContract::decode(contract.parameter.unwrap().value.as_slice()).unwrap();

        if call.contract_address != hex!("41a614f803b6fd780986a42c78ec9c7f77e6ded13c") {
            // USDT Tron address in hex format
            continue;
        }

        let to = H160::from_slice(&call.data[16..36]);
        let value = u64::from_be_bytes(call.data[60..68].try_into().unwrap());

        let mut active_addresses = active_addresses.lock().await;

        if !active_addresses.contains_key(&to) {
            continue;
        }

        // what's happening:
        // initially, active addresses store the size of the order that occupied this address.
        // when a transfer happens, the size is reduced by the amount of USDT being transferred.
        // when the size reaches 0, the address is removed from the active addresses and passed to the fulfiller.
        let size = active_addresses.get_mut(&to).unwrap();
        *size = size.saturating_sub(value);

        if *size == 0 {
            active_addresses.remove(&to);
        }
    }

    Ok(())
}

async fn run_tron(
    config: Tron,
    mut receiver: mpsc::Receiver<ActionChainUpdatedFilter>,
    orders: Arc<Mutex<HashMap<[u8; 32], Order>>>,
) -> Result<(), Box<dyn std::error::Error>> {
    let client = WalletClient::connect(config.rpc.clone()).await?;

    let active_addresses = Arc::new(Mutex::new(HashMap::new()));

    let transfer_listener = tokio::spawn(run_transfer_listener(client, active_addresses.clone()));

    while let Some(event) = receiver.recv().await {
        tracing::info!("Received event: {:?}", event);

        let mut active_addresses = active_addresses.lock().await;

        if active_addresses.contains_key(&event.receiver) {
            active_addresses.remove(&event.receiver);
        } else {
            active_addresses.insert(event.receiver, event.timestamp);
        }
    }

    tokio::try_join!(transfer_listener)?;

    Ok(())
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    tracing::info!("Starting order fulfiller");
}
