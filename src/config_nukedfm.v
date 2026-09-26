// Selects the Nuked YM3438 FM chip (src/nuked_fm/ + src/peripherals/nuked_fm_md.v) in
// place of jt12. Added FIRST by build.tcl, and only for the `console60k_exact_nukedfm` and
// `console60k_nukedfm` targets, so the macro is defined before system.sv is analysed.
`define NUKED_FM 1
