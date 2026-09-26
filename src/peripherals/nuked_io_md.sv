// nuked_io_md.sv -- mdtang glue for the Nuked YM6046 I/O controller (src/nuked_io/), used
// in place of gen_io when NUKED_IO is defined (build target console60k_exact_nukedio).
//
// gen_io_nuked has gen_io's exact port list, so multitap.sv instantiates it with the same
// `.*`. Mouse, light gun and serial-joystick inputs are accepted and ignored: mdtang ties
// them all off (mdtang_top.sv), and this option does not model them.
//
// What is the chip and what is not. The YM6046 is the console side only: data, control
// and serial registers, pin direction, TH interrupt, UART. It has NO pad protocol -- the
// 3/6-button multiplexing and the 6-button TH counter live inside the pad. So the pad
// side is modelled here (md_pad below), with the same behaviour as gen_io's pad_io, so
// that any difference between the two options is the chip's.
//
// Pins: the chip reads its pins raw (PORT_x_i); PORT_x_d = 1 means input. A pin the chip
// drives reads back its own output; an input pin reads the pad (or the pull-up).
//
// Clocking: ONE clock (MCLK, 53.7 MHz). Every ym_lib cell used by ym6046 samples a LEVEL
// on MCLK (two-latch flops); there is no edge detector. VCLK is a level from a local /7
// counter, 4 high / 3 low (as FM_PHI on feat/nuked-fm); it only times the reset
// synchroniser and the UART baud divider. The bus strobes (IO, CAS0, LWR) are levels held
// for 2 MCLK: a register takes the data present while its strobe is low, on the release.
//
// This file is mdtang's own code (GPL-3.0, like the rest of mdtang). md_pad's protocol
// table and timer values come from gen_io.sv's pad_io (Gregory Estrade, Sorgelig).
module gen_io_nuked
(
	input            RESET,
	input            CLK,
	input            CE,          // unused: the chip runs on MCLK with its own VCLK level

	input            J3BUT,

	input            P1_UP, P1_DOWN, P1_LEFT, P1_RIGHT, P1_A, P1_B, P1_C, P1_START,
	input            P1_MODE, P1_X, P1_Y, P1_Z,
	input            P2_UP, P2_DOWN, P2_LEFT, P2_RIGHT, P2_A, P2_B, P2_C, P2_START,
	input            P2_MODE, P2_X, P2_Y, P2_Z,

	input            DISK,

	input     [24:0] MOUSE,
	input      [2:0] MOUSE_OPT,

	input            GUN_OPT,
	input            GUN_TYPE,
	input            GUN_SENSOR,
	input            GUN_A,
	input            GUN_B,
	input            GUN_C,
	input            GUN_START,

	input      [7:0] SERJOYSTICK_IN,
	output     [7:0] SERJOYSTICK_OUT,
	input      [1:0] SER_OPT,

	input            SEL,
	input      [4:1] A,
	input            RNW,
	input      [7:0] DI,
	output reg [7:0] DO,
	output reg       DTACK_N,
	output reg       HL,

	input            PAL,
	input            EXPORT
);

assign SERJOYSTICK_OUT = 8'hFF;

