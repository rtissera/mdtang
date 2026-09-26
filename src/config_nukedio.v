// Selects the Nuked YM6046 I/O controller (src/nuked_io/ + src/peripherals/nuked_io_md.sv)
// in place of gen_io. Added FIRST by build.tcl, and only for the *_nukedio targets, so the
// macro is defined before multitap.sv is analysed.
`define NUKED_IO 1
