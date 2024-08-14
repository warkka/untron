// This is a script to test the circuit against real Tron data
// and calculate the proving complexity

use rand::{Rng, SeedableRng};
use sp1_sdk::{ProverClient, SP1Stdin};
use serde::Deserialize;
use tonic::transport::Channel;
use tonic::Request;
use block_header::Raw;
use serde_json;
use rand::rngs::StdRng;
use prost::Message;

mod test;

tonic::include_proto!("protocol");

use wallet_client::WalletClient;

/// The ELF (executable and linkable format) file for the Succinct RISC-V zkVM.
///
/// This file is generated by running `cargo prove build` inside the `program` directory.
pub const PROGRAM_ELF: &[u8] =
    include_bytes!("../../../zktron/elf/riscv32im-succinct-zkvm-elf");

// TODO: Use directly from zktron::lib
pub fn hash(data: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(data);

    let mut result = [0u8; 32];
    result.copy_from_slice(&hasher.finalize());
    result
}

async fn get_block_by_number(
    client: &mut WalletClient<Channel>,
    block_number: u32,
) -> Result<(Vec<u8>, Vec<u8>), Box<dyn std::error::Error>> {
    let request = Request::new(NumberMessage {
        num: block_number as i64,
    });

    let response = client.get_block_by_num2(request).await?;
    let block = response.into_inner();

    Ok((
        block.block_header.clone().unwrap().witness_signature,
        block.block_header.clone().unwrap().raw_data.as_ref().unwrap().encode_to_vec(),
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

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Setup the logger.
    sp1_sdk::utils::setup_logger();

    // Setup the prover client.
    let client = ProverClient::new();
    let (pk, vk) = client.setup(PROGRAM_ELF);

    // Setup the inputs.
    let mut stdin = SP1Stdin::new();

    let channel = Channel::from_shared("http://grpc.trongrid.io:50051")?
        .connect()
        .await?;
    let mut wallet_client = WalletClient::new(channel);

    // Sample 18 sequential blocks between block number 64301464 and 64308662 (epoch) deterministically
    let start_epoch_block = 64301464;
    let end_epoch_block = 64308662;
    let sample_size = 18;
    let random_seed = 0xaeu8;

    // Call the function and destructure the result to get the start and end blocks
    let Some((sampled_start, sampled_end)) = sample_block_range(start_epoch_block, end_epoch_block, sample_size, random_seed) else { todo!() };

    let start_block = sampled_start;
    let end_block = sampled_end;
    
    let mut blocks: Vec<test::Block> = Vec::new();
    // Fetch blocks from Tron network
    for block_number in start_block..end_block {
        let (witness_signature, raw_data) = get_block_by_number(&mut wallet_client, block_number).await?;
        println!("Block number: {}", block_number);
        println!("Witness signature: {:?}", witness_signature);
        println!("Raw data: {:?}", raw_data);

        let block = test::Block {
            block_number,
            witness_signature,
            raw_data,
        };
        blocks.push(block);
    }

    let srs_list = parse_json_to_vec(include_str!("srs.json"))?;

    println!("SRS list: {:?}", srs_list);

    /*let sp1_data = test::SP1Data {
        client,
        stdin,
        pk,
        vk
    };
    let test_data = test::InputTestData {
        blocks,
        srs_list
    };

    let InputTestData { blocks, srs_list } = input;
    */

    // TODO: Use directly from zktron/lib
    let start_block_number = blocks[0].block_number;
    let raw_data_hash = hash(&blocks[0].raw_data); 
    let start_block = raw_data_hash[..4].copy_from_slice(&start_block_number.to_be_bytes());

    let block_count = blocks.len() as u32;

    stdin.write(&start_block); // start_block
    stdin.write(&block_count); // block_count

    for sr in srs_list {
        stdin.write_vec(sr); // srs_list
    }

    for block in blocks {
        // TODO: See why with this fakeVec write proving still works fine when it should fail
        let fakeVec = vec![0u8; 32];
        stdin.write_vec(fakeVec); // raw_data
        stdin.write_vec(block.witness_signature); // signature
    }

    // Generate the proof.
    let proof = client.prove_compressed(&pk, stdin).expect("failed to generate proof");
    println!("Successfully executed proof!\n");

    println!("Public values: {:?}", proof.public_values);

    // Verify the proof
    let verified = client
        .verify_compressed(&proof, &vk)
        .expect("failed to verify proof");

    println!("Successfully verified proof!\n");
    println!("Verified: {:?}", verified);

    // 1. Test with 18 blocks, where:
    //      - All blocks are valid
    //      - All blocks are chained
    //      - All blocks are signed by a valid SR
    //      - All blocks follow a 
    //      - Assert that y = f(x,w) is the same as y = C(x,w)
    //test::test_valid_case(test_data, &sp1_data); 

    // 2. Test with 18 blocks, where:
    //      - Everything from the first test is the same
    //      - But 1 block is invalid
    //      - Assert that proving fails
    
    // 3. Test with 18 blocks, where:
    //      - Everything from first test is the same
    //      - But a pair of blocks are not chained
    //      - Assert that proving fails

    // 4. Test with 18 blocks, where:
    //      - Everything from first test is the same
    //      - But 1 block is signed by some public key that is not a SR
    //      - Assert that proving fails

    // 5. Test with 18 blocks, where:
    //      - Everything from first test is the same
    //      - But 1 block is signed by a SR twice
    //      - Assert that proving fails

    // 6. Test with 17 blocks, where:
    //      - Assert that proving fails (not enough blocks)
    
    Ok(())
}