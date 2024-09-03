use hex_literal::hex;

// RATIONALE:
// in this file, we do manual deserialization of txs into two types:
// VoteWitnessContract (4) and TriggerSmartContract (31) of USDT TRC20 transfer().
// we could've used "prost" library, but it'd consider all ~40 tx types,
// which from our approximation would waste a lot of resources (we haven't tried tho).
//
// untron circuit only needs witness vote txs (to determine who's the next SR)
// and TriggerSmartContract (EVM-ish) txs with USDT TRC20 transfer() calls.

pub struct BlockHeader {
    pub prev_block_id: [u8; 32],
    pub new_block_id: [u8; 32],
    pub tx_root: [u8; 32],
    pub timestamp: u64,
}

pub struct UsdtTransfer {
    pub to: [u8; 20],
    pub value: u64,
}

#[derive(Debug)]
pub struct Vote {
    pub witness_address: [u8; 20],
    pub votes_count: u64,
}

#[derive(Debug)]
pub struct VoteTx {
    pub voter: [u8; 20],
    pub votes: Vec<Vote>,
}

// assert_eq but None instead of panic
fn wagmi<T: core::cmp::PartialEq>(left: T, right: T) -> Option<()> {
    if left == right {
        Some(())
    } else {
        None
    }
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

pub fn parse_usdt_transfer(tx: &[u8]) -> Option<UsdtTransfer> {
    wagmi(tx[tx.len() - 1], 1)?; // ret.contractRet: SUCCESS (THIS THING IS CRITICAL!!!)

    wagmi(tx[0] & 7, 2)?; // LEN
    wagmi(tx[0] >> 3, 1)?; // 1:
    let (_, mut offset) = read_varint(tx);
    offset += 1;

    // skipping unnecessary protobuf elements
    loop {
        if offset >= tx.len() {
            return None;
        }
        let t = tx[offset];
        if t == 0x5a {
            // 11: LEN
            break;
        }
        offset += 1;
        if t & 7 == 5 {
            offset += 4;
        } else {
            let (length, v) = read_varint(&tx[offset..]);
            offset += v + (length * (t & 7 == 2) as usize);
        }
    }

    wagmi(tx[offset] & 7, 2)?; // LEN
    wagmi(tx[offset] >> 3, 11)?; // 11:
    offset += 1;
    let (_, v) = read_varint(&tx[offset..]);
    offset += v;

    wagmi(tx[offset] & 7, 0)?; // VARINT
    wagmi(tx[offset] >> 3, 1)?; // 1: (we enter the contract protobuf)
    offset += 1;
    let (call_type, v) = read_varint(&tx[offset..]);
    offset += v;

    wagmi(call_type, 31); // TriggerSmartContract

    wagmi(tx[offset] & 7, 2)?; // LEN
    wagmi(tx[offset] >> 3, 2)?; // 2:
    offset += 1;
    let (_, v) = read_varint(&tx[offset..]);
    offset += v;

    wagmi(tx[offset] & 7, 2)?; // LEN
    wagmi(tx[offset] >> 3, 1)?; // 1:
    offset += 1;
    let (_, v) = read_varint(&tx[offset..]);
    offset += v;

    wagmi(tx[offset] & 7, 2)?; // LEN
    wagmi(tx[offset] >> 3, 2)?; // 2:
    offset += 1;
    let (_, v) = read_varint(&tx[offset..]);
    offset += v;

    wagmi(tx[offset] & 7, 2)?; // LEN
    wagmi(tx[offset] >> 3, 1)?; // 1:
    offset += 1;
    let (_, v) = read_varint(&tx[offset..]);
    offset += v;

    wagmi(tx[offset] & 7, 2)?; // LEN
    wagmi(tx[offset] >> 3, 2)?; // 2:
    offset += 1;
    let (length, v) = read_varint(&tx[offset..]);
    offset += v;

    // USDT smart contract TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t
    wagmi(
        &tx[offset..offset + length],
        &hex!("41a614f803b6fd780986a42c78ec9c7f77e6ded13c"),
    )?;
    offset += length;

    wagmi(tx[offset] & 7, 2)?; // LEN
    wagmi(tx[offset] >> 3, 4)?; // 4:
    offset += 1;
    let (length, v) = read_varint(&tx[offset..]);
    offset += v;

    let data = &tx[offset..offset + length];
    wagmi(&data[..4], &hex!("a9059cbb"))?;

    let mut to = [0u8; 20];
    to.copy_from_slice(&data[16..36]);

    let mut value_bytes = [0u8; 8];
    value_bytes.copy_from_slice(&data[60..68]);
    let value = u64::from_le_bytes(value_bytes);

    Some(UsdtTransfer { to, value })
}

pub fn parse_vote_tx(tx: &[u8]) -> Option<VoteTx> {
    wagmi(tx[tx.len() - 1], 1)?; // ret.contractRet: SUCCESS (THIS THING IS CRITICAL!!!)

    wagmi(tx[0] & 7, 2)?; // LEN
    wagmi(tx[0] >> 3, 1)?; // 1:
    let (_, mut offset) = read_varint(tx);
    offset += 1;

    // skipping unnecessary protobuf elements
    loop {
        if offset >= tx.len() {
            return None;
        }
        let t = tx[offset];
        if t == 0x5a {
            // 11: LEN
            break;
        }
        offset += 1;
        if t & 7 == 5 {
            offset += 4;
        } else {
            let (length, v) = read_varint(&tx[offset..]);
            offset += v + (length * (t & 7 == 2) as usize);
        }
    }

    wagmi(tx[offset] & 7, 2)?; // LEN
    wagmi(tx[offset] >> 3, 11)?; // 11:
    offset += 1;
    let (_, v) = read_varint(&tx[offset..]);
    offset += v;

    wagmi(tx[offset] & 7, 0)?; // VARINT
    wagmi(tx[offset] >> 3, 1)?; // 1: (we enter the contract protobuf)
    offset += 1;
    let (call_type, v) = read_varint(&tx[offset..]);
    offset += v;

    wagmi(call_type, 4)?; // VoteWitnessContract
    wagmi(tx[offset] & 7, 2)?; // LEN
    wagmi(tx[offset] >> 3, 2)?; // 2:
    offset += 1;
    let (_, v) = read_varint(&tx[offset..]);
    offset += v;

    wagmi(tx[offset] & 7, 2)?; // LEN
    wagmi(tx[offset] >> 3, 1)?; // 1:
    offset += 1;
    let (length, v) = read_varint(&tx[offset..]);
    offset += v;
    // wagmi(
    //     &tx[offset..offset + length],
    //     b"type.googleapis.com/protocol.VoteWitnessContract",
    // )?;
    offset += length;

    wagmi(tx[offset] & 7, 2)?; // LEN
    wagmi(tx[offset] >> 3, 2)?; // 2:
    offset += 1;
    let (_, v) = read_varint(&tx[offset..]);
    offset += v;

    wagmi(tx[offset] & 7, 2)?; // LEN
    wagmi(tx[offset] >> 3, 1)?; // 1:
    offset += 1;
    let (length, v) = read_varint(&tx[offset..]);
    offset += v;

    let mut voter = [0u8; 20];
    voter.copy_from_slice(&tx[offset + 1..offset + length]); // strip 0x41
    offset += length;

    let mut votes = Vec::new();
    while offset < tx.len() && tx[offset] & 7 == 2 && tx[offset] >> 3 == 2 {
        offset += 1;
        let (_, v) = read_varint(&tx[offset..]);
        offset += v;
        wagmi(tx[offset] & 7, 2)?; // LEN
        wagmi(tx[offset] >> 3, 1)?; // 1:
        offset += 1;
        let (length, v) = read_varint(&tx[offset..]);
        offset += v;
        let mut witness_address = [0u8; 20];
        witness_address.copy_from_slice(&tx[offset + 1..offset + length]); // strip 0x41
        offset += length;
        wagmi(tx[offset] & 7, 0)?; // VARINT
        wagmi(tx[offset] >> 3, 2)?; // 2:
        offset += 1;
        let (votes_count, v) = read_varint(&tx[offset..]);
        offset += v;
        votes.push(Vote {
            witness_address,
            votes_count: votes_count as u64,
        });
    }

    Some(VoteTx { voter, votes })
}
