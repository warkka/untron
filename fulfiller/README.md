# Untron.finance — Fulfiller

This is a simple agent that fulfills orders on ZKsync. It scans the Tron blockchain for USDT transfers closing orders in Untron Core and sends the respective amount in USDT L2 to the order creator in advance. This way, the order creators don't need to wait for the relayer's ZK proof proving their transfer on Tron. Fulfillers are incentivized to run the service by getting a share of the fees paid by the order creators.

## Running

```bash
cargo run --bin fulfiller
```
