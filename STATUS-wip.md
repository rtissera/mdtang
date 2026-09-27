# Work in progress: exact-lock HDMI, quick wins, 68k bus timing

This branch is not merged and not released. It stacks three sets of changes on
top of `master`:

1. **Exact-lock HDMI** (`feat/exact-lock-hdmi`): 855x524 output locked to the
   core clock, one source line = two output lines, no frame drops or repeats.
2. **Quick wins** (`feat/quick-wins`): 4 MB ROMs load, cart quirks and region
   from the ROM header, 6-button pad, MiSTer audio defaults.
3. **68k bus timing** (`feat/68k-waits`): the bus state machine added one wait
   state to every 68k access, so the 68000 ran about 18% slow. Reads now start
   at once; work-RAM writes are posted.

## Tested on hardware (Console 60K, exact-lock build)

| Game | Before | After |
|---|---|---|
| Gunstar Heroes | no sound | sound (to be checked against a reference) |
| Mortal Kombat 3 | no sound | sound |
| Lightening Force | no sound | sound and music |
| Castlevania Bloodlines | locks going in-game | gets in-game, sound and music |
| Sonic 1 / 2 / 3, Sonic & Knuckles | boot | Sonic 2 re-checked, OK |
| Super Street Fighter II | boots (4 MB) | not re-checked |
| SF2 Special Champion Edition | 6-button OK | not re-checked |

Castlevania Bloodlines was silent, flickered and could lock up only in the exact-lock
builds. The cause was the Z80 clock: those builds divided the core clock with a CLKDIV.
Taking the PLL's /2 output instead, as the stock build does, fixed all three on hardware.

## Open

- Primer 25K builds and meets timing; not tested on hardware.
- Nano 20K: does not fit (about 10 BSRAM short).
- Exact-lock builds are NTSC only; PAL (576p50) is planned.
