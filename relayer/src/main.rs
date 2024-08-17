use prost::Message;
use sp1_sdk::{ProverClient, SP1Stdin};
use tonic::transport::Channel;
use tonic::Request;

tonic::include_proto!("protocol");

use block_header::Raw;
use wallet_client::WalletClient;

async fn get_block_by_number(
    client: &mut WalletClient<Channel>,
    block_number: u32,
) -> Result<(Vec<Vec<u8>>, Raw), Box<dyn std::error::Error>> {
    let request = Request::new(NumberMessage {
        num: block_number as i64,
    });

    let response = client.get_block_by_num2(request).await?;
    let block = response.into_inner();

    Ok((
        block
            .transactions
            .iter()
            .map(|tx| tx.transaction.as_ref().unwrap().encode_to_vec())
            .collect(),
        block.block_header.unwrap().raw_data.unwrap(),
    ))
}

#[tokio::main]
async fn main() {
    println!("Hello, world!");
}
