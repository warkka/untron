#![no_main]
sp1_zkvm::entrypoint!(main);

mod crypto;
mod protobuf;

use std::collections::{HashMap, HashSet};

use alloy_sol_types::{sol, SolType};
use sp1_zkvm::io::*;

use crypto::*;

const ORDER_TTL: u32 = 100; // blocks
const BLOCK_TIME: u32 = 3000; // milliseconds

type PublicValues = sol! {
    tuple(address,bytes32,bytes32,uint32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64)
};

type OrderChain = sol! {
    tuple(bytes32,uint32,address,uint64)
};

type EncodedState = sol! {
    tuple(address,uint32,uint64,uint64)[]
};

#[derive(Clone, Debug)]
struct OrderState {
    timestamp: u32,
    inflow: u64,
    min_deposit: u64,
}

fn build_state_hash(state: &HashMap<[u8; 20], OrderState>) -> [u8; 32] {
    let tupled_state: Vec<([u8; 20], u32, u64, u64)> = state
        .iter()
        .map(|(address, order)| (*address, order.timestamp, order.inflow, order.min_deposit))
        .collect();

    let state_print = EncodedState::abi_encode(&tupled_state);
    zktron::hash(&state_print)
}

pub fn main() {
    let mut state = HashMap::new();
    let state_length = read::<u32>();
    for _ in 0..state_length {
        let address = read::<[u8; 20]>();
        let timestamp = read::<u32>();
        let inflow = read::<u64>();
        let min_deposit = read::<u64>();

        state.insert(
            address,
            OrderState {
                timestamp,
                inflow,
                min_deposit,
            },
        );
    }

    let me = read::<[u8; 20]>();

    let old_state_hash = build_state_hash(&state);

    let start_order_chain = read::<[u8; 32]>();
    let mut end_order_chain = start_order_chain;
    let order_count = read::<u32>();

    for _ in 0..order_count {
        let mut element = Vec::with_capacity(32 * 3);
        element.extend_from_slice(&end_order_chain);

        let timestamp = read::<u32>();
        let address = read::<[u8; 20]>();
        let min_deposit = read::<u64>();

        let order = OrderChain::abi_encode(&(end_order_chain, timestamp, address, min_deposit));
        end_order_chain = zktron::hash(&order);

        state.insert(
            address,
            OrderState {
                timestamp,
                inflow: 0,
                min_deposit,
            },
        );
    }

    let start_block = read::<[u8; 32]>();
    let mut end_block = start_block;

    let block_count = read::<u32>();
    assert!(block_count > ORDER_TTL); // so that we don't have >1 queued relayers

    let mut total_fee = 0u64;
    let fee_per_block = read::<u64>();

    let mut closed_orders = HashMap::new();
    let mut active_addresses = HashSet::new();
    let mut end_block_timestamp = 0;
    for _ in 0..block_count {
        let block_raw_data = read_vec();
        let block =
            zktron::parse_block_header(end_block, &block_raw_data, zktron::hash(&block_raw_data));

        end_block_timestamp = block.timestamp;
        let tx_count = read::<u32>();

        let mut txs = Vec::with_capacity(tx_count as usize);
        for _ in 0..tx_count {
            // txs must be inputted in such an order that
            // their SHA256 hashes are sorted alphabetically
            txs.push(read_vec());
        }

        let orders_copy = state.clone();
        for (address, order) in orders_copy {
            if block.timestamp > order.timestamp + ORDER_TTL * BLOCK_TIME {
                state.remove(&address);
                closed_orders.insert(address, order);
                active_addresses.remove(&address);
            } else if block.timestamp < order.timestamp {
                continue;
            } else {
                active_addresses.insert(address);
            }
        }

        if active_addresses.is_empty() {
            continue;
        }

        let tx_hashes: Vec<[u8; 32]> = txs.iter().map(|tx| zktron::hash(tx)).collect();

        let mut tx_root = [0u8; 32];
        tx_root.copy_from_slice(&create_merkle_tree(&tx_hashes));

        for tx in txs.iter() {
            let Some(transfer) = protobuf::parse_usdt_transfer(tx) else {
                continue;
            };

            if active_addresses.contains(&transfer.to)
                && transfer.value >= state.get(&transfer.to).unwrap().min_deposit
            {
                state.get_mut(&transfer.to).unwrap().inflow += transfer.value;
            }
        }

        total_fee += fee_per_block * active_addresses.len() as u64;

        end_block = block.new_block_id;
    }

    let new_state_hash = build_state_hash(&state);
    let closed_orders_hash = build_state_hash(&closed_orders);

    println!("{:?}", &state);

    let public_values = PublicValues::abi_encode(&(
        me,
        start_block,
        end_block,
        end_block_timestamp,
        start_order_chain,
        end_order_chain,
        old_state_hash,
        new_state_hash,
        closed_orders_hash,
        fee_per_block,
        total_fee,
    ));

    commit_slice(&public_values);
}
