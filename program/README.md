# Untron.finance: ZK program

This directory contains Untron's ZK program written in SP1 zkVM. ZK program accepts Tron blockchain and order data from the smart contract and looks for valid deposits against the tx roots of these blocks.

## Making a reproducible build

`cargo prove build --docker --tag v1.0.1`

[Untron Relayer](../relayer) makes a reproducible build of this program on compilation. You might want to try it out too.

## Checksum

`TODO`
