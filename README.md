# Stream-Oriented Memory Subsystem

A cycle-aware RTL and C++ reference model for a hierarchical stream-coupled
memory subsystem.

## Features

- Hierarchical leaf, bank, slice, group, hemisphere, and full-system design
- Stream-oriented read and write interface
- Deterministic scheduled access with registered read responses
- Write and WriteTap behavior
- Explicit consume and producer-candidate signals
- Cycle-aware C++ reference models
- RTL and CModel regression tests

## Architecture

```text
mem_full
|-- hemisphere[0]
|   `-- groups
|       `-- slices
|           `-- logical banks
|               `-- storage leaves
`-- hemisphere[1]
```

## Cycle Semantics

The implementation models deterministic scheduled accesses. Reads produce a
registered response, writes update their addressed row at the active edge, and
same-address read-after-write behavior is explicitly tested. The model has no
dynamic retry or backpressure mechanism; invalid schedules are reported through
the local fault behavior exposed by the implementation.

## Project Structure

```text
rtl/       Synthesizable Verilog RTL
cmodel/    Cycle-aware C++ reference models
tb/        RTL testbenches
scripts/   Windows batch regression entry points
docs/      Architecture and interface notes
```

## Quick Start

From the repository root on Windows:

```bat
scripts\run_mem_full_regression.bat
```

## Verification

The repository includes verification at leaf, logical-bank, slice, group,
hemisphere, and full-system levels, together with C++ model tests where
applicable.

Expected final result:

```text
MEM_FULL_REGRESSION TEST_PASS
```

This is a personal educational RTL/CModel architecture project. Verify that
you have the appropriate rights before publishing any derivative work.
