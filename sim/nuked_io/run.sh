#!/bin/bash
# gen_io vs Nuked YM6046 (gen_io_nuked) pad-port reads, Verilator.
set -e
cd "$(dirname "$0")"
S=../../src
verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-PINMISSING -Wno-PINCONNECTEMPTY \
  -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-BLKANDNBLK -Wno-INITIALDLY -Wno-LATCH \
  --top-module tb_nuked_io tb_nuked_io.sv \
  $S/peripherals/gen_io.sv $S/peripherals/nuked_io_md.sv $S/nuked_io/ym6046.v $S/nuked_io/ym_lib.v \
  tb_nuked_io.cpp -o tb >/dev/null
./obj_dir/tb

# optional: YM6046 at 1x MCLK (as integrated) vs 2x (upstream), ~20 s
if [ "$1" = "2x" ]; then
  verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-PINMISSING -Wno-PINCONNECTEMPTY \
    -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-INITIALDLY -Wno-BLKANDNBLK --top-module tb_clk2x tb_clk2x.sv \
    $S/nuked_io/ym6046.v $S/nuked_io/ym_lib.v -o tb2x --Mdir obj_dir/c2x >/dev/null
  ./obj_dir/c2x/tb2x | grep -v "pin diff"
fi
