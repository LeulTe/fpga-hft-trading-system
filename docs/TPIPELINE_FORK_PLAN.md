# TPIPELINE Fork Plan

## Fork Thesis

TPIPELINE starts from `Ashutosh0x/fpga-hft-trading-system` but narrows the
project to a rigorous low-latency datapath. The fork should be judged by
correctness under stressful market-data ordering, backpressure behavior,
verification quality, timing closure, and measured hardware latency.

The interview-defensible statement is:

> I forked an open-source FPGA HFT demo, removed the speculative AI focus, and
> rebuilt the core market-data path around ready/valid flow control,
> hazard-aware order-book updates, randomized Cocotb verification, Quartus
> timing closure, and DE10-Standard hardware measurements.

## Upstream Module Map

| File | TPIPELINE action | Reason |
| --- | --- | --- |
| `rtl/fixed_point_pkg.sv` | Keep, then extend | Good shared type package. Add explicit TPIPELINE message/update structs and error flags. |
| `rtl/market_data_parser.sv` | Keep as baseline parser | Simple FSM parser is readable and useful for bring-up. Add downstream `ready` before serious testing. |
| `rtl/speculative_parser.sv` | Keep as optional fast parser | Useful once the baseline path works. Needs output backpressure and `tlast/tkeep` validation. |
| `rtl/order_book.sv` | Replace in stages | Current design has no explicit hazard scoreboard, forwarding, or collision-proof order lookup story. |
| `rtl/cuckoo_hash_table.sv` | Study, maybe reuse | Potentially useful, but a simpler M10K-friendly table may be better for Cyclone V timing. |
| `rtl/market_maker.sv` | Keep and simplify | Good deterministic strategy stage. Not the main contribution. |
| `rtl/risk_manager.sv` | Modify | Pipeline notional multiply and add ready/valid. |
| `rtl/order_generator.sv` | Keep and harden | Add input ready or small FIFO so orders are not dropped while TX is busy. |
| `rtl/trading_system_top.sv` | Replace with `tpipeline_top.sv` | Current top is a baseline integration, not the final fork architecture. |
| `rtl/smartnic_top.sv` | Remove from active build | Too broad and Alveo/AI-specific for the DE10-focused fork. |
| `rtl/neural_inference.sv` | Archive/reference only | Upstream model uses heuristic weights and does not prove trading value. |
| `rtl/sparse_neural_inference.sv` | Archive/reference only | Same issue; adds complexity without strengthening the core datapath. |
| `rtl/transformer_attention.sv` | Archive/reference only | Proof-of-concept, not useful for a low-latency Cyclone V datapath. |
| `rtl/fp8_compute_unit.sv` | Archive/reference only | AI support block, not active TPIPELINE work. |
| `rtl/feature_extractor.sv` | Archive/reference only | Only needed if the AI path returns. |
| `rtl/avellaneda_stoikov.sv` | Stretch/reference only | Interesting but calibration-heavy and distracts from hazards/timing. |
| `rtl/stat_arb.sv` | Archive/reference only | Multi-instrument strategy is out of scope. |
| `rtl/latency_arbiter.sv` | Archive/reference only | Cross-exchange flow is out of scope for DE10 bring-up. |
| `rtl/session_override.sv` | Archive/reference only | Depends on a broader SmartNIC story. |
| `rtl/inline_packet_filter.sv` | Stretch/reference only | Could become useful later, but not needed for the first board demo. |
| `tb/tb_trading_system.sv` | Keep as smoke test | Useful for baseline integration only. |
| `tb/tb_smartnic.sv` | Archive/reference only | Tests inactive AI/SmartNIC path. |
| `verify/nn_reference.py` | Replace | Create `model/golden_book.py` instead. |
| `scripts/synth.tcl` | Replace | Vivado/Alveo script must become Quartus/Cyclone V flow. |

## Milestone 0: Baseline Reproducibility

Goal: prove the inherited minimal datapath can be built and simulated.

Tasks:

- Pin the upstream commit in `docs/UPSTREAM_BASELINE.md`.
- Run the smallest parser -> book -> market maker -> risk -> TX simulation.
- Fix simulator portability issues before changing behavior.
- Remove CI patterns that allow failed simulations to pass.

Exit criteria:

- One documented simulator flow works.
- The active Makefile target does not include AI/SmartNIC modules.
- Known upstream limitations are written down.

## Milestone 1: TPIPELINE Top

Goal: create a small top-level that reflects the final project shape.

Tasks:

- Add `rtl/tpipeline_top.sv`.
- Wire parser, order book, strategy, risk, and TX only.
- Expose diagnostic counters for accepted messages, book updates, rejects,
  generated orders, and stalls.
