#!/bin/sh
# jt12 vs Nuked YM3438 level/busy check (Verilator 5, ~15 s per run).
# iverilog is NOT usable here: jt12 outputs X there (uninitialised shift registers) and the
# gate-level Nuked model runs ~1000x slower.
set -e
cd "$(dirname "$0")"
J=$(grep -o 'src/jt12/[^"]*' ../../build.tcl | sed 's|^|../../|')
for L in 1 0; do
	verilator --binary --timing -j 0 -O3 -Wno-fatal -Wno-lint -Wno-style -DLADDER_VAL=$L \
		--top-module tb -Mdir obj$L tb_nuked_fm.v ../../src/peripherals/nuked_fm_md.v \
		../../src/nuked_fm/*.v $J > vl$L.log 2>&1
	./obj$L/Vtb
done
python3 level.py levels_ladder.txt levels_noladder.txt
