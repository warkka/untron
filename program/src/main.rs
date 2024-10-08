#![no_main]
sp1_zkvm::entrypoint!(main);

use alloy_sol_types::{sol, SolType};
use sp1_zkvm::io::{commit_slice, read_vec};

use untron_program::{crypto, stf, Execution, State};

// UntronPublicValues are the public input (output) of the Untron program.
// Must be encoded as defined in the smart contracts.
// Format:
// - old_block_id: [u8; 32] (block id of the previous latest zk proven block in the Tron blockchain)
// - old_action_chain: [u8; 32] (chained hash of all performed actions in the Untron contract before applying the execution)
// - old_state_hash: [u8; 32] (hash of the previous state of the Untron program)

// - new_block_id: [u8; 32] (block id of the latest zk proven block in the Tron blockchain after applying the execution)
// - new_action_chain: [u8; 32] (chained hash of all performed actions in the Untron contract after applying the execution)
// - new_state_hash: [u8; 32] (hash of the new state of the Untron program after applying the execution)

// - closed_orders: Vec<(bytes32, uint64)> (list of all orders that must be closed in the Untron contract after applying the execution)
type UntronPublicValues = sol! {
    tuple(bytes32,bytes32,bytes32,bytes32,bytes32,bytes32,(bytes32,uint64)[])
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
    // - actions: Vec<u8> (bincode serialized Vec<Order>)
    // - blocks: Vec<u8> (bincode serialized Vec<RawBlock>)
    let execution = Execution {
        actions: bincode::deserialize(&read_vec()).unwrap(),
        blocks: bincode::deserialize(&read_vec()).unwrap(),
    };

    // get the latest zk proven Tron blockchain's block id and Untron's action chain (chained hash of all actions)
    let old_block_id = state.latest_block_id;
    let old_action_chain = state.action_chain;

    // perform execution over the state through the state transition function (see lib.rs for details)
    // and format closed_orders as (order_id, amount)
    let closed_orders: Vec<([u8; 32], u64)> = stf(&mut state, execution)
        .into_iter()
        .map(|(order_id, order_state)| (order_id, order_state.inflow))
        .collect();

    // compute the new state hash
    let new_state_hash = crypto::hash(&bincode::serialize(&state).unwrap());

    let public_values = UntronPublicValues::abi_encode(&(
        old_block_id,
        state.latest_block_id,
        old_action_chain,
        state.action_chain,
        old_state_hash,
        new_state_hash,
        closed_orders,
    ));

    // commit the public values as public inputs for the zk proof
    commit_slice(&public_values);
}
