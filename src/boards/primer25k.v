// Board configuration for Sipeed Tang Primer 25K (GW5A-25A).
//
// Added 2026-09-22, and only possible with the exact-lock video path: the stock build
// needs 82 BSRAM blocks and this device has 56.
//
// USB1/USB2 are deliberately NOT defined. The board has no USB host pins broken out, and
// dropping both hosts also returns their ROM blocks and logic -- which is what brings the
// design inside the BSRAM budget. Gamepads come from the two DualShock ports instead.
// The SD and SPI-flash pins are declared but unused by this core, so they are not brought
// out either; that frees 12 of the package's 68 regular I/O.
`define PRIMER25K

// NOT enabled: `define ZRAM_SDRAM moves the Z80's 8 KB out of block RAM and into SDRAM.
// It works (the ZBUS state machine already serialises the 68000 and the Z80 and both
// already wait for an acknowledge), and it does remove that RAM -- but MEASURED
// 2026-09-23 it made the total WORSE, 57 -> 58 blocks: something else grew by five and
// the cause is not identified. The code stays for whoever chases it.
