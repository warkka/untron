use k256::ecdsa::{RecoveryId, Signature, VerifyingKey};
use sha2::{Digest, Sha256};
use sha3::Keccak256;

pub fn hash(data: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(data);

    let mut result = [0u8; 32];
    result.copy_from_slice(&hasher.finalize());
    result
}

pub fn recover_public_key(sig: &[u8], msg_hash: [u8; 32]) -> Vec<u8> {
    let mut recid = sig[64];
    let mut sig = Signature::from_slice(&sig[..64]).unwrap();

    if let Some(sig_normalized) = sig.normalize_s() {
        sig = sig_normalized;
        recid ^= 1;
    };
    let recid = RecoveryId::from_byte(recid).unwrap();

    let recovered_key = VerifyingKey::recover_from_prehash(&msg_hash[..], &sig, recid).unwrap();
    let bytes_recovered_key = recovered_key.to_encoded_point(false).as_bytes().to_vec();
    bytes_recovered_key[1..].to_vec()
}

fn combine_hashes(left: &[u8], right: &[u8]) -> [u8; 32] {
    let mut combined = Vec::with_capacity(64);
    combined.extend_from_slice(left);
    combined.extend_from_slice(right);
    hash(&combined)
}

pub fn create_merkle_tree(leaves: &[[u8; 32]]) -> [u8; 32] {
    if leaves.is_empty() {
        return [0u8; 32];
    }

    let mut current_level = leaves.to_vec();

    while current_level.len() > 1 {
        let mut next_level = Vec::new();

        for chunk in current_level.chunks(2) {
            if chunk.len() == 2 {
                next_level.push(combine_hashes(&chunk[0], &chunk[1]));
            } else {
                next_level.push(chunk[0]);
            }
        }

        current_level = next_level;
    }

    current_level[0]
}

pub fn public_key_to_address(public_key: &[u8]) -> [u8; 20] {
    let mut hasher = Keccak256::new();
    hasher.update(public_key);

    let mut address = [0u8; 20];
    address.copy_from_slice(&hasher.finalize()[12..]);
    address
}
