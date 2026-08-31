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

The default configuration uses 52 slices and 416 producer candidates per
hemisphere. These values describe the current prototype configuration rather
than a required industry-standard topology.

## Documentation

- [Architecture](docs/architecture.md)
- [Interface Notes](docs/interface.md)

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

This repository is a cycle-aware RTL/C++ prototype for architectural modeling
and verification; it is not a production memory IP implementation. Verify that
you have the appropriate rights before publishing any derivative work.