- Keep the old upstream top available for comparison.

Exit criteria:

- `tpipeline_top` can run a deterministic smoke stream.
- The top-level has no AI, transformer, session override, or multi-strategy mux.

## Milestone 2: Ready/Valid Backpressure

Goal: make every pipeline boundary explicit and testable.

Tasks:

- Add `rtl/rv_skid_buffer.sv`.
- Add ready/valid ports to parser output, book input/output, strategy, risk, and TX.
- Add stall counters per stage.
- Ensure TX backpressure propagates upstream without dropping orders.

Exit criteria:

- Random stalls at each boundary produce the same book state as no-stall runs.
- No message is lost, duplicated, or reordered.

## Milestone 3: Hazard-Aware Order Book

Goal: correctly process adversarial back-to-back updates.

Tasks:

- Add `rtl/hazard_scoreboard.sv`.
- Track in-flight keys:
  - `symbol_id`
  - `order_id`
  - `order_id_hash`
  - `side`
  - `price`
- Add forwarding for in-flight quantity and level updates.
- Add interlocks when forwarding is impossible.
- Split storage into:
  - `rtl/order_id_table.sv`
  - `rtl/price_level_store.sv`
  - `rtl/book_update_pipeline.sv`
  - `rtl/top_of_book_cache.sv`

Hazard tests:

- ADD then DELETE same order in consecutive cycles.
- ADD then EXECUTE same order in consecutive cycles.
- EXECUTE partial then DELETE same order.
- Two ADDs to the same price level.
- DELETE causing best bid/ask to move.
- Hash collision between unrelated order IDs.

Exit criteria:

- Python golden model and RTL match after every emitted top-of-book update.
- Hazard stalls are counted and explained.

## Milestone 4: Cocotb and Golden Model

Goal: replace hand-written happy-path tests with randomized verification.

Tasks:

- Add `model/golden_book.py`.
- Add `tests/cocotb/test_parser.py`.
- Add `tests/cocotb/test_order_book_random.py`.
- Add `tests/cocotb/test_backpressure.py`.
- Add `tests/cocotb/test_hazards.py`.
- Generate reproducible seeds and save failing streams.

Exit criteria:

- Thousands of randomized updates pass.
- Regression includes both no-stall and randomized-stall modes.
- Failures produce a minimal replay file.

## Milestone 5: C++ Host Replay

Goal: create a host-side tool that feeds the same stream into simulation and
hardware.

Tasks:

- Add `host/replay.cpp`.
- Support CSV input with fields:
  - timestamp
  - message type
  - order ID
  - symbol
  - side
  - price
  - quantity
- Pack messages into the same 4 x 64-bit format used by the parser.
- Add modes for:
  - dump binary vectors
  - simulator replay
  - HPS/MMIO replay
  - latency benchmark replay

Exit criteria:

- One replay file drives Python, RTL simulation, and hardware harness.
- Replay output is deterministic and versioned.

## Milestone 6: Quartus Timing Closure

Goal: make the fork honest on Cyclone V.

Tasks:

- Add `quartus/tpipeline_de10.qsf`.
- Add `quartus/tpipeline_de10.sdc`.
- Start with 50 MHz, then push 100 MHz, 125 MHz, and higher only if timing allows.
- Replace wide one-cycle operations with pipelined versions.
- Map memories intentionally to M10K blocks where appropriate.

Exit criteria:

- Post-fit Fmax and resource utilization are documented.
- Worst paths are understood.
- Timing numbers are clearly separated from simulation cycle counts.

## Milestone 7: DE10-Standard Hardware Benchmark

Goal: measure the datapath on real hardware without pretending the DE10 is an
Alveo trading NIC.

Tasks:

- Use HPS, UART, or memory-mapped replay to inject packed messages.
- Add cycle counters at:
  - input accept
  - parsed message valid
  - book update commit
  - top-of-book valid
  - strategy order valid
  - risk approved
  - TX frame start
- Record min, max, average, and histogram.
- Display coarse status on LEDs/seven-segment if useful.

Exit criteria:

- Board run produces measured cycle latency.
- Results include stalls, rejects, and hazard counts.
- README reports measured numbers, not estimates.

## Final Portfolio Deliverables

- `README.md` with concise scope and measured results.
- `docs/ARCHITECTURE.md` with pipeline diagram and latency budget.
- `docs/VERIFICATION.md` with golden model strategy and coverage matrix.
- `docs/TIMING.md` with Quartus reports and worst-path notes.
- `docs/HARDWARE_RESULTS.md` with DE10 measurements.
- Clean active RTL path with inactive upstream AI modules clearly marked.
