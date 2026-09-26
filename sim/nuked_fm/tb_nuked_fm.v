`timescale 1ns/1ps
// jt12 vs Nuked YM3438 (via src/peripherals/nuked_fm_md.v), driven exactly the way
// src/system.sv drives them:
//   * MCLK 53.7 MHz; jt12 gets FM_CLKEN (1 in 7), Nuked gets PHI = 4 high / 3 low
//   * a write is a 1-MCLK strobe (FM_SEL & ZBUS_WE); address+data then stay on the bus
//   * a read is a 1-MCLK strobe (the ZBUS_READ state), data sampled the NEXT cycle
//     (ZBUS_FINISH)
//   * writes are paced like a Z80 driver: address, 13 T-states (195 MCLK), data, then poll the
//     busy flag before the next register
// Output: per-sample (MCLK/1008) values of jt12 after mdtang's fm_adjust (x22.25) and
// Nuked's raw output, for level.py (run.sh builds and runs everything).
// Self-checks: busy seen set after every data write and cleared within the chip's 32-cycle window (~1344 MCLK).
module tb;
`ifndef LADDER_VAL
`define LADDER_VAL 1
`endif
	localparam LADDER = `LADDER_VAL;
	reg clk = 0; always #9.3 clk = ~clk;    // ~53.7 MHz

	reg [3:0] fcnt = 0; reg fm_clken = 0; reg phi = 0;
	always @(posedge clk) begin
		fm_clken <= 0;
		fcnt <= fcnt + 1'b1;
		if (fcnt == 6) begin fcnt <= 0; fm_clken <= 1; end
		phi <= (fcnt < 4);                    // same expression as system.sv
	end

	reg rst_n = 0;                          // Z80_RESET_N
	reg we = 0, rd = 0; reg [1:0] a = 0; reg [7:0] d = 0;

	wire [7:0] jt_do, nk_do;
	wire signed [15:0] jt_l, jt_r, nk_l, nk_r;
	jt12 jt(.rst(~rst_n), .clk(clk), .cen(fm_clken), .cs_n(1'b0), .addr(a), .wr_n(~we),
		.din(d), .dout(jt_do), .irq_n(), .en_hifi_pcm(1'b0), .ladder(LADDER[0]),
		.snd_left(jt_l), .snd_right(jt_r), .snd_sample());
	nuked_fm_md nk(.clk(clk), .ic_n(rst_n), .phi(phi), .cs_n(~(we | rd)), .wr_n(~we),
		.rd_n(~rd), .addr(a), .din(d), .dout(nk_do), .ladder(LADDER[0]),
		.snd_left(nk_l), .snd_right(nk_r));

	// system.sv's jt12 trim, verbatim
	wire signed [15:0] jt_adj = (jt_l << 4) + (jt_l << 2) + (jt_l << 1) + (jt_l >>> 2);

	integer busy_seen = 0, busy_max = 0, nwrites = 0, timeouts = 0, stuck = 0, first_max = 0;
	task strobe_wr(input [1:0] ad, input [7:0] v); begin
		@(posedge clk); a <= ad; d <= v; we <= 1; @(posedge clk); we <= 0;
	end endtask
	// one ZBUS status read: strobe in READ, sample in FINISH
	task rd_status(output [7:0] s); begin
		@(posedge clk); a <= 0; rd <= 1; @(posedge clk); rd <= 0; #1 s = nk_do;
	end endtask
	// Z80-realistic pacing: `ld (4000),a` / `ld (4001),a` are 13 T-states = 195 MCLK apart.
	// After the data write, poll status every 45 MCLK (one ZBUS read each) until busy has
	// been seen AND has cleared; record how long it stayed set. The chip consumes a write on
	// its own internal cycle (42 MCLK), so busy appears a cycle or two after the strobe.
	task w(input p, input [7:0] r, input [7:0] v);
		reg [7:0] s; integer n, first, last; begin
		strobe_wr({p,1'b0}, r); repeat (195) @(posedge clk);
		strobe_wr({p,1'b1}, v);
		first = -1; last = -1; n = 0;
		while (n < 80 && (first < 0 || last < 0)) begin
			repeat (44) @(posedge clk); rd_status(s); n = n + 1;
			if (s[7] && first < 0) first = n;
			if (!s[7] && first >= 0 && last < 0) last = n;
		end
		if (first < 0) timeouts = timeouts + 1;          // busy never seen
		else begin
			busy_seen = busy_seen + 1;
			if (last < 0) stuck = stuck + 1;               // busy never cleared
			else if ((last - first) * 46 > busy_max) busy_max = (last - first) * 46;
			if (first * 46 > first_max) first_max = first * 46;
		end
		nwrites = nwrites + 1;
		repeat (100) @(posedge clk);
	end endtask

	// sample both at the chip's sample rate
	integer f, scnt = 0, logging = 0;
	always @(posedge clk) begin
		scnt <= (scnt == 1007) ? 0 : scnt + 1;
		if (scnt == 0 && logging) $fwrite(f, "%0d %0d %0d %0d %0d\n", logging, jt_adj, nk_l, jt_r, nk_r);
	end

	task patch(input [1:0] ch, input [2:0] alg, input [7:0] tl_car, input [7:0] fb_alg_extra); integer i; begin
		for (i = 0; i < 4; i = i + 1) begin
			w(0, 8'h30+4*i+ch, 8'h01+i);                       // DT/MUL
			w(0, 8'h40+4*i+ch, (i==3 || alg==7) ? tl_car : 8'h20); // TL
			w(0, 8'h50+4*i+ch, 8'h1F);                         // AR max
			w(0, 8'h60+4*i+ch, 8'h00);                         // D1R 0: sustain
			w(0, 8'h70+4*i+ch, 8'h00);
			w(0, 8'h80+4*i+ch, 8'h0F);                         // SL 0, RR 15
			w(0, 8'h90+4*i+ch, 8'h00);
		end
		w(0, 8'hB0+ch, {2'b00, fb_alg_extra[2:0], alg});
		w(0, 8'hB4+ch, 8'hC0);                                  // L+R
	end endtask
	task note(input [1:0] ch, input [7:0] blk_fhi, input [7:0] flo); begin
		w(0, 8'hA4+ch, blk_fhi); w(0, 8'hA0+ch, flo); w(0, 8'h28, 8'hF0 | ch);
	end endtask
	task keyoff(input [1:0] ch); w(0, 8'h28, {6'd0, ch}); endtask
	task hold(input integer nsmp); repeat (nsmp*1008) @(posedge clk); endtask

	initial begin
		if (LADDER) f = $fopen("levels_ladder.txt"); else f = $fopen("levels_noladder.txt");
		repeat (3000) @(posedge clk); rst_n = 1; repeat (3000) @(posedge clk);
		w(0, 8'h22, 8'h00); w(0, 8'h27, 8'h00); w(0, 8'h2B, 8'h00);
		// case 1: ch1 algorithm 7 (4 sine carriers), moderate TL
		patch(0, 7, 8'h10, 0); note(0, 8'h22, 8'h69); hold(100);
		$display("case 1 t=%0t", $time); logging = 1; hold(600); logging = 0; keyoff(0); hold(100);
		// case 2: ch1 algorithm 4 (2 carriers, FM), feedback 3, loud
		patch(0, 4, 8'h00, 3); note(0, 8'h1A, 8'h40); hold(100);
		$display("case 2 t=%0t", $time); logging = 2; hold(600); logging = 0; keyoff(0); hold(100);
		// case 3: algorithm 0 (1 carrier, deep FM) on ch1 + ch2 + ch3 chord
		patch(0, 0, 8'h08, 5); patch(1, 0, 8'h08, 5); patch(2, 0, 8'h08, 5);
		note(0, 8'h22, 8'h69); note(1, 8'h22, 8'hB0); note(2, 8'h23, 8'h10); hold(100);
		$display("case 3 t=%0t", $time); logging = 3; hold(600); logging = 0; keyoff(0); keyoff(1); keyoff(2); hold(100);
		// case 4: quiet single sine (alg 7, TL 0x30) -- ladder crossover region
		patch(0, 7, 8'h30, 0); note(0, 8'h22, 8'h69); hold(100);
		$display("case 4 t=%0t", $time); logging = 4; hold(600); logging = 0; keyoff(0); hold(100);
		$display("LADDER=%0d writes=%0d busy_seen=%0d never_busy=%0d never_cleared=%0d busy_len_max~%0d MCLK first_busy_max~%0d MCLK",
			LADDER, nwrites, busy_seen, timeouts, stuck, busy_max, first_max);
		$fclose(f); $finish;
	end
endmodule
