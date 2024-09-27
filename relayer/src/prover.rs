use sp1_sdk::{HashableKey, ProverClient, SP1ProvingKey, SP1Stdin, SP1VerifyingKey};
use std::error::Error;
use std::sync::Arc;

use crate::zksync::ZkSyncClient;

pub struct Prover {
    prover: ProverClient,
    pk: SP1ProvingKey,
    vk: SP1VerifyingKey,
    elf: &'static [u8],
    zksync_client: Arc<ZkSyncClient>,
}

impl Prover {
    pub fn new(elf: &'static [u8], zksync_client: Arc<ZkSyncClient>) -> Self {
        let prover = ProverClient::new();
        let (pk, vk) = prover.setup(elf);

        Self {
            prover,
            pk,
            vk,
            elf,
            zksync_client,
        }
    }

    pub async fn generate_proof(
        &self,
        stdin: SP1Stdin,
    ) -> Result<(Vec<u8>, Vec<u8>), Box<dyn Error>> {
        let vkey = self.zksync_client.vkey().await;
        if vkey == [0; 32] {
            let (public_values, _) = self.prover.execute(self.elf, stdin.clone()).run()?;
            return Ok((vec![], public_values.to_vec()));
        }

        if vkey != self.vk.hash_bytes() {
            tracing::error!(
                "Contract's vkey does not match the one compiled into the program. Contact Untron team."
            );
            return Err("Vkey does not match".into());
        }

        // Generates the ZK proof
        let result = self.prover.prove(&self.pk, stdin).groth16().run()?;
        self.prover.verify(&result, &self.vk)?;
        Ok((result.bytes(), result.public_values.to_vec()))
    }
}