// ---- VCLK level: MCLK/7, 4 high / 3 low -----------------------------------------------
reg [2:0] vcnt = 3'd0;
reg       vclk = 1'b0;
always @(posedge CLK) begin
	vcnt <= (vcnt == 3'd6) ? 3'd0 : vcnt + 3'd1;
	vclk <= (vcnt < 3'd4);
end

// ---- 68k bus -> chip strobes ------------------------------------------------------------
reg       io_n = 1'b1, cas0_n = 1'b1, lwr_n = 1'b1;
reg [3:0] va = 4'd0;
reg [7:0] vd = 8'd0;
reg [1:0] bstate = 2'd0;
wire [7:0] vdata;

always @(posedge CLK or posedge RESET) begin
	if (RESET) begin
		bstate  <= 2'd0;
		io_n    <= 1'b1;
		cas0_n  <= 1'b1;
		lwr_n   <= 1'b1;
		DTACK_N <= 1'b1;
		DO      <= 8'hFF;
	end
	else case (bstate)
		2'd0: if (SEL & DTACK_N) begin
			va     <= A;
			vd     <= DI;
			io_n   <= 1'b0;
			cas0_n <= ~RNW;
			lwr_n  <= RNW;
			bstate <= 2'd1;
		end
		2'd1: bstate <= 2'd2;                  // strobe low for 2 MCLK
		2'd2: begin
			if (~cas0_n) DO <= vdata;          // combinational read path, stable by now
			io_n    <= 1'b1;
			cas0_n  <= 1'b1;
			lwr_n   <= 1'b1;
			DTACK_N <= 1'b0;
			bstate  <= 2'd3;
		end
		2'd3: if (~SEL) begin
			DTACK_N <= 1'b1;
			bstate  <= 2'd0;
		end
	endcase
end

// ---- chip ---------------------------------------------------------------------------------
wire [6:0] pa_i, pb_i, pc_i, pa_d, pb_d, pc_d, pa_o, pb_o, pc_o;
wire       hl_n;
wire [5:0] pad1, pad2;
wire       th1, th2;

ym6046 ioc
(
	.MCLK(CLK),
	.PORT_A_i(pa_i),
	.PORT_B_i(pb_i),
	.PORT_C_i(pc_i),
	.test(1'b0),
	.M3(1'b1),              // Mega Drive mode (0 = Mark III / SMS mode)
	.IO(io_n),
	.CAS0(cas0_n),
	.SRES(~RESET),
	.VCLK(vclk),
	.NTSC(~PAL),
	.DISK(~DISK),           // pin is active low: 0 = Mega-CD attached
	.JAP(EXPORT),           // version bit 7: 1 = overseas
	.ZA_i(8'h00),
	.ZD_i(8'h00),
	.VA_i({3'b000, va}),
	.VD_i({8'h00, vd}),
	.LWR(lwr_n),
	.t1(1'b0),
	.ZV(1'b1),
	.VZ(1'b1),
	.PORT_A_d(pa_d),
	.PORT_B_d(pb_d),
	.PORT_C_d(pc_d),
	.PORT_A_o(pa_o),
	.PORT_B_o(pb_o),
	.PORT_C_o(pc_o),
	.HL(hl_n),
	.FRES(),
	.bc1(), .bc2(), .bc3(), .bc4(), .bc5(),
	.vdata(vdata),
	.reg_3e_q(),
	.zdata(),
	.ztov_address(),
	.tmss_enable(1'b0)      // Model 1 without TMSS: version bit 0 = 0, as gen_io
);

// Pin levels. Output pins read back what the chip drives; input pins read the pad, TH
// (pin 6) reads the pad-side TH level (pull-up with its float delay, see md_pad).
assign pa_i = (pa_d & {th1, pad1}) | (~pa_d & pa_o);
assign pb_i = (pb_d & {th2, pad2}) | (~pb_d & pb_o);
assign pc_i = (pc_d & 7'h7F) | (~pc_d & pc_o);  // port C: nothing plugged, pulled up

always @(posedge CLK) HL <= hl_n;

md_pad pad_1(
	.clk(CLK), .reset(RESET), .j3but(J3BUT),
	.th_d(pa_d[6]), .th_o(pa_o[6]), .th(th1),
	.p_up(P1_UP), .p_down(P1_DOWN), .p_left(P1_LEFT), .p_right(P1_RIGHT),
	.p_a(P1_A), .p_b(P1_B), .p_c(P1_C), .p_start(P1_START),
	.p_mode(P1_MODE), .p_x(P1_X), .p_y(P1_Y), .p_z(P1_Z),
	.dout(pad1)
);

md_pad pad_2(
	.clk(CLK), .reset(RESET), .j3but(J3BUT),
	.th_d(pb_d[6]), .th_o(pb_o[6]), .th(th2),
	.p_up(P2_UP), .p_down(P2_DOWN), .p_left(P2_LEFT), .p_right(P2_RIGHT),
	.p_a(P2_A), .p_b(P2_B), .p_c(P2_C), .p_start(P2_START),
	.p_mode(P2_MODE), .p_x(P2_X), .p_y(P2_Y), .p_z(P2_Z),
	.dout(pad2)
);

endmodule


// Sega 3/6-button pad, as seen from its connector. Buttons are active low (pin levels).
// Same protocol and timings as gen_io's pad_io, but counted in MCLK (x7), so they no
// longer depend on the 68k clock enable (pause/turbo):
//   - TH follows the console's TH output; when the console stops driving it, the pull-up
//     takes it high after 210 x 7 MCLK (~27 us).
//   - rising TH edges count 0..3 (6-button); 1.5 ms (11600 x 7 MCLK) after the last
//     falling edge the counter returns to 0. J3BUT holds it at 0 (3-button pad).
module md_pad(
	input        clk,
	input        reset,
	input        j3but,
	input        th_d,       // console TH direction: 1 = console input (not driving)
	input        th_o,       // console TH output level
	output reg   th,         // TH level at the pad
	input        p_up, p_down, p_left, p_right, p_a, p_b, p_c, p_start,
	input        p_mode, p_x, p_y, p_z,
	output reg [5:0] dout
);

reg  [1:0] jcnt;
reg [16:0] jtmr;
reg [10:0] fltmr;
reg        thd;

always @(*) begin
	if (th)
		if (jcnt != 3)   dout = {p_c, p_b, p_right, p_left, p_down, p_up};
		else             dout = {p_c, p_b, p_mode, p_x, p_y, p_z};
	else if (jcnt < 2)  dout = {p_start, p_a, 2'b00, p_down, p_up};
	else if (jcnt == 2) dout = {p_start, p_a, 4'b0000};
	else                dout = {p_start, p_a, 4'b1111};
end

always @(posedge clk or posedge reset) begin
	if (reset) begin
		th    <= 1'b1;
		thd   <= 1'b1;
		jcnt  <= 2'd3;
		jtmr  <= 17'd0;
		fltmr <= 11'd0;
	end
	else begin
		if (~&fltmr) fltmr <= fltmr + 11'd1;
		if (~th_d) begin
			th    <= th_o;
			fltmr <= 11'd0;
		end
		else if (fltmr == 11'd1470) th <= 1'b1;

		thd <= th;
		if (jtmr > 17'd81200 || j3but) jcnt <= 2'd0;
		if (~thd & th) jcnt <= jcnt + 2'd1;

		if (~&jtmr) jtmr <= jtmr + 17'd1;
		if (thd & ~th) jtmr <= 17'd0;
	end
end

endmodule
