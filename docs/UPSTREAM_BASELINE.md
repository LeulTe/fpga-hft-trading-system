# Upstream Baseline

## Source

- Upstream repository: `https://github.com/Ashutosh0x/fpga-hft-trading-system`
- Imported commit: `3124a47`
- Local fork branch: `tpipeline-main`
- Local upstream remote: `upstream`

Pushes to the upstream remote are disabled in this local checkout. Add a new
`origin` remote later if this fork is published to a personal GitHub repository.

## Initial Bring-Up Notes

The fork begins from the upstream minimal datapath:

```text
market_data_parser
    -> order_book
    -> market_maker
    -> risk_manager
    -> order_generator
```

The upstream SmartNIC/AI path is intentionally inactive for TPIPELINE.

## Baseline Bring-Up Result

The first local `make sim-basic` attempt with Icarus Verilog did not complete.
The failure occurred during elaboration around `rtl/order_book.sv`, where Icarus
reported struct-array casting/indexing issues and then aborted.

This has been resolved for the active baseline path by:

1. Splitting the order lookup table from an indexed packed-struct array into
   parallel arrays.
2. Removing block-scoped initialized declarations that trigger simulator
   lifetime warnings.
3. Unpacking `risk_manager` input fields before the combinational risk checks.
4. Adjusting the latency smoke-test stimulus so it actually moves the strategy
   quote.

Current active baseline command:

```sh
make sim-basic
```

Expected result: the parser -> order book -> market maker -> risk -> order
generator smoke test builds and runs to completion with Icarus Verilog.
