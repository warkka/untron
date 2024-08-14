use alloy_sol_types::sol_data::Bool;
use sp1_sdk::{ProverClient, SP1Stdin, SP1ProvingKey, SP1VerifyingKey, SP1PublicValues};

pub struct Block {
    pub block_number: u32,
    pub witness_signature: Vec<u8>,
    pub raw_data: Vec<u8>,
}

pub struct SP1Data {
    pub client: ProverClient,
    pub stdin: SP1Stdin,
    pub pk: SP1ProvingKey,
    pub vk: SP1VerifyingKey,
}

pub struct InputTestData {
    pub blocks: Vec<Block>,
    pub srs_list: Vec<Vec<u8>>,
}

// TODO: Use directly from zktron::lib
pub fn hash(data: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(data);

    let mut result = [0u8; 32];
    result.copy_from_slice(&hasher.finalize());
    result
}

pub fn execute(sp1_data: &SP1Data) {
    let proof = sp1_data.client.execute(&sp1_data.pk, sp1_data.stdin.clone()).expect("failed to generate proof");
    println!("Successfully executed proof!\n");

    println!("Public values: {:?}", proof.public_values);
}

pub fn prove_and_verify(sp1_data: &SP1Data) -> Result<SP1PublicValues, Box<dyn std::error::Error>> {
    // Generate the proof.
    let proof = sp1_data.client.prove_compressed(&sp1_data.pk, sp1_data.stdin.clone()).expect("failed to generate proof");
    println!("Successfully executed proof!\n");

    println!("Public values: {:?}", proof.public_values);

    // Verify the proof
    let verified = sp1_data.client
        .verify_compressed(&proof, &sp1_data.vk)
        .expect("failed to verify proof");

    println!("Successfully verified proof!\n");
    println!("Verified: {:?}", verified);

    Ok(proof.public_values)
}


pub fn test(input: InputTestData, sp1_data: &SP1Data, prove: Bool) {
    let InputTestData { blocks, srs_list } = input;

    // TODO: Use directly from zktron/lib
    let start_block_number = blocks[0].block_number;
    let raw_data_hash = hash(&blocks[0].raw_data); 
    let start_block = raw_data_hash[..4].copy_from_slice(&start_block_number.to_be_bytes());

    let block_count = blocks.len();

    sp1_data.stdin.write(&start_block.to_le_bytes()); // start_block
    sp1_data.stdin.write(&block_count.to_le_bytes()); // block_count

    for sr in srs_list {
        sp1_data.stdin.write_vec(sr); // srs_list
    }

    for block in blocks {
        let fakeVec = vec![0u8; 32];
        sp1_data.stdin.write_vec(fakeVec); // raw_data
        sp1_data.stdin.write_vec(block.witness_signature); // signature
    }

    if (prove) {
        prove_and_verify(sp1_data);
    } else {
        execute(sp1_data);
    }
}

pub fn test_invalid_block_case(input: InputTestData, sp1_data: SP1Data) {

}

pub fn test_unchained_blocks_case(input: InputTestData, sp1_data: SP1Data) {

}

pub fn test_non_sr_signature_case(input: InputTestData, sp1_data: SP1Data) {

}

pub fn test_sr_duplicated_signature_case(input: InputTestData, sp1_data: SP1Data) {

}

pub fn test_not_enough_blocks_case(input: InputTestData, sp1_data: SP1Data) {

}
*/