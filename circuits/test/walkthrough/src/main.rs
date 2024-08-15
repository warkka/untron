use rand::{Rng, SeedableRng};
use tonic::transport::Channel;
use tonic::Request;
use serde_json;
use rand::rngs::StdRng;
use prost::Message;
use rand::RngCore;

mod test;

tonic::include_proto!("protocol");

use wallet_client::WalletClient;

async fn get_block_by_number(
    client: &mut WalletClient<Channel>,
    block_number: u32,
) -> Result<(Vec<u8>, u64, Vec<u8>, Vec<Vec<u8>>), Box<dyn std::error::Error>> {
    let request = Request::new(NumberMessage {
        num: block_number as i64,
    });

    let response = client.get_block_by_num2(request).await?;
    let block = response.into_inner();

    Ok((
        block.block_header.clone().unwrap().witness_signature,
        block.block_header.clone().unwrap().raw_data.unwrap().timestamp.try_into().unwrap(),
        block.block_header.clone().unwrap().raw_data.as_ref().unwrap().encode_to_vec(),
        block.transactions.iter().map(|tx| tx.transaction.as_ref().unwrap().encode_to_vec()).collect()
    ))
}

fn sample_block_range(
    start_block: u32,
    end_block: u32,
    sample_size: u32,
    random_seed: u8,
) -> Option<(u32, u32)> {
    let total_blocks = end_block - start_block + 1;

    // Ensure there are enough blocks to sample
    if total_blocks < sample_size {
        return None;
    }

    // Seed the random number generator
    let mut rng = StdRng::seed_from_u64(random_seed as u64);

    // Determine the starting point within the range
    let max_start = total_blocks - sample_size;
    let random_start = rng.gen_range(0..=max_start);

    // Calculate the start and end of the sampled range
    let sampled_start_block = start_block + random_start;
    let sampled_end_block = sampled_start_block + sample_size - 1u32;

    Some((sampled_start_block, sampled_end_block))
}

fn parse_json_to_vec(json_data: &str) -> Result<Vec<Vec<u8>>, serde_json::Error> {
    // Deserialize the JSON string into a Vec<String>
    let string_vec: Vec<String> = serde_json::from_str(json_data)?;

    // Convert each hexadecimal string into a Vec<u8>
    let byte_vec: Vec<Vec<u8>> = string_vec.iter()
        .map(|hex_str| hex::decode(hex_str).expect("Invalid hex string"))
        .collect();

    Ok(byte_vec)
}

const ORDER_TTL: u64 = 100; // blocks
const BLOCK_TIME: u64 = 3000; // milliseconds

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Setup the logger.
    sp1_sdk::utils::setup_logger();

    let channel = Channel::from_shared("http://grpc.trongrid.io:50051")?
        .connect()
        .await?;
    let mut wallet_client = WalletClient::new(channel);

    // Sample 101 sequential blocks between block number 64301464 and 64308662 (epoch) deterministically
    let start_epoch_block = 64301464;
    let end_epoch_block = 64308662;
    let sample_size = 3;
    let random_seed = 0xbeu8;

    // Call the function and destructure the result to get the start and end blocks
    let Some((sampled_start, sampled_end)) = sample_block_range(start_epoch_block, end_epoch_block, sample_size, random_seed) else { todo!() };

    let start_block = sampled_start;
    let end_block = sampled_end;
    
    let mut blocks: Vec<test::Block> = Vec::new();
    // Fetch blocks from Tron network
    for block_number in start_block..end_block {
        let (witness_signature, timestamp, raw_data, transactions) = get_block_by_number(&mut wallet_client, block_number).await?;
        println!("Fetching block with number: {}", block_number);

        let block = test::Block {
            block_number,
            witness_signature,
            timestamp,
            raw_data,
            transactions
        };
        blocks.push(block);
    }

    let mut rng = rand::thread_rng();
    let mut address = [0u8; 20];
    rng.fill_bytes(&mut address);
    let old_orders = vec![test::Order {
        address,
        // Order expires at block 10 of revealing blocks.
        timestamp: blocks[0].timestamp - (ORDER_TTL * BLOCK_TIME) + (10 * BLOCK_TIME),
        inflow: Some(5u64),
        min_deposit: 1u64
    }];

    rng.fill_bytes(&mut address);
    let new_orders = vec![
        test::Order {
            address,
            // TODO: This should be expired, see if we need to send an extra block or not
            timestamp: blocks[0].timestamp,
            inflow: None,
            min_deposit: 1u64
        },
        test::Order {
            // TODO: Actually fill the other order with some other address
            address,
            timestamp: blocks[0].timestamp + (25 * BLOCK_TIME),
            inflow: None,
            min_deposit: 1u64
        }
    ];
    let fee_per_block = 1u64;

    // 1. Test with 101 blocks, where:
    //      - Old state consists of 1 order
    //      - There are 2 new orders
    //      - All blocks are valid
    //      - Order in old state expires
    //      - 1 out of the 2 orders is fulfilled in the 101 blocks
    //      - Assert that y = f(x,w) is the same as y = C(x,w)
    let previous_block = blocks[0].clone();
    let proving_blocks = blocks[1..].to_vec();
    let valid_test_data = test::InputTestData {
        previous_block: previous_block.clone(),
        blocks: proving_blocks.clone(),
        old_orders: old_orders.clone(),
        new_orders: new_orders.clone(),
        fee_per_block
    };
    test::test(valid_test_data, false, false); 
    
    //  2. Test with 100 blocks, where:
    //      - Since it is less than ORDER_TTL, then proving should fail
    //let invalid_test_data = test::InputTestData {
    //    blocks: blocks[..100].to_vec(),
    //    old_orders,
    //    new_orders,
    //    fee_per_block
    //};
    //test::test(invalid_test_data, &sp1_data, false);
    
    Ok(())
}