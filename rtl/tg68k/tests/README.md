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

The MMU instruction-decoder test exhaustively classifies all 65,536 extension
words for legal and illegal effective-address fields. It checks the MC68030
PMOVE register set and sizes, FC source encodings, PLOAD, the three PFLUSH
forms, PTEST level and address-register rules, reserved fields, privilege
indication, and exclusion of other coprocessor IDs.

The MMU instruction-controller test checks big-endian PMOVE word sequencing
and commit/error behavior, PFLUSH qualifiers, PLOAD invalidate/walk/fill
ordering, exact PTEST MMUSR results and descriptor-address return, FC source
selection, and privilege versus F-line exception priority.

The descriptor test covers root, short, and long formats, including invalid,
table, page, early-termination, and indirect descriptors and every protection
and history field used by the MC68030.

The table-walker test uses a 16-bit physical-memory model and checks exact
descriptor read and history-write sequences for short, long, mixed-format,
indirect, and early-termination searches. It also covers root direct mapping,
limits, supervisor and write protection, CPU-space bypass, and read/update bus
fault classification. Instruction-search cases verify TC.E-independent walks,
PTEST level termination, descriptor-address return, and suppressed history
updates.

The ATC test covers all 22 fully associative entries, variable page-size tag
matching, function-code tags, physical page-index insertion, status fields,
write misses for clear M bits, reset retention, selective and full flushes,
invalid-entry preference, and deterministic history-bit replacement.
PTEST lookups are also checked for non-mutating write-status searches.

The transparent-translation test checks exact TT address and function-code
masking, read/write qualification, locked read-modify-write exclusion, overlap
and CI combination, and the higher-priority CPU-space bypass. The walker test
also checks SRE/FC2 root selection and an explicit function-code table level.
