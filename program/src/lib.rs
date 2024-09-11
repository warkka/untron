pub mod crypto;
pub mod protobuf;

use std::collections::HashMap;

use alloy_sol_types::{sol, SolType};
use serde::{Deserialize, Serialize};

// how long the program will look for order's receiver address in the transactions of a block
pub const ORDER_TTL: u64 = 100; // blocks

// how often blocks in Tron blockchain are produced
pub const BLOCK_TIME: u64 = 3000; // milliseconds

// proof: https://tronscan.org/#/block/64992129 and https://tronscan.org/#/block/64992130 timestamps differ by 9 secs.
// 64992129 - (64992129 // 7198 * 7198) = 1387
pub const MAINTENANCE_PERIOD_BLOCK_OFFSET: u32 = 1387;

// how often maintenance period happens.
// in docs it's 7200, but actually it's 7198 blocks because maintenance window skips two blocks
pub const MAINTENANCE_PERIOD_INTERVAL: u32 = 7198;

// OrderChain is the format of the order data that's needed for the program, chained with the previous order
pub type OrderChain = sol! {
    tuple(bytes32,uint64,address,uint64)
};

// OrderState is the state of an order in the Untron program
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct OrderState {
    // Tron address (receiver) that we look for in USDT transfers in the blocks
    pub address: [u8; 20],
    // timestamp when the order was created in Tron format (not unix timestamp)
    pub timestamp: u64,
    // how much USDT was deposited to the Tron address above
    pub inflow: u64,
    // minimum amount of USDT transfer for it to be accepted
    // (e.g. if it's 1 USDT, the program won't count 0.5 USDT transfers to the address above)
    pub min_deposit: u64,
}

// State is the state of the Untron program
#[derive(Default, Serialize, Deserialize, Clone, Debug)]
pub struct State {
    // id of the latest zk proven block in the Tron blockchain
    pub latest_block_id: [u8; 32],
    // timestamp of the latest zk proven block in the Tron blockchain
    pub latest_timestamp: u64,
    // 19 latest block proposers. they all must be unique (that is, 19/27 SRs must follow the chain we prove)
    pub cycle: Vec<[u8; 20]>,
    // list of all SRs (super representatives) in the Tron blockchain
    pub srs: [[u8; 20]; 27],
    // votes for SRs
    pub votes: HashMap<[u8; 20], u64>,
    // all currently active orders in the Untron protocol
    pub orders: HashMap<[u8; 32], OrderState>,
    // chained hash of all orders in the Untron protocol
    pub order_chain: [u8; 32],
}

// Order is the data of a new order in the Untron protocol.
// Created in the smart contract and only contains order fields that are needed for the program.
// All other fields are kept in the smart contract, because the program doesn't need them.
#[derive(Serialize, Deserialize)]
pub struct Order {
    // timestamp when the order was created in Tron format (not unix timestamp)
    pub timestamp: u64,
    // Tron address (receiver) that we look for in USDT transfers in the blocks
    pub address: [u8; 20],
    // minimum amount of USDT transfer for it to be accepted
    pub min_deposit: u64,
}

// RawBlock is the data of a block in the Tron blockchain.
// It's needed for the program to check the block contents.
#[derive(Serialize, Deserialize)]
pub struct RawBlock {
    // raw data of the block. contains its timestamp, tx root, etc.
    // it's encoded in protobuf, but we use our own makeshift-but-efficient deserialization (see protobuf.rs)
    pub raw_data: Vec<u8>,
    // signature of the block proposer
    pub signature: Vec<u8>,
    // transactions in the block.
    // they must be used to reconstruct the tx tree which root will be compared to the one in the block header
    pub txs: Vec<Vec<u8>>,
}

// Execution is the payload for the Untron program.
// It's all kept in the private inputs,
// and the smart contract will only receive the results of the execution.
pub struct Execution {
    // new orders that were created in the smart contract
    pub orders: Vec<Order>,
    // new blocks from the Tron blockchain
    pub blocks: Vec<RawBlock>,
}

// block_id_to_number is a helper function to convert a block id to a block number
// in Tron, block id is a sha256 hash of the block header with first 8 bytes set to the block number in big endian.
// however, to save some cycles, we'll use u32 for the block number
pub fn block_id_to_number(block_id: [u8; 32]) -> u32 {
    let mut block_number = [0u8; 4];
    block_number.copy_from_slice(&block_id[4..8]);
    u32::from_be_bytes(block_number)
}

