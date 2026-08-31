# Memory Subsystem Architecture

The design uses a regular hierarchy to keep storage, control propagation, and
stream-facing behavior separated.

```text
mem_full
  -> hemisphere
    -> group
      -> slice
        -> logical bank
          -> bank control column
          -> bank superlane leaves
```

Storage state is held by the bank leaves. Higher layers organize independent
banks and slices, distribute scheduled commands, and flatten boundary signals
without replacing leaf-local memory behavior.

Each bank leaf operates on an eight-byte segment. Groups and hemispheres scale
this regular unit while preserving deterministic command timing.

The default prototype configuration uses 52 slices and 416 producer candidates
per hemisphere. These values are configuration choices for this model rather
than a required general-purpose memory topology.
