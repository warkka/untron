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
// TODO: calculate it more accurately
const RECONSTRUCT_CYCLE_COUNT: u32 = 2_000_000;

const ORDER_TTL: u32 = 300; // seconds

type PublicValues = sol! {
    tuple(uint32,uint32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint64)
};

type OrderChain = sol! {
    tuple(bytes32,uint32,address)
};

type Block = sol! {
    tuple(bytes32,uint32,bytes32,uint32)
};

type Inflows = sol! {
    tuple(address,uint64)[]
};

#[derive(Clone)]
struct OrderState {
    timestamp: u32,
    inflow: u64,
    cycles_spent: u32,
}

pub fn main() {
    let mut state = HashMap::new();
    let mut closed_orders = HashMap::new();
    let mut active_addresses = HashSet::new();

    let state_length = read::<u32>();
    let mut state_print = Vec::with_capacity((32 * state_length) as usize);
    for _ in 0..state_length {
        let address = read::<[u8; 20]>();
        let timestamp = read::<u32>();
        let inflow = read::<u64>();

        state_print.extend_from_slice(&address);
        state_print.extend_from_slice(&timestamp.to_be_bytes());
        state_print.extend_from_slice(&inflow.to_be_bytes());

        state.insert(
            address,
            OrderState {
                timestamp,
                inflow,
                cycles_spent: 0,
            },
        );
    }

    let mut old_state_hash = [0u8; 32];
    old_state_hash.copy_from_slice(&hash(&state_print));

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
                cycles_spent: 0,
            },
        );
    }

    let start_block = read::<u32>();
    let end_block = read::<u32>();

    let mut blockprint = read::<[u8; 32]>();

    for block_number in start_block..=end_block {
        let timestamp = read::<u32>();
        let tx_count = read::<u32>();

        let mut txs = Vec::new();
        for _ in 0..tx_count {
            // txs must be inputted in such an order that
            // their SHA256 hashes are sorted alphabetically
            txs.push(read_vec());
        }

        let state_copy = state.clone();
        for (address, order) in state_copy {
            if order.timestamp > timestamp + ORDER_TTL {
                state.remove(&address);
                closed_orders.insert(address, order);
                active_addresses.remove(&address);
            } else if timestamp < order.timestamp {
                continue;
            } else {
                active_addresses.insert(address);
            }
        }

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

        for address in active_addresses.iter() {
            state.get_mut(address).unwrap().cycles_spent +=
                RECONSTRUCT_CYCLE_COUNT / active_addresses.len() as u32;
        }

        let block = Block::abi_encode(&(blockprint, block_number, tx_root, timestamp));
        blockprint.copy_from_slice(&hash(&block));
    }

    let mcycles_cost = read::<u64>(); // USDT cost per 1M cycles

    let mut paymaster_fine = 0u64;
    let mut invoice = 0u64;

    let mut state_print = Vec::new();
    for (address, order) in state.iter() {
        state_print.extend_from_slice(address);
        state_print.extend_from_slice(&order.timestamp.to_be_bytes());

        let price = order.cycles_spent as u64 * mcycles_cost / 1_000_000;
        invoice += price;
        paymaster_fine += price.saturating_sub(order.inflow);
        state_print.extend_from_slice(&(order.inflow.saturating_sub(price)).to_be_bytes());
    }

    let mut new_state_hash = [0u8; 32];
    new_state_hash.copy_from_slice(&hash(&state_print));

    let mut inflows_hash = [0u8; 32];
    let inflows = Inflows::abi_encode(
        &closed_orders
            .into_iter()
            .map(|(address, value)| (address, value.inflow))
            .collect::<Vec<([u8; 20], u64)>>(),
    );
    inflows_hash.copy_from_slice(&hash(&inflows));

    let public_values = PublicValues::abi_encode(&(
        start_block,
        end_block,
        blockprint,
        old_state_hash,
        new_state_hash,
        inflows_hash,
        mcycles_cost,
        invoice,
        paymaster_fine,
    ));

    commit_slice(&public_values);
}
