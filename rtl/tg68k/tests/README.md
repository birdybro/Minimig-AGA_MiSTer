# TG68K verification

Run the standalone TG68K regression with `make`.

The testbench uses a zero-wait-state, big-endian 16-bit memory and runs the
same integer program in the TG68K 68000, 68010, and 68020 modes. It checks the
program's memory result and records every externally visible bus transfer in
`build/bus_trace_*.log`.

The trace state field uses the kernel interface encoding:

- `0`: instruction fetch
- `2`: data read
- `3`: data write

Generated test artifacts are confined to the ignored `build` directory.
