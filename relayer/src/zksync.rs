use ethers::contract::abigen;
use ethers::middleware::SignerMiddleware;
use ethers::prelude::*;
use k256::ecdsa::SigningKey;
use std::str::FromStr;
use std::sync::Arc;
use zksync_web3_rs::providers::{Middleware, Provider};
use zksync_web3_rs::signers::{LocalWallet, Signer};
use zksync_web3_rs::types::H160;
use zksync_web3_rs::ZKSWallet;

abigen!(
    UntronCore,
    "../contracts/zkout/UntronCore.sol/UntronCore.json"
);

pub struct ZkSyncClient {
    pub wallet: ZKSWallet<Provider<Ws>, SigningKey>,
    pub contract: UntronCore<SignerMiddleware<Provider<Ws>, LocalWallet>>,
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

        let event = contract.event::<ActionChainUpdatedFilter>();
        let action_chain_updates = event.subscribe().await?;

        // let active_address_listener =
        //     tokio::spawn(run_active_address_listener(action_chain_updates, sender));
        // let order_listener = tokio::spawn(run_order_listener(contract.clone(), orders.clone()));

        Ok(Self { wallet, contract })
    }

    pub async fn vkey(&self) -> [u8; 32] {
        self.contract.vkey().call().await.unwrap()
    }

    // Additional methods for interacting with the contract
}
