// nuked_fm_md.v -- mdtang glue for the Nuked YM3438 (src/nuked_fm/), used instead of jt12
// when NUKED_FM is defined (build target console60k_exact_nukedfm / console60k_nukedfm).
//
// Clocking: ONE clock (MCLK, 53.7 MHz). `phi` is a LEVEL, not an enable: the chip's own
// prescaler turns its edges into the two internal phases. system.sv drives it from the /7
// FM counter, 4 MCLK high / 3 low -- the same cadence jt12's cen used. Measured
// 2026-09-26: bit-identical to the 2x-MCLK (107 MHz, 7/7) arrangement upstream uses.
//
// Bus: active-low strobes, all from the ZBUS state machine. A write is the 1-MCLK
// FM_SEL & ZBUS_WE strobe (the chip's RS trigger catches it; ZBUS_DO is held until the
// next ZBUS access). A read is a 1-MCLK strobe in the ZBUS_READ state; the chip registers
// the status on that edge, so `dout` is valid in ZBUS_FINISH, where system.sv samples it.
//
// Audio: the chip emits one channel slot per internal cycle. As MegaDrive_MiSTer's
// audio_cond.sv does, sum the slots on each falling edge of fm_clk1 and latch the sum once
// per sample on fsm_sel23 (TEST_o) -> MCLK/1008 = 53.3 kHz, the same rate jt12 produced.
//   ladder=1: MOL_2612/MOR_2612 (YM2612 DAC with its crossover step), x3 like audio_cond
//   ladder=0: MOL/MOR           (YM3438 linear DAC, 9-bit offset binary)
// Output is audio_cond's {sum, 2'b00}; system.sv applies the level trim.
//
// This file is mdtang's own code (GPL-3.0, like the rest of mdtang).
module nuked_fm_md(
	input             clk,
	input             ic_n,       // chip reset, active low (the MD ties it to the Z80 reset)
	input             phi,        // FM master clock as a level (MCLK/7)
	input             cs_n,
	input             wr_n,
	input             rd_n,
	input       [1:0] addr,
	input       [7:0] din,
	output      [7:0] dout,
	input             ladder,     // 1 = YM2612 DAC, 0 = YM3438 DAC
	output reg signed [15:0] snd_left  = 16'sd0,
	output reg signed [15:0] snd_right = 16'sd0
);

wire [8:0] mol, mor;
wire [9:0] mol2612, mor2612;
wire       fm_clk1, sel23;

ym3438 fm(
	.MCLK(clk),
	.PHI(phi),
	.DATA_i(din),
	.DATA_o(dout),
	.DATA_o_z(),
	.TEST_i(1'b0),
	.TEST_o(sel23),
	.TEST_o_z(),
	.IC(ic_n),
	.CS(cs_n),
	.WR(wr_n),
	.RD(rd_n),
	.ADDRESS(addr),
	.IRQ(),
	.MOL(mol),
	.MOR(mor),
	.MOL_2612(mol2612),
	.MOR_2612(mor2612),
	.fm_clk1(fm_clk1),
	.DAC_ch_index(),
	.ym2612_status_enable(1'b1)   // YM2612: status only at address 0, as on the MD
);

// audio_cond.sv (MegaDrive_MiSTer), minus its filters -- mdtang has its own mixer/LPF.
reg signed [13:0] fm_l = 0, fm_r = 0, acc_l = 0, acc_r = 0;
reg clk_d1 = 0, clk_d2 = 0, clk_d3 = 0, sel_d1 = 0, sel_d2 = 0;

wire signed [13:0] m3_l = {{6{~mol[8]}}, mol[7:0]};
wire signed [13:0] m3_r = {{6{~mor[8]}}, mor[7:0]};
wire signed [13:0] m2_l = {{5{mol2612[9]}}, mol2612[8:0]};
wire signed [13:0] m2_r = {{5{mor2612[9]}}, mor2612[8:0]};

always @(posedge clk) begin
	fm_l <= ladder ? (m2_l + m2_l + m2_l) : m3_l;
	fm_r <= ladder ? (m2_r + m2_r + m2_r) : m3_r;

	clk_d1 <= fm_clk1; clk_d2 <= clk_d1; clk_d3 <= clk_d2;
	sel_d1 <= sel23;   sel_d2 <= sel_d1;

	if (clk_d3 & ~clk_d2) begin
		acc_l <= acc_l + fm_l;
		acc_r <= acc_r + fm_r;
		if (sel_d2) begin
			snd_left  <= {acc_l + fm_l, 2'b00};
			snd_right <= {acc_r + fm_r, 2'b00};
			acc_l <= 0;
			acc_r <= 0;
		end
	end
end

endmodule
