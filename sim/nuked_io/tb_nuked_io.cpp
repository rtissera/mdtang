// Pad-port read sequences on gen_io vs gen_io_nuked (YM6046). Prints every read from both
// and flags the ones that differ. MCLK = 53.693 MHz, 68k CE = MCLK/7.
#include "Vtb_nuked_io.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <string>

static Vtb_nuked_io *t;
static uint64_t cyc = 0;
static int ndiff = 0, nreads = 0;
static const double MCLK_HZ = 53693175.0;

static void tick() {
	t->ce = (cyc % 7) == 0;
	t->clk = 0; t->eval();
	t->clk = 1; t->eval();
	cyc++;
}
static void wait_mclk(uint64_t n) { while (n--) tick(); }
static void wait_us(double us) { wait_mclk((uint64_t)(us * MCLK_HZ / 1e6)); }

// one 68k byte access on one DUT (0 = gen_io, 1 = nuked); returns DO
static uint8_t acc1(int dut, int reg, int rnw, uint8_t d) {
	t->a = reg; t->rnw = rnw; t->di = d;
	if (dut) t->sel_n = 1; else t->sel_g = 1;
	int guard = 0;
	while ((dut ? t->dtack_n : t->dtack_g) && guard++ < 1000) tick();
	uint8_t r = dut ? t->do_n : t->do_g;
	if (dut) t->sel_n = 0; else t->sel_g = 0;
	guard = 0;
	while (!(dut ? t->dtack_n : t->dtack_g) && guard++ < 1000) tick();
	return r;
}
// the two DUTs are accessed back to back (a few MCLK apart), then 28 MCLK of "CPU time"
static void wr(int reg, uint8_t d) { acc1(0, reg, 0, d); acc1(1, reg, 0, d); wait_mclk(28); }
static void rd(const char *what, int reg) {
	uint8_t g = acc1(0, reg, 1, 0), n = acc1(1, reg, 1, 0);
	nreads++;
	bool diff = g != n;
	if (diff) ndiff++;
	printf("  %-40s reg%-2d gen_io=%02X nuked=%02X %s\n", what, reg, g, n, diff ? "<-- DIFF" : "");
	wait_mclk(28);
}
static void hard_reset() {
	t->reset = 1; wait_mclk(40); t->reset = 0; wait_mclk(200);
}
// JOY bits: 0 R 1 L 2 D 3 U 4 A 5 B 6 C 7 St 8 Mode 9 X 10 Y 11 Z
enum { R=1, L=2, D=4, U=8, BA=16, BB=32, BC=64, ST=128, MO=256, BX=512, BY=1024, BZ=2048 };

