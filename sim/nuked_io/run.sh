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
