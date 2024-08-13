use sp1_core::runtime::SyscallCode;
use sp1_sdk::{ProverClient, SP1Stdin, SP1ProvingKey, SP1VerifyingKey};
use serde::Deserialize;
use sha2::{Sha256, Digest};
use k256::ecdsa::{RecoveryId, Signature, VerifyingKey};
use tonic::transport::Channel;
use tonic::Request;
use block_header::Raw;

struct Block {
    block_number: u32,
    witness_signature: Vec<u8>,
    raw_data: Vec<u8>,
}

pub struct SP1Data {
    client: ProverClient,
    stdin: SP1Stdin,
    pk: SP1ProvingKey,
    vk: SP1VerifyingKey,
}

pub struct InputTestData {
    blocks: Vec<Block>,
    srs_list: Vec<Vec<u8>>,
}

pub fn prove_and_verify(sp1_data: SP1Data): Result<(SP1PublicValues), Box<dyn std::error::Error>> {
    let (client, stdin, pk, vk) = sp1_data;

    // Generate the proof.
    let (public_values, execution_report) = client
        .execute(&pk, stdin)
        .expect("failed to generate proof");
    println!("Successfully executed proof!\n");

    println!("Public values: {:?}", public_values);
    println!("Execution report: {:?}\n", execution_report);

    let tic = execution_report.total_instruction_count();
    println!("Total instruction count: {}\n", tic);

    // Verify the proof
    let verified = client
        .verify(&proof, &vk)
        .expect("failed to verify proof");

    println!("Successfully verified proof!\n");
    println!("Verified: {:?}", verified);

    Ok(public_values)
}

pub fn test_valid_case(input: InputTestData, sp1_data: SP1Data) {
    let InputTestData { blocks, srs_list } = input;
    let SP1Data { client, stdin, pk, vk } = sp1_data;

    let start_block = blocks[0].block_number;
    let block_count = blocks.len();

    stdin.write(&start_block.to_le_bytes()); // start_block
    stdin.write(&block_count.to_le_bytes()); // block_count

    stdin.write_vec(&srs_list); // srs_list

    for block in blocks {
        stdin.write_vec(&block.raw_data); // raw_data
        stdin.write_vec(&block.witness_signature); // signature
    }

    prove_and_verify(
        SP1Data {
            client,
            stdin,
            pk,
            vk
        }
    );
}

pub fn test_invalid_block_case(zkron_test: ZktronTest) {

}

pub fn test_unchained_blocks_case(zkron_test: ZktronTest) {

}

pub fn test_non_sr_signature_case(zkron_test: ZktronTest) {

}

pub fn test_sr_duplicated_signature_case(zkron_test: ZktronTest) {

}

pub fn test_not_enough_blocks_case(zkron_test: ZktronTest) {

}