// This is a script to test the circuit against real Tron data
// and calculate the proving complexity

use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sp1_sdk::{HashableKey, ProverClient, SP1PlonkBn254Proof, SP1Stdin, SP1VerifyingKey};
use tonic::transport::Channel;
use tonic::Request;

tonic::include_proto!("protocol");

use wallet_client::WalletClient;

/// The ELF (executable and linkable format) file for the Succinct RISC-V zkVM.
///
/// This file is generated by running `cargo prove build` inside the `program` directory.
pub const PROGRAM_ELF: &[u8] = include_bytes!("../../../program/elf/riscv32im-succinct-zkvm-elf");

#[tokio::main]
async fn main() {
    // Setup the logger.
    sp1_sdk::utils::setup_logger();

    // Setup the prover client.
    let client = ProverClient::new();

    // Setup the program.
    let (pk, vk) = client.setup(PROGRAM_ELF);

    // Setup the inputs.

    let mut rng = rand::thread_rng();

    let mut leaves = Vec::new();
    for _ in 0..args.n {
        let mut input = [0u8; 32];
        rng.fill_bytes(&mut input);
        leaves.push(input.to_vec());
    }
    leaves.sort();

    let root = create_merkle_tree(&leaves);

    let mut stdin = SP1Stdin::new();
    stdin.write(&args.n);
    leaves.into_iter().for_each(|l| stdin.write_vec(l));

    println!("n: {}", args.n);

    // Generate the proof.
    let proof = client.prove(&pk, stdin).expect("failed to generate proof");
    println!("Successfully generated proof!");
    println!("Output: {:?}", proof.public_values.as_slice());

    // Verify the proof.
    client.verify(&proof, &vk).expect("failed to verify proof");

    assert_eq!(proof.public_values.as_slice(), &root);
}
