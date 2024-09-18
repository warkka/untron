# Untron Monorepo

This repo contains all code for [Untron](http://untron.finance) project.

![Untron Banner](/static/banner.png)

## What's Untron?

Untron is a decentralized exchange powered by zero-knowledge proofs of Tron blockchain. With Untron, everyone can seamlessly swap between USDT on Tron and other crypto in the Ethereum ecosystem. Inspired by [ZKP2P](https://zkp2p.xyz), it allows anyone to provide liquidity for the bridge at their preferred rate, which makes Untron the cheapest and most trustless way to interact with Tron ecosystem. It's an implementation of ["P2P ZK Light Client Bridge between Tron and Ethereum L2s" (Hook, 2024)](https://ethresear.ch/t/p2p-zk-light-client-bridge-between-tron-and-ethereum-l2s/19931).

## Repository Structure

- [`contracts`](/contracts): all smart contracts for Untron Core (core logic) and Untron V1 (rate-limited production wrapper). Written in Solidity and deployed on ZKsync Era L2 blockchain.
- [`program`](/program): ZK program for Untron, implementing Tron consensus verification and transaction scanning. Written in Rust using [SP1](https://github.com/succinctlabs/sp1).
- [`relayer`](/relayer): relayer for Untron, written in Rust. It generates ZK proofs of the program using the prover network and broadcasts them to the Core.
- [`fulfiller`](/fulfiller): fulfiller for Untron, written in Rust. Acting quite similar to [relayers in Across](https://docs.across.to/concepts/intents-architecture-in-across), it scans the Tron blockchain for new swap deposits and sends the respective outputs to the swap initiator in advance, allowing for faster swaps before the ZK proof of the deposit is published to the smart contract.

## Architecture & Integrations

If you're interested in integrating Untron into your own project or just want to learn more about how Untron works, please refer to [our documentation](https://docs.untron.finance). The source code for the documentation is available [here](https://github.com/ultrasoundlabs/untron-docs).

We're also looking forward to establishing partnerships with projects and individuals. If you're interested, please get in touch with us at contact@untron.finance, or reach out to the founders of Ultrasound Labs: [Alex Hook](https://github.com/alexhooketh), [Ziemen](https://github.com/ziemen4).

## Acknowledgements

We would like to acknowledge the projects below whose previous work has been instrumental in making this project a reality:

- [ZKP2P](https://zkp2p.xyz): its ramping process involves two entities - liquidity providers (depositors) and swap initiators. The same logic was used in Untron to minimize gas usage on the Tron side.
- [Across](https://across.to): Across is used for cross-chain swap logic, making Untron truly chainless and compatible with the entire Ethereum ecosystem. Besides this, "fulfillers" in Untron were inspired by relayers in intent-based bridges, whom Across pioneered.
- [ZKsync](https://www.zksync.io): Untron is deployed on ZKsync Era L2, significantly reducing the costs for running the bridge and making it fully compatible with the Elastic Chain.
- [SP1](https://github.com/succinctlabs/sp1): Untron's ZK proofs are powered by SP1 zkVM.

## License

This project is licensed under the BUSL-1.1 license by Ultrasound Labs LLC. For details, please refer to [LICENSE](/LICENSE).
