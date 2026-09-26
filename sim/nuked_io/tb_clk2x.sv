// YM6046 alone at 1x MCLK (VCLK level 4 high / 3 low, 2-MCLK strobes -- what gen_io_nuked
// does) vs 2x MCLK (VCLK 7/7, 4-cycle strobes -- the upstream Nuked-MD arrangement).
// Same bus sequence in real time; compares every read and the port pins every 1x cycle.
// Measured 2026-09-26: 0 of 3641 reads differ; the pins differ only around serial TX bit
// edges, by <= 6 1x cycles (~110 ns of a 208 us bit): the ripple baud divider adds one
// MCLK per stage, which is 18.6 ns at 1x and 9.3 ns at 2x. Invisible to the 68k.
// The A->B TL loopback transmits (TR toggles, TXFULL clears) but B's receiver never
// reports a byte in either clocking; mdtang has no serial device, so not pursued.
`timescale 1ns/1ps
module tb_clk2x;
	reg c1 = 0, c2 = 0;
	always #9.3 c2 = ~c2;                       // 2x MCLK
	always @(posedge c2) c1 <= ~c1;              // 1x MCLK, derived: aligned edges
	reg [2:0] n1 = 0; reg v1 = 0;
	reg [3:0] n2 = 0; reg v2 = 0;
	always @(posedge c1) begin n1 <= (n1 == 6) ? 0 : n1 + 1; v1 <= (n1 < 4); end
	always @(posedge c2) begin n2 <= (n2 == 13) ? 0 : n2 + 1; v2 <= (n2 < 7); end

	reg sres = 0, io = 1, cas = 1, lwr = 1;
	reg [6:0] va = 0; reg [7:0] vd = 0;
	wire [6:0] d1a, d1b, d1c, o1a, o1b, o1c, d2a, d2b, d2c, o2a, o2b, o2c;
	wire [7:0] r1, r2; wire h1, h2;
	// pins: outputs read back, inputs pulled up except TL (bit 5) looped from port B TR (bit 4)
	wire [6:0] i1a = (d1a & 7'h7F) | (~d1a & o1a);
	wire [6:0] i2a = (d2a & 7'h7F) | (~d2a & o2a);
	wire [6:0] i1b = (d1b & {1'b1, o1a[4], 5'h1F}) | (~d1b & o1b);
	wire [6:0] i2b = (d2b & {1'b1, o2a[4], 5'h1F}) | (~d2b & o2b);
`define CHIP(M, V, IA, IB, DA, DB, DC, OA, OB, OC, R, H) \
	ym6046 u``M(.MCLK(M), .PORT_A_i(IA), .PORT_B_i(IB), .PORT_C_i(7'h7F), .test(1'b0), .M3(1'b1), \
		.IO(io), .CAS0(cas), .SRES(sres), .VCLK(V), .NTSC(1'b1), .DISK(1'b1), .JAP(1'b1), .ZA_i(8'h0), \
		.ZD_i(8'h0), .VA_i(va), .VD_i({8'h0, vd}), .LWR(lwr), .t1(1'b0), .ZV(1'b1), .VZ(1'b1), \
		.PORT_A_d(DA), .PORT_B_d(DB), .PORT_C_d(DC), .PORT_A_o(OA), .PORT_B_o(OB), .PORT_C_o(OC), \
		.HL(H), .FRES(), .bc1(), .bc2(), .bc3(), .bc4(), .bc5(), .vdata(R), .reg_3e_q(), .zdata(), \
		.ztov_address(), .tmss_enable(1'b0));
	`CHIP(c1, v1, i1a, i1b, d1a, d1b, d1c, o1a, o1b, o1c, r1, h1)
	`CHIP(c2, v2, i2a, i2b, d2a, d2b, d2c, o2a, o2b, o2c, r2, h2)

	integer nrd = 0, nrdiff = 0, npin = 0;
	integer run = 0, maxrun = 0, ntr = 0; reg ptr = 1;
	always @(posedge c1) begin ptr <= o1a[4]; if (ptr != o1a[4]) ntr = ntr + 1; end
	reg [7:0] st12 = 0; always @(posedge c1) if (~io & ~cas & va == 12) st12 <= r1;
	always @(posedge c1) if ({d1a,o1a,d1b,o1b,h1} !== {d2a,o2a,d2b,o2b,h2}) begin
		npin = npin + 1; run = run + 1; if (run > maxrun) maxrun = run;
		if (npin <= 6) $display("pin diff t=%0t 1x: oa=%02x ob=%02x 2x: oa=%02x ob=%02x", $time, o1a, o1b, o2a, o2b);
	end else run = 0;

	task automatic wr(input [3:0] a, input [7:0] d);
		@(posedge c1); va = a; vd = d; io = 0; lwr = 0;
		repeat (2) @(posedge c1); io = 1; lwr = 1; repeat (28) @(posedge c1);
	endtask
	task automatic rd(input [3:0] a);
		@(posedge c1); va = a; io = 0; cas = 0;
		repeat (2) @(posedge c1);
		nrd = nrd + 1; if (r1 !== r2) begin nrdiff = nrdiff + 1; $display("read %0d reg%0d: 1x=%02x 2x=%02x", nrd, a, r1, r2); end
		io = 1; cas = 1; repeat (28) @(posedge c1);
	endtask
	integer i, k;
	initial begin
		repeat (100) @(posedge c1); sres = 1; repeat (100) @(posedge c1);
		for (i = 0; i < 16; i = i + 1) rd(i);
		wr(4, 8'h40); for (i = 0; i < 20; i = i + 1) begin wr(1, i[0] ? 8'h40 : 8'h00); rd(1); end
		wr(4, 8'hC0); wr(1, 8'h00); rd(1); wr(1, 8'h40);
		// serial: A transmits on TR at each baud rate, B receives it on TL; poll status and data
		for (k = 0; k < 4; k = k + 1) begin
			wr(12, {k[1:0], 6'b100000});             // B: SIN, rate k
			wr(9,  {k[1:0], 6'b010000});             // A: SOUT, rate k
			wr(7, 8'hA5 ^ k);
			for (i = 0; i < 450; i = i + 1) begin rd(9); rd(12); repeat (5000) @(posedge c1); end  // ~42 ms
			@(posedge c1); va = 11; io = 0; cas = 0; repeat (2) @(posedge c1); $display("TR edges so far %0d, last B status %02x, d1a=%02x d1b=%02x", ntr, st12, d1a, d1b); $display("rate %0d: sent %02x, B received 1x=%02x 2x=%02x", k, 8'hA5 ^ k, r1, r2); io = 1; cas = 1; repeat (28) @(posedge c1); rd(12);
		end
		$display("reads: %0d, differing: %0d; 1x cycles with differing pins/HL: %0d (longest run %0d)", nrd, nrdiff, npin, maxrun);
		$finish;
	end
endmodule
