#![no_main]
sp1_zkvm::entrypoint!(main);

use alloy_sol_types::{sol, SolType};
use sp1_zkvm::io::{commit_slice, read, read_vec};

use untron_circuit::{crypto, stf, Execution, State};

type UntronOutput = sol! {
    tuple(bytes32,bytes32,uint64,bytes32,bytes32,bytes32,bytes32,(address,uint64)[])
};

pub fn main() {
    let serialized_state = read_vec();
    let old_state_hash = crypto::hash(&serialized_state);
    let state: State = bincode::deserialize(&serialized_state).unwrap();

    let execution = Execution {
        me: sp1_zkvm::io::read(),
        orders: (0..read::<u32>())
            .map(|_| bincode::deserialize(&read_vec()).unwrap())
            .collect(),
        blocks: (0..read::<u32>())
            .map(|_| bincode::deserialize(&read_vec()).unwrap())
            .collect(),
    };

    let old_block_id = state.latest_block_id;
    let old_order_chain = state.order_chain;

    let (state, closed_orders) = stf(state, execution);

    let output = UntronOutput::abi_encode(&(
        old_block_id,
        state.latest_block_id,
        state.latest_timestamp,
        old_order_chain,
        state.order_chain,
        old_state_hash,
        crypto::hash(&bincode::serialize(&state).unwrap()),
        closed_orders,
    ));

    commit_slice(&output);
}
