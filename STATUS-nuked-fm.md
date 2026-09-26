# Experimental: Nuked YM3438 FM

Pushed for reference, not merged, **not tested on hardware**.

- Replaces jt12 with nukeykt's gate-level YM3438 as a build option.
- Build targets: `console60k_nukedfm`, `console60k_exact_nukedfm` (Console 60K). Simulated with Verilator; see `sim/nuked_fm/`.
- Branched from `feat/quick-wins`, so it does not have the 68k bus fix
  from `feat/68k-waits`.
- The files under `src/nuked_fm/` come from nukeykt's Nuked-MD-FPGA,
  via drizzt/openfpga-MegaDrive, unmodified except one marked line in
  `ym3438_io.v` (status timer, for the halved clock). The headed files are GPL v2 or later; the
  sub-modules carry no header of their own, only the GPL v2 `LICENSE` next
  to them.
