use k256::ecdsa::{RecoveryId, Signature, VerifyingKey};
use sha2::{Digest, Sha256};
use sha3::Keccak256;

// hash data using sha256 (Tron's main hash function)
// we return [u8; 32] instead of Vec<u8> because it's more efficient in our case
pub fn hash(data: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(data);

    let mut result = [0u8; 32];
    result.copy_from_slice(&hasher.finalize());
    result
}

// recover public key from a signature and a message hash
pub fn recover_public_key(sig: &[u8], msg_hash: [u8; 32]) -> Vec<u8> {
    // the signature must contain a recovery id at the end, so we need to separate it from the actual signature
    let mut recid = sig[64];
    let mut sig = Signature::from_slice(&sig[..64]).unwrap();

    // normalize the signature (no idea if it's actually necessary; stolen from SP1 docs)
    if let Some(sig_normalized) = sig.normalize_s() {
        sig = sig_normalized;
        recid ^= 1;
    };

    // make recovery id from the last byte of the signature
    let recid = RecoveryId::from_byte(recid).unwrap();

    // recover public key from the signature, message hash and recovery id
    let recovered_key = VerifyingKey::recover_from_prehash(&msg_hash[..], &sig, recid).unwrap();
    let bytes_recovered_key = recovered_key.to_encoded_point(false).as_bytes().to_vec();
    bytes_recovered_key[1..].to_vec()
}

// combine two hashes into one
fn combine_hashes(left: [u8; 32], right: [u8; 32]) -> [u8; 32] {
    let mut combined = [0u8; 64];
    combined[..32].copy_from_slice(&left);
    combined[32..].copy_from_slice(&right);
    hash(&combined)
}

// construct a merkle tree from a list of hashes and return the root hash
pub fn create_merkle_tree(leaves: &[[u8; 32]]) -> [u8; 32] {
    // it's like this in Tron source code
    if leaves.is_empty() {
        return [0u8; 32];
    }

    // it's a binary merkle tree, so we can just keep combining the hashes in pairs
    let mut current_level = leaves.to_vec();

    // keep combining the hashes in pairs until we get the root hash
    while current_level.len() > 1 {
        let mut next_level = Vec::new();

        for chunk in current_level.chunks(2) {
            if chunk.len() == 2 {
                next_level.push(combine_hashes(chunk[0], chunk[1]));
            } else {
                next_level.push(chunk[0]);
            }
        }

        current_level = next_level;
    }

    // the root hash is the only hash left in the current level
    current_level[0]
}

// convert a public key to a Tron address
// Tron addresses are equivalent to Ethereum addresses
// (actually they include 0x41 prefix at the start, but we don't use it for efficiency)
pub fn public_key_to_address(public_key: &[u8]) -> [u8; 20] {
    let mut hasher = Keccak256::new();
    hasher.update(public_key);

    let mut address = [0u8; 20];
    address.copy_from_slice(&hasher.finalize()[12..]);
    address
}