// stf is the state transition function for the Untron program.
// it takes the current state and an execution
// and returns the new state and the closed orders, then passed to the smart contract.
pub fn stf(state: &mut State, execution: Execution) -> Vec<([u8; 32], u64)> {
    // iterate over all new orders to form the new order chain
    for order in execution.orders {
        // encode the order into the chained ABI format
        let chained_order = OrderChain::abi_encode(&(
            state.order_chain,
            order.timestamp,
            order.address,
            order.min_deposit,
        ));
        // hash the chained order and insert it into the state
        state.order_chain = crypto::hash(&chained_order);
        // insert the order data into the state
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

    // this vector will store the closed orders
    let mut closed_orders = Vec::new();
    // this hashmap will store the receiver addresses of the active orders
    // and their order ids
    let mut active_addresses: HashMap<[u8; 20], [u8; 32]> = HashMap::new();
    // count of the blocks to process (needed to skip the contents of the last 19 blocks to ensure Tron's finality)
    let block_count = execution.blocks.len();

    // for simplicity of relayer implementation, we need at least 100 blocks to be processed
    assert!(block_count as u64 > ORDER_TTL);

    // iterate over all new blocks
    for (i, block) in execution.blocks.into_iter().enumerate() {
        // consensus checks (pka zktron)

        // hash the raw_data from the block header
        let raw_data_hash = crypto::hash(&block.raw_data);

        // deserialize raw_data into the BlockHeader struct with all data we need
        // it also validates raw_data by comparing latest_block_id with the prev one specified in the raw_data
        let block_header =
            protobuf::parse_block_header(state.latest_block_id, &block.raw_data, raw_data_hash);

        // recover the proposer's public key from the raw_data hash and proposer signature
        let public_key = crypto::recover_public_key(&block.signature, raw_data_hash);
        // convert the proposer's public key into their address
        let sr = crypto::public_key_to_address(&public_key);
        // verify that the proposer is in the SR set
        assert!(state.srs.contains(&sr));

        // move the cycle forward
        if state.cycle.len() == 19 {
            state.cycle.remove(0);
        }
        // verify that the proposer is not in the cycle (has not proposed the last 19 blocks)
        assert!(!state.cycle.contains(&sr));
        // add the proposer to the cycle
        state.cycle.push(sr);

        // we do verify the latest 19 blocks but don't check their contents
        // so that all blocks that were checked are finalized (19 blocks built on top of them)
        if block_count - i <= 19 {
            continue;
        }

        // update the latest block id and timestamp
        state.latest_block_id = block_header.new_block_id;
        state.latest_timestamp = block_header.timestamp;

        // content checks (pka walkthrough)

        // iterate over all active orders
        let orders_copy = state.orders.clone();
        for (order_id, order) in orders_copy {
            if block_header.timestamp > order.timestamp + ORDER_TTL * BLOCK_TIME {
                // if the order is expired, we close it
                state.orders.remove(&order_id);
                closed_orders.push((order_id, order.inflow));
                active_addresses.remove(&order.address);
            } else if block_header.timestamp < order.timestamp {
                // if the order is not yet live at this block, we don't include it to the active addresses
                continue;
            } else {
                // if the order is live, we...
                match active_addresses.entry(order.address) {
                    // if the address from the order is already active, we close the order
                    // (double order to the same address means it was stopped by the order creator)
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

        // hash all transactions in the block
        let tx_hashes: Vec<[u8; 32]> = block.txs.iter().map(|tx| crypto::hash(tx)).collect();

        // create the merkle tree of the transactions in the block and get its root,
        // then compare the root with the one in the block header
        assert_eq!(crypto::create_merkle_tree(&tx_hashes), block_header.tx_root);

        // iterate over all transactions in the block
        for tx in block.txs.iter() {
            // we only check for USDT transfer (TriggerSmartContract) or VoteWitnessContract

            match protobuf::parse_usdt_transfer(tx) {
                // if it's a USDT transfer, we check if its recipient is in the active addresses
                Some(transfer) => {
                    let Some(order_id) = active_addresses.get(&transfer.to) else {
                        // >99% of Tron txs will actually not be related to any orders or votes
                        // so we spend vast amounts of computation on nothing lmao
                        continue;
                    };

                    // if they are, we add the transfer value to their order's inflow
                    state.orders.get_mut(order_id).unwrap().inflow += transfer.value;
                }
                // if it's not a USDT transfer, we check if it's a vote transaction
                None => {
                    let Some(vote_tx) = protobuf::parse_vote_tx(tx) else {
                        continue;
                    };

                    // iterate over all votes in the transaction
                    for vote in vote_tx.votes {
                        // add the vote count to the vote count of the witness address
                        *state.votes.entry(vote.witness_address).or_insert(0) += vote.votes_count;
                    }
                }
            }
        }

        // maintenance period logic

        // if the current block is a maintenance block, we run the maintenance logic
        if (block_id_to_number(state.latest_block_id) - MAINTENANCE_PERIOD_BLOCK_OFFSET)
            .rem_euclid(MAINTENANCE_PERIOD_INTERVAL)
            == 0
        {
            // get all votes from the state and sort them by the vote count
            let mut votes: Vec<([u8; 20], u64)> = state.votes.clone().into_iter().collect();
            // sort the votes by the vote count
            votes.sort_by(|a, b| a.1.cmp(&b.1));
            // get the top 27 addresses (SR candidates)
            let candidates: Vec<[u8; 20]> = votes.into_iter().map(|(address, _)| address).collect();
            // set the top 27 SRs as the new SR (block producer) set
            state
                .srs
                .copy_from_slice(&candidates[candidates.len() - 27..]);
            // clear the old cycle
            state.cycle.clear();
            // clear the old votes
            state.votes = HashMap::new();
        }
    }

    // return the closed orders
    closed_orders
}
