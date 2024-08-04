#![no_main]
sp1_zkvm::entrypoint!(main);

use std::collections::HashSet;

use alloy_sol_types::{sol, SolType};
use sp1_zkvm::io::*;
use zktron::*;

type LightClientOutput = sol! {
    tuple(bytes32,bytes32,uint32,bytes32,bytes32)
};

pub fn main() {
    let start_block = read::<[u8; 32]>(); // blockid
    let mut end_block = start_block;

    let mut srs = HashSet::new();
    let mut sr_print = Vec::with_capacity(64 * 27);
    for _ in 0..27 {
        let sr = read_vec();
        sr_print.extend_from_slice(&sr);
        srs.insert(sr);
    }
    let sr_print = hash(&sr_print);

    let block_count = read::<u32>();
    let mut block_ids = Vec::with_capacity((32 * block_count) as usize);
    let mut cycle = Vec::with_capacity(18);

    for _ in 0..block_count {
        let raw_data = read_vec();
        let signature = read_vec();

        let raw_data_hash = hash(&raw_data);
        let public_key = recover_public_key(&signature, raw_data_hash);
        assert!(srs.contains(&public_key));

        if cycle.len() == 18 {
            cycle.remove(0);
        }
        assert!(!cycle.contains(&public_key));
        cycle.push(public_key);

        let block_header = parse_block_header(end_block, &raw_data, raw_data_hash);

        assert_eq!(block_header.prev_block_id, end_block);
        end_block = block_header.new_block_id;

        block_ids.extend_from_slice(&block_header.new_block_id);
    }

    let blockprint = hash(&block_ids);
    let output =
        LightClientOutput::abi_encode(&(start_block, end_block, block_count, sr_print, blockprint));

    commit_slice(&output);
}
