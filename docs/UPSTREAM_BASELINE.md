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

## Known Baseline Issue

The first local `make sim-basic` attempt with Icarus Verilog did not complete.
The failure occurs during elaboration around `rtl/order_book.sv`, where Icarus
reports struct-array casting/indexing issues and then aborts. This should be
treated as Milestone 0 work, not as a TPIPELINE behavior change.

Recommended next steps:

1. Try the same minimal datapath with Verilator or another SystemVerilog
   simulator.
2. If Icarus support matters, simplify the `order_entry_t order_table` array
   access pattern or split packed struct fields into parallel arrays.
3. Only begin hazard/backpressure changes after one simulator path is stable.
