use k256::ecdsa::{RecoveryId, Signature, VerifyingKey};
use sha2::{Digest, Sha256};

pub fn hash(data: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(data);

    let mut result = [0u8; 32];
    result.copy_from_slice(&hasher.finalize());
    result
}

pub struct BlockHeader {
    pub prev_block_id: [u8; 32],
    pub new_block_id: [u8; 32],
    pub tx_root: [u8; 32],
    pub timestamp: u64,
}

pub fn read_varint(arr: &[u8]) -> (usize, usize) {
    let mut result = 0;
    let mut offset = 0;
    loop {
        let i = arr[offset];
        result |= ((i & 0x7f) as usize) << (offset * 7);
        offset += 1;
        if i & 0x80 == 0 {
            break;
        }
    }

    (result, offset)
}

pub fn parse_block_header(prev_block_id: [u8; 32], raw_data: &[u8], hash: [u8; 32]) -> BlockHeader {
    // protobuf fuckery. in tron, everything is in protobuf
    let mut offset = 0;

    assert_eq!(raw_data[offset] & 7, 0); // VARINT
    assert_eq!(raw_data[offset] >> 3, 1);
    offset += 1;

    // we don't need timestamp so we skip it
    let (timestamp, o) = read_varint(&raw_data[offset..]);
    offset += o;

    assert_eq!(raw_data[offset] & 7, 2); // LEN
    assert_eq!(raw_data[offset] >> 3, 2);
    offset += 2; // txroot length is always 32 (1 byte)

    let tx_root = raw_data[offset..offset + 32].try_into().unwrap();
    offset += 32;

    assert_eq!(raw_data[offset] & 7, 2); // LEN
    assert_eq!(raw_data[offset] >> 3, 3);
    offset += 2; // prevblockhash length is always 32 (1 byte)

    assert_eq!(&raw_data[offset..offset + 32], &prev_block_id);
    offset += 32;

    assert_eq!(raw_data[offset] & 7, 0); // VARINT
    assert_eq!(raw_data[offset] >> 3, 7);
    offset += 1;

    let (block_number, _) = read_varint(&raw_data[offset..]);

    let mut new_block_id = hash;
    new_block_id[..8].copy_from_slice(&(block_number as u64).to_be_bytes());

    BlockHeader {
        prev_block_id,
        new_block_id,
        tx_root,
        timestamp: timestamp as u64,
    }
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
