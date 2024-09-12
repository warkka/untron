# Untron.finance — Fulfiller

This is a simple agent that fulfills orders and reverse orders on ZKsync and Tron. It consists of two parts:

1. **Order fulfiller**: A service that scans the Tron blockchain for USDT transfers closing orders in Untron Core and sends the respective amount in USDT L2 to the order creator in advance. This way, the order creators don't need to wait for the relayer's ZK proof proving their transfer on Tron. Fulfillers are incentivized to run the service by getting a share of the fees paid by the order creators.
2. **Autocreator**: A service that scans Untron Core for reverse swaps (liquidity provisions where the minimum deposit is equal to liquidity provided, used for swaps from L2 to Tron) and automatically performs orders for such providers. Autocreators are also incentivized by configuring the minimum fee (in USDT, not percents) they're willing to accept for performing the reverse swaps. Eventually, this mechanism will be replaced with a more predictable one, but for now, it works quite reliably.

## Running

```bash
cargo run --bin fulfiller
```
