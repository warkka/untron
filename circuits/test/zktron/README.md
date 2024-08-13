# Testing ground for circuits

**Warning:** to make reproducible builds, go to the respecitve crates instead. This script is for testing the circuits

As a first step, we will be testing the circuit with scripts. At some point, we will move to a more formal testing framework.

## Context

For the tests, we will be using actual tron blocks from block XXXXXXX to YYYYYYY. The srs.json file will contain the SRs (Super Representatives) for those blocks (which correspond to maintainance window XXX or epochs XXXX to YYYY)
A portion of the blocks will be obtained for every run from the tron network to test the circuit.

## Running

`RUST_LOG=info cargo run --release`
