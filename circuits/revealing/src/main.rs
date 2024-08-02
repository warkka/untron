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
    tuple(uint32,uint32,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64)
};

type OrderChain = sol! {
    tuple(bytes32,uint32,address)
};

type Block = sol! {
    tuple(bytes32,uint32,bytes32,uint32)
};

type EncodedState = sol! {
    tuple(address,uint64,(address,uint32,uint64)[])
};

#[derive(Clone, Debug)]
struct OrderState {
    timestamp: u32,
    inflow: u64,
}

fn blockprint(prev_blockprint: &[u8; 32], blocks: &[(u32, [u8; 32], u32)]) -> [u8; 32] {
    let mut blockprint = *prev_blockprint;
    for (block_number, tx_root, timestamp) in blocks {
        let data = Block::abi_encode(&(blockprint, block_number, tx_root, timestamp));
        blockprint.copy_from_slice(&hash(&data));
    }
    blockprint
}

fn build_state_hash(state: &State) -> [u8; 32] {
    #[allow(clippy::type_complexity)]
    let tupled_state: Vec<([u8; 20], u32, u64)> = state
        .orders
        .iter()
        .map(|(address, order)| (*address, order.timestamp, order.inflow))
        .collect();

    let state_print = EncodedState::abi_encode(&(state.address, state.total_cost, tupled_state));

    let mut state_hash = [0u8; 32];
    state_hash.copy_from_slice(&hash(&state_print));
    state_hash
}

pub fn main() {
    let mut old_orders = HashMap::new();
    let old_orders_length = read::<u32>();
    for _ in 0..old_orders_length {
        let address = read::<[u8; 20]>();
        let timestamp = read::<u32>();
        let inflow = read::<u64>();
        let relay_cost = read::<u64>();

        old_orders.insert(
            address,
            OrderState {
                timestamp,
                inflow,
                relay_cost,
            },
        );
    }

    let old_state = State {
        address: read::<[u8; 20]>(),
        total_cost: read::<u64>(),
        orders: old_orders,
    };

    let old_state_hash = build_state_hash(&old_state);

    let mut state = State {
        address: read::<[u8; 20]>(),
        total_cost: 0,
        orders: old_state.orders,
    };
    let mut closed_orders = State {
        address: old_state.address,
        total_cost: old_state.total_cost,
        orders: HashMap::new(),
    };

    let start_order_chain = read::<[u8; 32]>();
    let mut end_order_chain = start_order_chain;
    let order_count = read::<u32>();
    for _ in 0..order_count {
        let mut element = Vec::with_capacity(32 * 3);
        element.extend_from_slice(&end_order_chain);

        let timestamp = read::<u32>();
        let address = read::<[u8; 20]>();

        let order = OrderChain::abi_encode(&(end_order_chain, timestamp, address));
        end_order_chain.copy_from_slice(&hash(&order));

        state.orders.insert(
            address,
            OrderState {
                timestamp,
                inflow: 0,
                relay_cost: 0,
            },
        );
    }

    let start_block = read::<u32>();
    let end_block = read::<u32>();
    let mut end_blockprint = read::<[u8; 32]>(); // blockprint(start_block - 1)

    assert!(end_block - start_block + 1 > ORDER_TTL); // so that we don't have >1 queued relayers

    let mcycles_cost = read::<u64>(); // USDT cost per 1M cycles
    let cost_per_tx = RECONSTRUCT_CYCLE_COUNT * mcycles_cost; // WARNING: div by 1m is not applied

    let mut active_addresses = HashSet::new();
    for block_number in start_block..=end_block {
        let timestamp = read::<u32>();
        let tx_count = read::<u32>();

        let mut txs = Vec::with_capacity(tx_count as usize);
        for _ in 0..tx_count {
            // txs must be inputted in such an order that
            // their SHA256 hashes are sorted alphabetically
            txs.push(read_vec());
        }

        let orders_copy = state.orders.clone();
        for (address, order) in orders_copy {
            if timestamp > order.timestamp + ORDER_TTL * BLOCK_TIME {
                state.orders.remove(&address);
                closed_orders.orders.insert(address, order);
                active_addresses.remove(&address);
            } else if timestamp < order.timestamp {
                continue;
            } else {
                active_addresses.insert(address);
            }
        }

        println!(
            "{} {} {}",
            state.orders.len(),
            active_addresses.len(),
            closed_orders.orders.len()
        );

        // if active_addresses.is_empty() {
        //     continue;
        // }

        let tx_hashes: Vec<Vec<u8>> = txs.iter().map(|tx| hash(tx)).collect();

        let mut tx_root = [0u8; 32];
        tx_root.copy_from_slice(&create_merkle_tree(&tx_hashes));

        for tx in txs.iter() {
            let Some(transfer) = protobuf::parse_usdt_transfer(tx) else {
                continue;
            };

            if active_addresses.contains(&transfer.to) {
                state.orders.get_mut(&transfer.to).unwrap().inflow += transfer.value;
            }
        }

        let aa_count = active_addresses.len() as u64;

        let cost_per_block = cost_per_tx * txs.len() as u64 / 1_000_000u64;
        let cost_per_address = cost_per_block.div_ceil(aa_count);
        state.total_cost += cost_per_address * aa_count;

        for address in active_addresses.iter() {
            let order_state = state.orders.get_mut(address).unwrap();
            order_state.relay_cost += cost_per_address;
        }

        end_blockprint = blockprint(&end_blockprint, &[(block_number, tx_root, timestamp)]);
    }

    let new_state_hash = build_state_hash(&state);
    let closed_orders_hash = build_state_hash(&closed_orders);

    println!("{:?}", &state);

    let public_values = PublicValues::abi_encode(&(
        start_block,
        end_block,
        end_blockprint,
        start_order_chain,
        end_order_chain,
        old_state_hash,
        new_state_hash,
        closed_orders_hash,
        total_cost,
    ));

    commit_slice(&public_values);
}
