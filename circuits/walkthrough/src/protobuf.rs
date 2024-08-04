use hex_literal::hex;
use zktron::read_varint;

pub struct UsdtTransfer {
    pub to: [u8; 20],
    pub value: u64,
}

// assert_eq but None instead of panic
fn wagmi<T: core::cmp::PartialEq>(left: T, right: T) -> Option<()> {
    if left == right {
        Some(())
    } else {
        None
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
