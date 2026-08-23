# Contributing

TPIPELINE is currently a personal portfolio fork and active learning project.

## CLA

No Contributor License Agreement is required for this fork at this time.

If changes are ever submitted back to the original upstream repository, follow
that project's contribution process. A CLA would matter only if the upstream
maintainer requires one.

## Scope

Contributions should stay aligned with the TPIPELINE direction:

- minimal FPGA trading datapath
- ready/valid backpressure
- hazard-aware order-book updates
- Cocotb and Python golden-model verification
- C++ replay tooling
- Quartus / DE10-Standard timing and hardware measurement

Avoid expanding the active path back into the inherited AI/transformer/SmartNIC
demo unless that work is clearly isolated from the core datapath.

## License Note

The imported upstream commit does not include a standalone open-source license
file. Until that is resolved, treat this repository as a fork for study,
portfolio development, and contribution discussion rather than a cleanly
relicensed open-source codebase.
