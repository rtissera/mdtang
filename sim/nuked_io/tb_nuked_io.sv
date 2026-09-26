// gen_io and gen_io_nuked side by side: same pads, same reset, separate bus handshakes
// (each DUT answers in its own time). Driven from tb_nuked_io.cpp.
module tb_nuked_io(
	input         clk,
	input         reset,
	input         ce,
	input         j3but,
	input  [11:0] p1,      // {Z,Y,X,Mode,Start,C,B,A,Up,Down,Left,Right}, active high (JOY_1)
	input  [11:0] p2,
	input         sel_g, sel_n,
	input   [4:1] a,
	input         rnw,
	input   [7:0] di,
	output  [7:0] do_g, do_n,
	output        dtack_g, dtack_n,
	output        hl_g, hl_n
);
`define PADS(J) \
	.P1_UP(~p1[3]),.P1_DOWN(~p1[2]),.P1_LEFT(~p1[1]),.P1_RIGHT(~p1[0]),.P1_A(~p1[4]),.P1_B(~p1[5]), \
	.P1_C(~p1[6]),.P1_START(~p1[7]),.P1_MODE(~p1[8]),.P1_X(~p1[9]),.P1_Y(~p1[10]),.P1_Z(~p1[11]), \
	.P2_UP(~p2[3]),.P2_DOWN(~p2[2]),.P2_LEFT(~p2[1]),.P2_RIGHT(~p2[0]),.P2_A(~p2[4]),.P2_B(~p2[5]), \
	.P2_C(~p2[6]),.P2_START(~p2[7]),.P2_MODE(~p2[8]),.P2_X(~p2[9]),.P2_Y(~p2[10]),.P2_Z(~p2[11]), \
	.DISK(1'b0),.MOUSE(25'd0),.MOUSE_OPT(3'd0),.GUN_OPT(1'b0),.GUN_TYPE(1'b0),.GUN_SENSOR(1'b0), \
	.GUN_A(1'b0),.GUN_B(1'b0),.GUN_C(1'b0),.GUN_START(1'b0),.SERJOYSTICK_IN(8'd0),.SERJOYSTICK_OUT(), \
	.SER_OPT(2'd0),.PAL(1'b0),.EXPORT(1'b1),.RESET(reset),.CLK(clk),.CE(ce),.J3BUT(j3but), \
	.A(a),.RNW(rnw),.DI(di)

gen_io       g(`PADS(0), .SEL(sel_g), .DO(do_g), .DTACK_N(dtack_g), .HL(hl_g));
gen_io_nuked n(`PADS(0), .SEL(sel_n), .DO(do_n), .DTACK_N(dtack_n), .HL(hl_n));
endmodule
