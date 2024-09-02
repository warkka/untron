pub mod crypto;
pub mod protobuf;

use std::collections::HashMap;

use alloy_sol_types::{sol, SolType};
use serde::{Deserialize, Serialize};

pub const ORDER_TTL: u64 = 100; // blocks
pub const BLOCK_TIME: u64 = 3000; // milliseconds
pub const MAINTENANCE_PERIOD_BLOCK_OFFSET: u64 = 0; // TODO: find any maintenance block to determine this

pub type OrderChain = sol! {
    tuple(bytes32,uint64,address,uint64)
};

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct OrderState {
    pub address: [u8; 20],
    pub timestamp: u64,
    pub inflow: u64,
    pub min_deposit: u64,
}

#[derive(Default, Serialize, Deserialize, Clone, Debug)]
pub struct State {
    pub latest_block_id: [u8; 32],
    pub latest_timestamp: u64,
    pub cycle: Vec<[u8; 20]>,
    pub srs: [[u8; 20]; 27],
    pub votes: HashMap<[u8; 20], u64>,

    pub orders: HashMap<[u8; 32], OrderState>,
    pub order_chain: [u8; 32],
}

#[derive(Serialize, Deserialize)]
pub struct Order {
    pub timestamp: u64,
    pub address: [u8; 20],
    pub min_deposit: u64,
}

#[derive(Serialize, Deserialize)]
pub struct RawBlock {
    pub raw_data: Vec<u8>,
    pub signature: Vec<u8>,
    pub txs: Vec<Vec<u8>>,
}

pub struct Execution {
    pub me: [u8; 20],
    pub orders: Vec<Order>,
    pub blocks: Vec<RawBlock>,
}

pub fn block_id_to_number(block_id: [u8; 32]) -> u64 {
    let mut block_number = [0u8; 8];
    block_number.copy_from_slice(&block_id[..8]);
    u64::from_be_bytes(block_number)
}

pub fn stf(mut state: State, execution: Execution) -> (State, Vec<([u8; 32], u64)>) {
    for order in execution.orders {
        let chained_order = OrderChain::abi_encode(&(
            state.order_chain,
            order.timestamp,
            order.address,
            order.min_deposit,
        ));
        state.order_chain = crypto::hash(&chained_order);
        state.orders.insert(
            state.order_chain,
            OrderState {
                address: order.address,
                timestamp: order.timestamp,
                inflow: 0,
                min_deposit: order.min_deposit,
            },
        );
    }

    let mut closed_orders = Vec::new();
    let mut active_addresses: HashMap<[u8; 20], [u8; 32]> = HashMap::new();
    let block_count = execution.blocks.len();
    for (i, block) in execution.blocks.into_iter().enumerate() {
        // consensus checks (pka zktron)

        let raw_data_hash = crypto::hash(&block.raw_data);

        let block_header =
            protobuf::parse_block_header(state.latest_block_id, &block.raw_data, raw_data_hash);

        let public_key = crypto::recover_public_key(&block.signature, raw_data_hash);
        let sr = crypto::public_key_to_address(&public_key);
        assert!(state.srs.contains(&sr));

        if state.cycle.len() == 18 {
            state.cycle.remove(0);
        }
        assert!(!state.cycle.contains(&sr));
        state.cycle.push(sr);

        // we do verify the latest 19 blocks but don't check their contents
        // so that all blocks that were checked are finalized
        if block_count - i < 19 {
            continue;
        }

        state.latest_block_id = block_header.new_block_id;
        state.latest_timestamp = block_header.timestamp;

        // content checks (pka walkthrough)

        let orders_copy = state.orders.clone();
        for (order_id, order) in orders_copy {
            if block_header.timestamp > order.timestamp + ORDER_TTL * BLOCK_TIME {
                state.orders.remove(&order_id);
                closed_orders.push((order_id, order.inflow));
                active_addresses.remove(&order.address);
            } else if block_header.timestamp < order.timestamp {
                continue;
            } else {
                match active_addresses.entry(order.address) {
                    // if the order is already active, we close it
                    std::collections::hash_map::Entry::Occupied(_) => {
                        state.orders.remove(&order_id);
                        closed_orders.push((order_id, order.inflow));
                        active_addresses.remove(&order.address);
                    }
                    // if the order is not active, we activate it
                    std::collections::hash_map::Entry::Vacant(entry) => {
                        entry.insert(order_id);
                    }
                }
            }
        }

        if active_addresses.is_empty() {
            continue;
        }

        let tx_hashes: Vec<[u8; 32]> = block.txs.iter().map(|tx| crypto::hash(tx)).collect();

        let mut tx_root = [0u8; 32];
        tx_root.copy_from_slice(&crypto::create_merkle_tree(&tx_hashes));

        for tx in block.txs.iter() {
            // we only check for USDT transfer (TriggerSmartContract) or VoteWitnessContract

            match protobuf::parse_usdt_transfer(tx) {
                Some(transfer) => {
                    let Some(order_id) = active_addresses.get(&transfer.to) else {
                        continue;
                    };

                    state.orders.get_mut(order_id).unwrap().inflow += transfer.value;
                }
                None => {
                    let Some(vote_tx) = protobuf::parse_vote_tx(tx) else {
                        continue;
                    };

                    for vote in vote_tx.votes {
                        *state.votes.entry(vote.witness_address).or_insert(0) += vote.votes_count;
                    }
                }
            }
        }

        // maintenance period logic

        if (block_id_to_number(state.latest_block_id) + MAINTENANCE_PERIOD_BLOCK_OFFSET)
            .rem_euclid(7200)
            == 0
        {
            let mut votes: Vec<([u8; 20], u64)> = state.votes.into_iter().collect();
            votes.sort_by(|a, b| a.1.cmp(&b.1));
            let candidates: Vec<[u8; 20]> = votes.into_iter().map(|(address, _)| address).collect();
            state
                .srs
                .copy_from_slice(&candidates[candidates.len() - 27..]);

            state.votes = HashMap::new();
        }
    }

    (state, closed_orders)
}
