// Exact-lock timing constraints (2026-09-22). Upstream's mdtang.sdc times clk_sys and the
// Z80 only; the 74.25 MHz pixel clock and 371.25 MHz TMDS clock are never checked. Here
// all of them are, so "0 violations" means something.
//
//   clk_sys 53.750 MHz (FVCO 806.25/15), clk_z80 = clk_sys/2, clk_pixel 26.875 (/30),
//   clk_5x 134.375 (/6) -- 2.8x lower than the 371.25 MHz the 720p build serialises at.
create_clock -name clk50 -period 20.00 -waveform {0 10.00} [get_nets {clk50}]
create_clock -name clk_sys -period 18.605 -waveform {0 9.302} [get_nets {clk_sys}]
create_generated_clock -name clk_z80 -source [get_nets {clk_sys}] -divide_by 2 [get_nets {clk_z80}]
create_clock -name clk_pixel -period 37.209 -waveform {0 18.605} [get_nets {hclk}]
create_clock -name clk_5x -period 7.442 -waveform {0 3.721} [get_nets {hclk5}]
set_clock_groups -asynchronous -group [get_clocks {clk_sys clk_z80}] -group [get_clocks {clk_pixel clk_5x}]

// Z80 to M68K, 2 clk_sys cycles (unchanged from mdtang.sdc)
set_multicycle_path 4 -end -setup -from [get_clocks {clk_z80}] -to [get_clocks {clk_sys}]
set_multicycle_path 3 -end -hold -from [get_clocks {clk_z80}] -to [get_clocks {clk_sys}]
