# TG68K verification

Run the standalone TG68K regressions with `make`.

The testbench uses a zero-wait-state, big-endian 16-bit memory and runs the
same integer program in the TG68K 68000, 68010, and 68020 modes. It checks the
program's memory result and records every externally visible bus transfer in
`build/bus_trace_*.log`.

The trace state field uses the kernel interface encoding:

- `0`: instruction fetch
- `2`: data read
- `3`: data write

Generated test artifacts are confined to the ignored `build` directory.

The MMU state test checks MC68030 control-register reset, readback, reserved
fields, TC and root-pointer configuration errors, and PMOVE ATC-flush side
effects independently of the CPU kernel.

The descriptor test covers root, short, and long formats, including invalid,
table, page, early-termination, and indirect descriptors and every protection
and history field used by the MC68030.

The table-walker test uses a 16-bit physical-memory model and checks exact
descriptor read and history-write sequences for short, long, mixed-format,
indirect, and early-termination searches. It also covers root direct mapping,
limits, supervisor and write protection, CPU-space bypass, and read/update bus
fault classification.
