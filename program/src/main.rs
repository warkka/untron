#![no_main]
sp1_zkvm::entrypoint!(main);

use alloy_sol_types::{sol, SolType};
use sp1_zkvm::io::{commit_slice, read_vec};

use untron_program::{crypto, stf, Execution, State};

// UntronPublicValues are the public values (technically the public input) of the Untron program.
// Must be encoded as defined in the smart contracts.
// Format:
// - old_block_id: [u8; 32] (block id of the previous latest zk proven block in the Tron blockchain)
// - old_order_chain: [u8; 32] (chained hash of all orders in the Untron contract before applying the execution)
// - old_state_hash: [u8; 32] (hash of the previous state of the Untron program)

// - new_block_id: [u8; 32] (block id of the latest zk proven block in the Tron blockchain after applying the execution)
// - new_order_chain: [u8; 32] (chained hash of all orders in the Untron contract after applying the execution)
// - new_state_hash: [u8; 32] (hash of the new state of the Untron program after applying the execution)

// - new_timestamp: u64 (timestamp of the latest zk proven block in the Tron blockchain after applying the execution)
// - closed_orders: Vec<(bytes32, uint64)> (list of all orders that must be closed in the Untron contract after applying the execution)
type UntronPublicValues = sol! {
    tuple(bytes32,bytes32,uint64,bytes32,bytes32,bytes32,bytes32,(bytes32,uint64)[])
};

pub fn main() {
    // read the serialized state from stdin
    let serialized_state = read_vec();
    // compute the old state hash
    let old_state_hash = crypto::hash(&serialized_state);
    // deserialize the state thru bincode
    let mut state: State = bincode::deserialize(&serialized_state).unwrap();

    // read the execution payload from stdin
    // INPUT FORMAT:
    // - orders: Vec<u8> (bincode serialized Vec<Order>)
    // - blocks: Vec<u8> (bincode serialized Vec<RawBlock>)
    let execution = Execution {
        orders: bincode::deserialize(&read_vec()).unwrap(),
        blocks: bincode::deserialize(&read_vec()).unwrap(),
    };

    // get the latest zk proven Tron blockchain's block id and Untron's order chain (chained hash of all orders)
    let old_block_id = state.latest_block_id;
    let old_order_chain = state.order_chain;

    // perform execution over the state through the state transition function (see lib.rs for details)
    let closed_orders = stf(&mut state, execution);

    // compute the new state hash
    let new_state_hash = crypto::hash(&bincode::serialize(&state).unwrap());

    let public_values = UntronPublicValues::abi_encode(&(
        old_block_id,
        state.latest_block_id,
        state.latest_timestamp,
        old_order_chain,
        state.order_chain,
        old_state_hash,
        new_state_hash,
        closed_orders,
    ));

    // commit the public values as public inputs for the zk proof
    commit_slice(&public_values);
}
