// Selects the exact-lock video path (src/framebuffer_exact.sv + src/plla/pll_exact.v).
// Added FIRST by build.tcl for the `console60k_exact` target, so the macro is defined
// before mdtang_top.sv is analysed. The stock `console60k` target never adds this file.
`define EXACT_LOCK 1
