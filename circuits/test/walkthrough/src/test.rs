use alloy_sol_types::sol_data::Bool;
use sp1_sdk::{ProverClient, SP1Stdin, SP1ProvingKey, SP1VerifyingKey, SP1PublicValues};

pub struct Order {
    pub address: [u8; 20],
    pub timestamp: u32,
    pub inflow: Option<u64>,
    pub min_deposit: u64
}

pub struct Block {
    pub block_number: u32,
    pub witness_signature: Vec<u8>,
    pub raw_data: Vec<u8>,
    pub transactions: Vec<Vec<u8>>
}

pub struct SP1Data {
    pub client: ProverClient,
    pub stdin: SP1Stdin,
    pub pk: SP1ProvingKey,
    pub vk: SP1VerifyingKey
}

pub struct InputTestData {
    pub blocks: Vec<Block>,
    pub old_orders: Vec<Order>,
    pub new_orders: Vec<Order>,
    pub fee_per_block: u64
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
    // Execute the proof.
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
    let InputTestData { blocks, old_orders, new_orders, fee_per_block } = input;

    // TODO: Use directly from zktron/lib
    let start_block_number = blocks[0].block_number;
    let mut raw_data_hash = hash(&blocks[0].raw_data); 
    let start_block = raw_data_hash[..4].copy_from_slice(&start_block_number.to_be_bytes());

    let block_count = blocks.len();

    let state_length = old_orders.len();
    sp1_data.stdin.write(&state_length.to_be_bytes());

    for order in old_orders {
        sp1_data.stdin.write(&order.address);
        sp1_data.stdin.write(&order.timestamp.to_be_bytes());
        sp1_data.stdin.write(&order.inflow.unwrap_or(0).to_be_bytes());
        sp1_data.stdin.write(&order.min_deposit.to_be_bytes());
    }

    sp1_data.stdin.write(&[0u8; 20]); // Empty address (relayer address)
    sp1_data.stdin.write(&[0u8; 32]); // TODO: Add start order chain hash from input data

    let order_length = new_orders.len();
    sp1_data.stdin.write(&order_length.to_be_bytes());

    for order in new_orders {
        sp1_data.stdin.write(&order.timestamp.to_be_bytes());
        sp1_data.stdin.write(&order.address);
        sp1_data.stdin.write(&order.min_deposit.to_be_bytes());
    }

    sp1_data.stdin.write(&start_block.to_be_bytes()); // start_block
    sp1_data.stdin.write(&block_count.to_be_bytes()); // block_count
    sp1_data.stdin.write(&fee_per_block.to_be_bytes()); // fee_per_block

    for block in blocks {
        sp1_data.stdin.write_vec(block.raw_data); // raw_data

        sp1_data.stdin.write(&block.transactions.len());
        for transaction in block.transactions {
            sp1_data.stdin.write_vec(transaction); // transactions
        }
    }
}