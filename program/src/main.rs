#![no_main]
sp1_zkvm::entrypoint!(main);

mod crypto;
mod protobuf;

use std::collections::{HashMap, HashSet};

use alloy_sol_types::{sol, SolType};
use sp1_zkvm::io::*;

use crypto::*;

// the cycle count of reconstructing and revealing the tx from the tx root
// e.g. if there are 100 txs in the block, the cycle count of processing
// a single block will be approx RECONSTRUCT_CYCLE_COUNT * 100.
// there's also a small overhead from lookups (comparing USDT transfers
// to each active address) but it's somewhat negligible
//
// our napkin benchmark shows about 5k cycles per 1 tx and there's a little overhead
// for special cases and kinda reward for the relayer
const RECONSTRUCT_CYCLE_COUNT: u32 = 10000;

const ORDER_TTL: u32 = 300_000; // milliseconds

type PublicValues = sol! {
    tuple(uint32,uint32,bytes32,bytes32,bytes32,bytes32,bytes32,uint64)
};

type OrderChain = sol! {
    tuple(bytes32,uint32,address)
};

type Block = sol! {
    tuple(bytes32,uint32,bytes32,uint32)
};

type State = sol! {
    tuple(address,uint32,uint64,(address,uint64)[])[]
};

#[derive(Clone, Debug)]
struct OrderState {
    timestamp: u32,
    inflow: u64,
    relayer_costs: HashMap<[u8; 20], u64>,
}

fn blockprint(prev_blockprint: &[u8; 32], blocks: &[(u32, [u8; 32], u32)]) -> [u8; 32] {
    let mut blockprint = *prev_blockprint;
    for (block_number, tx_root, timestamp) in blocks {
        let data = Block::abi_encode(&(blockprint, block_number, tx_root, timestamp));
        blockprint.copy_from_slice(&hash(&data));
    }
    blockprint
}

fn build_state_hash(state: &HashMap<[u8; 20], OrderState>) -> [u8; 32] {
    #[allow(clippy::type_complexity)]
    let tupled_state: Vec<([u8; 20], u32, u64, Vec<([u8; 20], u64)>)> = state
        .iter()
        .map(|(address, order)| {
            (
                *address,
                order.timestamp,
                order.inflow,
                order
                    .relayer_costs
                    .iter()
                    .map(|(relayer, cost)| (*relayer, *cost))
                    .collect::<Vec<([u8; 20], u64)>>(),
            )
        })
        .collect();

    let state_print = State::abi_encode(&tupled_state);

    let mut state_hash = [0u8; 32];
    state_hash.copy_from_slice(&hash(&state_print));
    state_hash
}

pub fn main() {
    let mut state = HashMap::new();
    let mut closed_orders = HashMap::new();
    let mut active_addresses = HashSet::new();

    let my_address = read::<[u8; 20]>();

    let state_length = read::<u32>();
    for _ in 0..state_length {
        let mut relayer_costs = HashMap::new();

        let address = read::<[u8; 20]>();
        let timestamp = read::<u32>();
        let inflow = read::<u64>();
        let relayers_count = read::<u32>();

        for _ in 0..relayers_count {
            let relayer_address = read::<[u8; 20]>();
            let relayer_cost = read::<u64>();
            relayer_costs.insert(relayer_address, relayer_cost);
        }

        state.insert(
            address,
            OrderState {
                timestamp,
                inflow,
                relayer_costs,
            },
        );
    }

    let old_state_hash = build_state_hash(&state);

    let mut order_chain = read::<[u8; 32]>();
    let order_count = read::<u32>();
    for _ in 0..order_count {
        let mut element = Vec::with_capacity(32 * 3);
        element.extend_from_slice(&order_chain);

        let timestamp = read::<u32>();
        let address = read::<[u8; 20]>();

        let order = OrderChain::abi_encode(&(order_chain, timestamp, address));
        order_chain.copy_from_slice(&hash(&order));

        state.insert(
            address,
            OrderState {
                timestamp,
                inflow: 0,
                relayer_costs: HashMap::new(),
            },
        );
    }

    let start_block = read::<u32>();
    let end_block = read::<u32>();

    let mut end_blockprint = read::<[u8; 32]>(); // blockprint(start_block - 1)
    let mcycles_cost = read::<u64>(); // USDT cost per 1M cycles

    for block_number in start_block..=end_block {
        let timestamp = read::<u32>();
        let tx_count = read::<u32>();

        let mut txs = Vec::with_capacity(tx_count as usize);
        for _ in 0..tx_count {
            // txs must be inputted in such an order that
            // their SHA256 hashes are sorted alphabetically
            txs.push(read_vec());
        }

        let state_copy = state.clone();
        for (address, order) in state_copy {
            if timestamp > order.timestamp + ORDER_TTL {
                state.remove(&address);
                closed_orders.insert(address, order);
                active_addresses.remove(&address);
            } else if timestamp < order.timestamp {
                continue;
            } else {
                active_addresses.insert(address);
            }
        }

        println!(
            "{} {} {}",
            state.len(),
            active_addresses.len(),
            closed_orders.len()
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
                state.get_mut(&transfer.to).unwrap().inflow += transfer.value;
            }
        }

        let aa_count = active_addresses.len() as u64;

        for address in active_addresses.iter() {
            let order_state = state.get_mut(address).unwrap();
            *order_state.relayer_costs.entry(my_address).or_insert(0) +=
                RECONSTRUCT_CYCLE_COUNT as u64 * mcycles_cost / 1_000_000 / aa_count;
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
        order_chain,
        old_state_hash,
        new_state_hash,
        closed_orders_hash,
        mcycles_cost,
    ));

    commit_slice(&public_values);
}
