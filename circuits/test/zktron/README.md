# Testing ground for circuits

**Warning:** to make reproducible builds, go to the respecitve crates instead. This script is for testing the circuits

As a first step, we will be testing the circuit with scripts. At some point, we will move to a more formal testing framework.

## Context

For the tests, we will be using actual tron blocks from block 64301464 to 64308662 (2024-08-13 09:00:00 - 2024-08-13 15:00:00). The srs.json file will contain the SRs (Super Representatives) for those blocks (which correspond to that epoch)
A portion of the blocks will be obtained for every run from the tron network to test the circuit.

## Running

`RUST_LOG=info cargo run --release`
