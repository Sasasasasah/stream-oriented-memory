# Memory Subsystem Interface Notes

The subsystem uses a stream-oriented boundary interface. A boundary state
provides segment valid/data inputs to a memory slice; successful writes consume
the selected input segment. Registered reads emit producer candidates containing
segment data plus stream direction and index metadata.

Commands are issued per logical bank. The current implementation supports
scheduled read, write, and WriteTap-related behavior represented by its command
encoding. Fault and collision signals are diagnostic outputs for invalid
commands, invalid write data, and competing producer candidates.

Concrete adaptation to a surrounding stream fabric, including physical boundary
coordinates and external producer arbitration, is intentionally outside this
standalone project.
