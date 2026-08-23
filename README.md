# TPIPELINE

Default development branch: `tpipeline-main`.

TPIPELINE is a fork of `Ashutosh0x/fpga-hft-trading-system` focused on a
smaller, more defensible FPGA trading datapath:

```text
ITCH-like RX frame
    -> parser
    -> elastic/skid buffering
    -> hazard-aware order book
    -> simple market-making strategy
    -> pipelined risk gate
    -> order frame generator
```

The upstream project contains useful baseline RTL for parsing, book updates,
market making, risk checks, and order generation. This fork deliberately moves
away from the upstream AI/transformer/SmartNIC emphasis and toward the parts
that are strongest for an RTL/FPGA interview:

- deterministic ready/valid pipeline behavior
- explicit backpressure between stages
- order-book hazards for back-to-back updates
- forwarding and interlocks when two updates touch the same order or level
- Cocotb randomized tests against a Python golden book model
- C++ host replay for synthetic market-data streams
- Quartus timing closure for the DE10-Standard / Cyclone V
- on-board cycle measurements instead of pre-synthesis latency claims

## Active Scope

The active datapath starts from the simpler upstream path:

- `rtl/fixed_point_pkg.sv`
- `rtl/market_data_parser.sv` or `rtl/speculative_parser.sv`
- `rtl/order_book.sv`
- `rtl/market_maker.sv`
- `rtl/risk_manager.sv`
- `rtl/order_generator.sv`
- `rtl/trading_system_top.sv`

These files will be progressively refactored into TPIPELINE-specific modules:

- `rtl/rv_skid_buffer.sv`
- `rtl/hazard_scoreboard.sv`
- `rtl/order_id_table.sv`
- `rtl/price_level_store.sv`
- `rtl/book_update_pipeline.sv`
- `rtl/top_of_book_cache.sv`
- `rtl/tpipeline_top.sv`

## Intentionally Out of Scope

The upstream AI and multi-strategy modules are kept as inherited reference
material but are not part of the main TPIPELINE datapath:

- `rtl/neural_inference.sv`
- `rtl/sparse_neural_inference.sv`
- `rtl/fp8_compute_unit.sv`
- `rtl/transformer_attention.sv`
- `rtl/feature_extractor.sv`
- AI portions of `rtl/deterministic_wrapper.sv`
- `rtl/smartnic_top.sv`
- `rtl/avellaneda_stoikov.sv`
- `rtl/stat_arb.sv`
- `rtl/latency_arbiter.sv`
- `rtl/session_override.sv`
- `rtl/inline_packet_filter.sv`

The reason is practical: untrained AI blocks and broad strategy demos distract
from the harder systems problem this fork is meant to prove.

## Hardware Target

Primary board target:

- Terasic DE10-Standard
- Intel/Altera Cyclone V SoC `5CSXFC6D6F31C6N`
- FPGA fabric plus HPS-assisted replay/measurement

The DE10-Standard is not an Alveo-class trading NIC. TPIPELINE will report
measured FPGA fabric cycles and Quartus timing, not unsupported wire-to-wire HFT
claims.

## Verification Strategy

The verification plan is:

1. Keep a small SystemVerilog smoke test for parser/book/TX bring-up.
2. Add Cocotb tests for randomized market-data streams.
3. Compare every observable top-of-book update against a Python golden model.
4. Inject stalls on every ready/valid boundary.
5. Bias random tests toward hazards:
   - add/delete same `order_id`
   - execute immediately after add
   - repeated updates to one price level
   - hash collisions
   - full/empty book transitions
   - TX backpressure while strategy emits orders

## Current Status

Milestone 1 is in progress. The fork now has its own active top-level,
`rtl/tpipeline_top.sv`, for the minimal parser -> book -> strategy -> risk ->
TX path. It builds and runs with Icarus Verilog through:

```sh
make sim-basic
```

The active smoke test reports parsed-message, book-update, risk-approval, and
order-output counters. The next implementation milestone is ready/valid
backpressure between stages.

See `docs/TPIPELINE_FORK_PLAN.md` for the milestone-by-milestone plan.

## Attribution and License Status

This repository is a fork of
`https://github.com/Ashutosh0x/fpga-hft-trading-system`.

At the imported upstream commit, no standalone open-source license file was
present in the repository. That means this fork should not be treated as a
normally licensed open-source project yet. The upstream code remains attributed
to the original author, and TPIPELINE-specific changes are documented as fork
work by Leul Tewelde.

See `NOTICE.md` for the current license and attribution notes.
