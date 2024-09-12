use ethers::contract::abigen;
use ethers::middleware::SignerMiddleware;
use ethers::prelude::*;
use prost::Message;
use sp1_sdk::{ProverClient, SP1Stdin};
use std::str::FromStr;
use std::time::SystemTime;
use tokio::fs;
use tonic::transport::Channel;
use tonic::Request;
use untron_program::{block_id_to_number, Execution};
use untron_program::{crypto::hash, RawBlock, State};
use zksync_web3_rs::providers::{Middleware, Provider};
use zksync_web3_rs::signers::{LocalWallet, Signer};
use zksync_web3_rs::types::H160;
use zksync_web3_rs::ZKSWallet;

use untron_relayer::proto::{wallet_client::WalletClient, BlockExtention, NumberMessage};
use untron_relayer::types::Config;

abigen!(
    UntronCore,
    "../contracts/zkout/UntronCore.sol/UntronCore.json"
);

const ELF: &[u8] = include_bytes!("../../program/elf/riscv32im-succinct-zkvm-elf");

impl From<BlockExtention> for RawBlock {
    fn from(block: BlockExtention) -> Self {
        let header = block.block_header.unwrap();
        Self {
            raw_data: header.raw_data.unwrap().encode_to_vec(),
            signature: header.witness_signature,
            txs: block
                .transactions
                .iter()
                .map(|tx| tx.transaction.as_ref().unwrap().encode_to_vec())
                .collect(),
        }
    }
}

impl From<OrderCreatedFilter> for untron_program::Order {
    fn from(event: OrderCreatedFilter) -> Self {
        Self {
            timestamp: event.timestamp.as_u64(),
            address: event.receiver.into(),
            min_deposit: event.min_deposit.as_u64(),
        }
    }
}

async fn get_block_by_number(
    client: &mut WalletClient<Channel>,
    block_number: u32,
) -> Result<BlockExtention, Box<dyn std::error::Error>> {
    let request = Request::new(NumberMessage {
        num: block_number as i64,
    });

    let response = client.get_block_by_num2(request).await?;
    let block = response.into_inner();

    Ok(block)
}

