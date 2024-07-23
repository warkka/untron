#![no_main]
sp1_zkvm::entrypoint!(main);

use sha2::{Digest, Sha256};

fn hash(data: &[u8]) -> Vec<u8> {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hasher.finalize().to_vec()
}

fn combine_hashes(left: &[u8], right: &[u8]) -> Vec<u8> {
    let mut combined = Vec::new();
    combined.extend_from_slice(left);
    combined.extend_from_slice(right);
    hash(&combined)
}

fn create_merkle_tree(leaves: &[Vec<u8>]) -> Vec<u8> {
    if leaves.is_empty() {
        return Vec::new();
    }

    let mut current_level = leaves.to_vec();

    while current_level.len() > 1 {
        let mut next_level = Vec::new();

        for chunk in current_level.chunks(2) {
            if chunk.len() == 2 {
                next_level.push(combine_hashes(&chunk[0], &chunk[1]));
            } else {
                next_level.push(chunk[0].clone());
            }
        }

        current_level = next_level;
    }

    current_level[0].clone()
}

pub fn main() {
    let tx_count = sp1_zkvm::io::read::<u32>();

    let mut tx_hashes = Vec::new();
    for _ in 0..tx_count {
        tx_hashes.push(sp1_zkvm::io::read_vec());
    }

    let tx_root = create_merkle_tree(&tx_hashes);
    sp1_zkvm::io::commit_slice(&tx_root);
}
