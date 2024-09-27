use ethers::contract::abigen;
use ethers::middleware::SignerMiddleware;
use ethers::prelude::*;
use k256::ecdsa::SigningKey;
use std::str::FromStr;
use tokio::sync::mpsc::Sender;
use untron_program::Action;
use zksync_web3_rs::providers::{Middleware, Provider};
use zksync_web3_rs::signers::{LocalWallet, Signer};
use zksync_web3_rs::types::H160;
use zksync_web3_rs::ZKSWallet;

abigen!(
    UntronCore,
    "../contracts/zkout/UntronCore.sol/UntronCore.json"
);

abigen!(USDT, "../contracts/zkout/ERC20.sol/ERC20.json");

pub struct ZkSyncClient {
    pub wallet: ZKSWallet<Provider<Ws>, SigningKey>,
    pub contract: UntronCore<SignerMiddleware<Provider<Ws>, LocalWallet>>,
    pub usdt: USDT<SignerMiddleware<Provider<Ws>, LocalWallet>>,
}

impl ZkSyncClient {
    pub async fn new(
        config: &crate::config::ZkSyncConfig,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        let wallet = {
            let era_provider = Provider::<Ws>::connect(&config.rpc).await?;

            let chain_id = era_provider.get_chainid().await?;
            let l2_wallet =
                LocalWallet::from_str(&config.private_key)?.with_chain_id(chain_id.as_u64());
            ZKSWallet::new(l2_wallet, None, Some(era_provider.clone()), None)?
        };

        let contract = UntronCore::new(
            H160::from_str(&config.core_address)?,
            wallet.get_era_provider()?,
        );

        let usdt = USDT::new(
            H160::from_str(&config.usdt_address)?,
            wallet.get_era_provider()?,
        );

        Ok(Self {
            wallet,
            contract,
            usdt,
        })
    }

    pub async fn start_listener(
        &self,
        pending_actions: Sender<Action>,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let event = self.contract.event::<ActionChainUpdatedFilter>();
        let mut action_chain_updates = event.subscribe().await?;

        while let Some(Ok(event)) = action_chain_updates.next().await {
            tracing::info!("Received ActionChainUpdated event: {:?}", event);

            let action = Action {
                prev: event.prev_order_id,
                address: event.receiver.into(),
                timestamp: event.timestamp.as_u64(),
                min_deposit: event.min_deposit.as_u64(),
                size: event.size.as_u64(),
            };

            if let Err(e) = pending_actions.send(action).await {
                tracing::error!("Failed to send Action to pending_actions: {}", e);
            }
        }

        Ok(())
    }

    pub async fn vkey(&self) -> [u8; 32] {
        self.contract.vkey().call().await.unwrap()
    }

    pub async fn get_usdt_balance(&self) -> Result<u64, Box<dyn std::error::Error>> {
        Ok(self
            .usdt
            .balance_of(self.wallet.l2_address())
            .call()
            .await?
            .as_u64())
    }

    pub async fn calculate_fulfiller_total(
        &self,
        order_ids: &[[u8; 32]],
    ) -> Result<u64, Box<dyn std::error::Error>> {
        Ok(self
            .contract
            .calculate_fulfiller_total(order_ids.to_vec())
            .call()
            .await?
            .0
            .as_u64())
    }

    pub async fn fulfill_orders(
        &self,
        order_ids: Vec<[u8; 32]>,
        total: u64,
    ) -> Result<(), Box<dyn std::error::Error>> {
        self.contract
            .fulfill(order_ids, U256::from(total))
            .send()
            .await?;
        Ok(())
    }

    pub async fn close_orders(
        &self,
        proof: Vec<u8>,
        public_inputs: Vec<u8>,
    ) -> Result<(), Box<dyn std::error::Error>> {
        self.contract
            .close_orders(Bytes::from(proof), Bytes::from(public_inputs))
            .send()
            .await?;
        Ok(())
    }
}
