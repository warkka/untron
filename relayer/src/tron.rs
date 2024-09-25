mod proto;

use proto::{wallet_client::WalletClient, BlockExtention, NumberMessage};
use std::error::Error;
use tonic::transport::Channel;
use tonic::Request;

pub struct TronClient {
    client: WalletClient<Channel>,
}

impl TronClient {
    pub async fn new(rpc_url: &str) -> Result<Self, Box<dyn Error>> {
        let client = WalletClient::connect(rpc_url.to_string()).await?;
        Ok(Self { client })
    }

    pub async fn get_block_by_number(
        &mut self,
        block_number: u32,
    ) -> Result<BlockExtention, Box<dyn Error>> {
        let request = Request::new(NumberMessage {
            num: block_number as i64,
        });
        let response = self.client.get_block_by_num2(request).await?;
        let block = response.into_inner();
        Ok(block)
    }

    // Additional methods for processing blocks and transactions
}
