# Experimental: Nuked YM6046 I/O

Pushed for reference, not merged, **not tested on hardware**.

- Replaces gen_io with nukeykt's YM6046 pad/I/O chip as a build option, groundwork for multitap and light gun.
- Build targets: the `*_nukedio` targets (Console 60K). Simulated with Verilator; see `sim/nuked_io/`.
- Branched from `feat/quick-wins`, so it does not have the 68k bus fix
  from `feat/68k-waits`.
- The files under `src/nuked_io/` come unmodified from nukeykt's Nuked-MD-FPGA,
  via drizzt/openfpga-MegaDrive. The headed files are GPL v2 or later; the
  sub-modules carry no header of their own, only the GPL v2 `LICENSE` next
  to them.