static void six_button_frame(const char *tag) {
	printf(" %s: TH toggled 8x, reads after each write\n", tag);
	const char *names[] = {"TH=1 (idle)", "TH=0 #1", "TH=1 #1", "TH=0 #2", "TH=1 #2", "TH=0 #3 (ID: low nibble 0)",
	                       "TH=1 #3 (MODE X Y Z)", "TH=0 #4 (low nibble F)", "TH=1 #4 (back to normal)"};
	wr(1, 0x40); rd(names[0], 1);
	for (int i = 1; i <= 8; i++) { wr(1, (i & 1) ? 0x00 : 0x40); rd(names[i], 1); }
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	t = new Vtb_nuked_io;
	t->sel_g = t->sel_n = 0; t->j3but = 0; t->p1 = 0; t->p2 = 0;
	hard_reset();

	printf("== 1. register file after reset (no writes)\n");
	const char *rn[16] = {"version", "data A", "data B", "data C", "ctrl A", "ctrl B", "ctrl C",
		"txdata A", "rxdata A", "sctrl A", "txdata B", "rxdata B", "sctrl B", "txdata C", "rxdata C", "sctrl C"};
	for (int r = 0; r < 16; r++) rd(rn[r], r);

	printf("== 2. 3-button protocol (J3BUT=1), P1 = A+C+Start+Up+Right, P2 = B+Down+Left\n");
	t->j3but = 1; t->p1 = BA|BC|ST|U|R; t->p2 = BB|D|L;
	wr(4, 0x40); wr(5, 0x40);
	for (int k = 0; k < 2; k++) {
		wr(1, 0x40); rd("P1 TH=1 (?1CBRLDU)", 1);
		wr(1, 0x00); rd("P1 TH=0 (?0SA00DU)", 1);
		wr(2, 0x40); rd("P2 TH=1", 2);
		wr(2, 0x00); rd("P2 TH=0", 2);
	}

	printf("== 3. 6-button protocol (J3BUT=0), P1 = X+Z+Mode+A+Left\n");
	t->j3but = 0; t->p1 = BX|BZ|MO|BA|L; t->p2 = 0;
	wait_us(2000);
	six_button_frame("3a fresh (>1.5 ms idle)");
	// counter timeout: leave the pad mid-sequence (2 TH pulses done), then resume
	printf(" 3b 2 TH pulses, 1.0 ms pause, resume (counter must NOT have reset)\n");
	wait_us(2000);
	wr(1, 0x40); wr(1, 0x00); wr(1, 0x40); wr(1, 0x00); wr(1, 0x40);
	wait_us(1000);
	wr(1, 0x00); rd("TH=0 #3 after 1.0 ms (ID nibble 0 expected)", 1);
	wr(1, 0x40); rd("TH=1 #3 (MODE X Y Z expected)", 1);
	printf(" 3c 2 TH pulses, 1.6 ms pause, resume (counter must have reset)\n");
	wait_us(2000);
	wr(1, 0x40); wr(1, 0x00); wr(1, 0x40); wr(1, 0x00); wr(1, 0x40);
	wait_us(1600);
	wr(1, 0x00); rd("TH=0 after 1.6 ms (normal ?0SA00DU expected)", 1);
	wr(1, 0x40); rd("TH=1 (normal ?1CBRLDU expected)", 1);
	printf(" 3d 3-button game on a 6-button pad: one TH pulse per frame (16.7 ms)\n");
	for (int f = 0; f < 3; f++) { wr(1, 0x40); rd("frame TH=1", 1); wr(1, 0x00); rd("frame TH=0", 1); wait_us(16700); }
	printf(" 3e 3-button-style double read every 1 ms (<1.5 ms: counter advances)\n");
	wait_us(2000);
	for (int f = 0; f < 3; f++) { wr(1, 0x40); rd("TH=1", 1); wr(1, 0x00); rd("TH=0", 1); wait_us(1000); }
	wr(1, 0x40);

	printf("== 4. TH as input: ctrl A = $00, pad pull-up\n");
	wr(1, 0x00); wr(4, 0x40); wait_us(2000); // TH driven low
	wr(4, 0x00); rd("TH released, read at once", 1);
	wait_us(40); rd("40 us later (pulled up)", 1);

	printf("== 5. chip-side register semantics\n");
	wr(4, 0x40); wr(1, 0xC0); rd("ctrl=$40 data=$C0: bit 7 readback", 1);
	wr(4, 0x7F); wr(1, 0x55); rd("ctrl=$7F data=$55: all outputs", 1);
	wr(1, 0xD5); rd("ctrl=$7F data=$D5", 1);
	wr(4, 0x40); wr(1, 0x40);
	rd("port C data, untouched", 3);
	wr(3, 0x80); rd("port C data after write $80", 3);
	wr(6, 0x7F); wr(3, 0x2A); rd("port C ctrl=$7F data=$2A", 3);
	wr(9, 0x10); wr(7, 0x5A); rd("sctrl A=$10 (SOUT 4800), txdata written: status", 9);
	wait_us(100); rd("  +100 us", 9);
	wait_us(3000); rd("  +3.1 ms (byte shifted out)", 9);
	wr(9, 0x00);
	wr(9, 0xF8); rd("sctrl A write $F8", 9);
	wr(9, 0x00); rd("sctrl A write $00", 9);
	wr(7, 0x5A); rd("txdata A write $5A", 7);
	rd("rxdata A", 8);
	wr(12, 0x38); rd("sctrl B write $38 (serial in/out on B)", 12);
	rd("data B with serial mode (TR=serial out)", 2);
	wr(12, 0x00);

	printf("== 6. TH interrupt enable (ctrl bit 7) with TH driven low\n");
	wr(4, 0xC0); wr(1, 0x40);
	printf("  HL (active low) TH=1: gen_io=%d nuked=%d\n", t->hl_g, t->hl_n);
	wr(1, 0x00); wait_mclk(4);
	printf("  HL (active low) TH=0: gen_io=%d nuked=%d %s\n", t->hl_g, t->hl_n, t->hl_g != t->hl_n ? "<-- DIFF" : "");
	if (t->hl_g != t->hl_n) ndiff++;
	wr(4, 0x40); wr(1, 0x40);

	printf("== 7. soft reset keeps the data latches? (write data $00, reset, then ctrl $40)\n");
	wr(1, 0x00); hard_reset(); wr(4, 0x40); rd("ctrl=$40 after reset, data never written", 1);
	wr(1, 0x40); rd("after data=$40", 1);

	printf("== 8. data written before ctrl (ctrl=$40 first time after reset)\n");
	hard_reset(); wr(1, 0x00); wr(4, 0x40); rd("data=$00 then ctrl=$40", 1);

	printf("\n%d reads, %d differ\n", nreads, ndiff);
	delete t;
	return 0;
}