fn get_time() -> u64 {
    SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

struct UntronRelayer {
    config: Config,
    client: WalletClient<Channel>,
    contract: UntronCore<SignerMiddleware<Provider<Ws>, LocalWallet>>,
    state: State,
    prover: ProverClient,
}
impl UntronRelayer {
    pub async fn new(config: Config) -> Result<Self, Box<dyn std::error::Error>> {
        let client = WalletClient::connect(config.tron.rpc.clone()).await?;

        let wallet = {
            let era_provider = Provider::<Ws>::connect(&config.zksync.rpc).await?;

            let chain_id = era_provider.get_chainid().await?;
            let l2_wallet =
                LocalWallet::from_str(&config.zksync.private_key)?.with_chain_id(chain_id.as_u64());
            ZKSWallet::new(l2_wallet, None, Some(era_provider.clone()), None)?
        };

        let provider = wallet.get_era_provider()?;

        let contract = UntronCore::new(
            H160::from_str(&config.zksync.untron_contract_address)?,
            provider,
        );

        let mut untron = Self {
            config,
            client,
            contract,
            state: State::default(),
            prover: ProverClient::new(),
        };

        untron.reconstruct_state().await?;

        Ok(untron)
    }

    async fn get_latest_orders(
        &self,
    ) -> Result<Vec<untron_program::Order>, Box<dyn std::error::Error>> {
        let mut order_id = self.contract.latest_closed_order().call().await?;
        let latest_timestamp = self.contract.orders(order_id).call().await?.timestamp;
        let mut latest_orders = vec![];

        loop {
            let order = self.contract.orders(order_id).call().await?;
            latest_orders.push(untron_program::Order {
                timestamp: order.timestamp.as_u64(),
                address: order.receiver.into(),
                min_deposit: order.min_deposit.as_u64(),
            });

            if order.timestamp + 300 < latest_timestamp {
                break;
            }

            order_id = order.prev_order;
        }

        Ok(latest_orders)
    }

    async fn get_producer_info(
        &mut self,
        block_number: u32,
    ) -> Result<([[u8; 20]; 27], Vec<[u8; 20]>), Box<dyn std::error::Error>> {
        let mut cycle = vec![];

        for i in 0..27 {
            let block = get_block_by_number(&mut self.client, block_number - i).await?;

            let mut sr = [0u8; 20];
            sr.copy_from_slice(
                &block
                    .block_header
                    .unwrap()
                    .raw_data
                    .unwrap()
                    .witness_address,
            );
            cycle.push(sr);
        }
        let srs = cycle.clone().try_into().unwrap();
        cycle.resize(18, [0u8; 20]);
        cycle.reverse();

        Ok((srs, cycle))
    }

    async fn reconstruct_state(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        let latest_block_id = self.contract.block_id().call().await?;

        tracing::info!(
            "latest zk proven block ID in the contract: {:?}",
            hex::encode(latest_block_id)
        );

        let block_number = block_id_to_number(latest_block_id);
        let block = get_block_by_number(&mut self.client, block_number).await?;

        let _ = {
            let actual_block_id = block.blockid;

            if latest_block_id[8..32] != actual_block_id[8..32] {
                tracing::info!(
                    "Actual block {}: {:?}",
                    block_number,
                    hex::encode(&actual_block_id)
                );
                Err("Block ID mismatch".to_string())
            } else {
                Ok(())
            }
        }.map_err(|e| {
            panic!("Block ID in the contract is not canonical ({}). If you have upgrading rights in this Untron deployment, please change the storage manually.", e);
        });

        let prev_maintenance_number = block_number / 7198 * 7198 - 1;
        let (srs, cycle) = self.get_producer_info(prev_maintenance_number).await?;

        tracing::info!("SR set: {:?}", srs);
        tracing::info!("Last proposers: {:?}", &cycle);
        tracing::info!("Reconstructing previous state...");

        let mut state = State {
            latest_block_id: get_block_by_number(&mut self.client, prev_maintenance_number)
                .await
                .unwrap()
                .blockid
                .try_into()
                .unwrap(),
            latest_timestamp: 0, // unsafe but not necessary in our case
            cycle,
            srs,
            ..Default::default()
        };

        tracing::info!(
            "State reconstructed (circa {})",
            hex::encode(state.latest_block_id)
        );
        tracing::info!("Collecting blocks for execution...");

        let mut blocks = vec![];
        for i in prev_maintenance_number + 1..=block_number {
            let block = get_block_by_number(&mut self.client, i).await.unwrap();
            blocks.push(block.into());
        }

        tracing::info!(
            "Collected {} blocks from {} to {}",
            blocks.len(),
            prev_maintenance_number + 1,
            block_number
        );
        tracing::info!("Executing state transition function...");

        let _ = untron_program::stf(
            &mut state,
            Execution {
                orders: self.get_latest_orders().await?,
                blocks,
            },
        );

        tracing::info!("State transition function executed");
        let state_hash = hash(&bincode::serialize(&state).unwrap());
        tracing::info!("State hash: {:?}", hex::encode(state_hash));

        let contract_state_hash = self.contract.state_hash().call().await?;
        if state_hash != contract_state_hash {
            panic!(
                "State hash mismatch: {} != {}. This might be the case of Core's misconfiguration or a bug in the relayer. If you think it's the latter, please report it to the developers.",
                hex::encode(state_hash),
                hex::encode(contract_state_hash)
            );
        }

        self.state = state;

        Ok(())
    }

    async fn update_state(
        &mut self,
        orders: Vec<untron_program::Order>,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let mut stdin = SP1Stdin::new();
        stdin.write_vec(bincode::serialize(&self.state).unwrap());
        stdin.write_vec(bincode::serialize(&orders).unwrap());

        let mut new_blocks: Vec<RawBlock> = vec![];
        let mut block_number = block_id_to_number(self.state.latest_block_id);
        loop {
            let Ok(block) = get_block_by_number(&mut self.client, block_number).await else {
                break;
            };
            new_blocks.push(block.into());
            block_number += 1;
        }
        stdin.write_vec(bincode::serialize(&new_blocks).unwrap());

        tracing::info!("Input map for the program constructed");

        let (output, report) = self.prover.execute(ELF, stdin.clone()).run()?;

        tracing::info!("Program executed successfully");
        tracing::info!("Output: {:?}", &output);
        tracing::info!("Report: {:?}", report);

        let mut proof = vec![];
        if !self.config.relay.mock {
            tracing::info!("Running PLONK proof generation...");

            let (pk, vk) = self.prover.setup(ELF);
            let result = self.prover.prove(&pk, stdin).plonk().run().unwrap();
            self.prover.verify(&result, &vk)?;
            proof = result.bytes();

            tracing::info!("Proof generated successfully");
        };

        self.contract
            .close_orders(proof.into(), output.to_vec().into())
            .send()
            .await?;

        tracing::info!("Contract call sent!");

        self.reconstruct_state().await?;

        Ok(())
    }

    async fn run(mut self) -> Result<(), Box<dyn std::error::Error>> {
        let event = self.contract.event::<OrderCreatedFilter>();
        let mut stream = event.subscribe().await?;
        let mut orders = vec![];
        tracing::info!("Listening for OrderCreated events...");

        let mut last_proof_time = 0;

        while let Some(event) = stream.next().await {
            tracing::info!("Order created: {:?}", event);
            orders.push(event?.into());

            let time = get_time();
            if orders.len() >= self.config.relay.min_orders_to_relay
                && time - last_proof_time >= self.config.relay.proof_interval
            {
                tracing::info!("Required number of orders created, running ZK proving...");

                self.update_state(orders).await?;
                orders = vec![];
                last_proof_time = time;
            }
        }

        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();
    tracing::info!("Starting Untron relayer");

    let config: Config = toml::from_str(&fs::read_to_string("config.toml").await?)?;
    tracing::info!("Config: {:?}", config);

    let relayer = UntronRelayer::new(config).await?;
    tracing::info!("Untron relayer initialized");

    relayer.run().await?;

    Ok(())
}
