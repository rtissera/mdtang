// Modifications copyright (c) 2026 Romain Tisserand.
// Derived from this repository's own src/framebuffer_sync.sv (nand2mario, 2024.10);
// only the changes are covered above. GPL-3.0-or-later, as the file it derives from.
//
// EXACT-LOCK MEGA DRIVE -> HDMI, line-buffered (2026-09-22).
//
// src/framebuffer_sync.sv buffers 32 lines AND pauses the emulated Mega Drive once per
// frame (`pause_core`) to stop the two rasters drifting apart, because its 74.25 MHz
// pixel clock has no relationship to the core clock.
//
// Here both clocks come off ONE VCO (see src/plla/pll_exact.v):
//
//     one source line  = 3420 core clocks = 2 output lines of 855 pixel clocks
//     one source frame = 262 source lines = 524 output lines
//
// so the rasters cannot drift, three line buffers replace the 32, and NOTHING EVER PAUSES
// THE CORE: `pause_core` is tied low. The technique is from MiSTle-Dev/c64nano (harbaum)
// via this author's pcetang core.
//
// Output is the real CEA 720x480 active area declared as VIC 2 (mode 201 in hdmi.sv), the
// picture centred: x2 vertically, and horizontally scaled to height*3 so that 224-line
// modes get a 672-pixel window and 240-line modes fill all 720 -- 4:3 either way, inside a
// frame the sink already displays as 4:3. Both Mega Drive widths (256 H32, 320 H40) map
// onto that same window, which is what a real console does on a real TV.

module framebuffer_exact #(
    parameter WIDTH = 320,          // max frame width
    parameter HEIGHT = 240,         // max frame height
    parameter COLOR_BITS = 4        // bits per RGB colour channel
)(
    input clk,                      // megadrive clock, 53.75 MHz
    input resetn,
    input clk_pixel,                // 26.875 MHz, EXACTLY clk/2 off the same VCO
    input clk_5x_pixel,             // 134.375 MHz

    // video signals
    input ce_pix,
    input [COLOR_BITS-1:0] r,
    input [COLOR_BITS-1:0] g,
    input [COLOR_BITS-1:0] b,
    input [$clog2(WIDTH)-1:0] x,
    input [$clog2(HEIGHT)-1:0] y,
    input [10:0] width,             // 256 (H32) or 320 (H40)
    input [9:0] height,             // 224 or 240

    output pause_core,              // tied low: an exact lock never needs to stall the core

    // overlay from iosys
    input overlay,
    output [7:0] overlay_x,
    output [7:0] overlay_y,
    input [14:0] overlay_color,     // BGR5

    input [15:0] audio_left,
    input [15:0] audio_right,

    // HDMI output signals
    output       tmds_clk_n,
    output       tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p
);

localparam CLKFRQ = 26875;          // clk_pixel in kHz
localparam AUDIO_BIT_WIDTH = 16;
localparam AUDIO_RATE = 48000;
localparam COLOR_WIDTH = COLOR_BITS * 3;
localparam int N_LINE_BUF = 3;

assign pause_core = 1'b0;

wire [10:0] cx;
wire [9:0]  cy;

// ---------------------------------------------------------------------------------------
// Three line buffers: 3 x 320 x 12 bits = 11520 bits, against 32 x 320 x 12 = 122880 for
// the 32-line buffer this replaces.
// ---------------------------------------------------------------------------------------
reg [COLOR_WIDTH-1:0] linebuf [0:N_LINE_BUF*WIDTH-1];
reg [1:0] wr_sel = 2'd0;
reg [$clog2(HEIGHT)-1:0] y_r = 0;

always @(posedge clk) begin
    y_r <= y;
    if (ce_pix) begin
        // restart at buffer 0 on source line 0 so line s always lands in buffer s mod 3;
        // otherwise the phase slips against the read side (which restarts every frame)
        if (y != y_r)
            wr_sel <= (y == 0 || wr_sel == N_LINE_BUF-1) ? 2'd0 : wr_sel + 2'd1;
        if (x < width)
            linebuf[wr_sel*WIDTH + x] <= {b, g, r};
    end
end

// ---------------------------------------------------------------------------------------
// Frame phase. Under an exact lock the raster cannot drift, so the phase is set, not
// servoed: `vreset` loads the HDMI raster when the source starts line 0, with cy = ytop - 2
// (mod 524). Source line s is then displayed on ytop + 2s and ytop + 2s + 1, exactly one
// source line after it was written, while the writer fills buffer (s+1) mod 3.
// hdmi.sv's `vreset` touches cx/cy only -- never its full `reset`, which fans out to the
// serializer on the 134 MHz clock and costs real timing margin.
// It fires at power-up and again ONLY when a source frame starts outside the expected
// window: a reset or game load (VDP counters restart) or a 224/240-line switch (ytop moves).
// Interlaced MD modes (262/263 lines) are not handled and would re-fire every frame.
// ---------------------------------------------------------------------------------------
localparam [9:0]  V_TOTAL = 524;
localparam [10:0] H_TOTAL = 855;
wire [9:0] ytop_w    = (10'd480 - {height, 1'b0}) >> 1;
wire [9:0] vreset_cy = (ytop_w >= 10'd2) ? ytop_w - 10'd2 : ytop_w + V_TOTAL - 10'd2;
wire [9:0] vreset_cy_m1 = (vreset_cy == 10'd0) ? V_TOTAL - 10'd1 : vreset_cy - 10'd1;

reg frame_tog   = 1'b0;
reg fs_meta     = 1'b0, fs_sync = 1'b0, fs_sync_r = 1'b0;
reg vreset      = 1'b0;

always @(posedge clk) begin
    if (ce_pix && y == 0 && y_r != 0)
        frame_tog <= ~frame_tog;
end

wire in_phase = (cy == vreset_cy && cx < 11'd24) || (cy == vreset_cy_m1 && cx >= H_TOTAL - 11'd24);

always @(posedge clk_pixel) begin
    fs_meta   <= frame_tog;
    fs_sync   <= fs_meta;
    fs_sync_r <= fs_sync;
    vreset    <= (fs_sync != fs_sync_r) && !in_phase;
end

// ---------------------------------------------------------------------------------------
// Read side. Vertical: each source line shown twice. Horizontal: a fractional counter
// walks `width` source pixels across a window of height*3 pixels.
// ---------------------------------------------------------------------------------------
wire [10:0] dst_w  = {height, 1'b0} + height;       // height * 3  (672 or 720)
wire [10:0] xstart = (11'd720 - dst_w) >> 1;
wire [9:0]  ytop   = (10'd480 - {height, 1'b0}) >> 1;

wire v_in = (cy >= ytop) && (cy < ytop + {height, 1'b0});
wire h_in = (cx >= xstart) && (cx < xstart + dst_w);

reg [$clog2(WIDTH)-1:0] src_x = 0;
reg [11:0] xacc = 0;
reg [1:0]  rd_sel = 2'd0;
reg        active = 1'b0;
reg [COLOR_WIDTH-1:0] px;
reg [23:0] rgb;

always @(posedge clk_pixel) begin
    if (cx == 0) begin
        if (cy == ytop)                 rd_sel <= 2'd0;
        // advance on the FIRST output line of each pair (same parity as ytop)
        else if (v_in && cy[0] == ytop[0]) rd_sel <= (rd_sel == N_LINE_BUF-1) ? 2'd0 : rd_sel + 2'd1;
    end
end

always @(posedge clk_pixel) begin
    active <= v_in && h_in;

    if (cx == 0) begin
        src_x <= 0;
        xacc  <= 0;
    end else if (v_in && h_in) begin
        xacc <= xacc + {1'b0, width};
        if (xacc + {1'b0, width} >= {1'b0, dst_w}) begin
            xacc  <= xacc + {1'b0, width} - {1'b0, dst_w};
            src_x <= src_x + 1'd1;
        end
    end

    px <= linebuf[rd_sel*WIDTH + src_x];

    if (active) begin
        if (overlay)
            rgb <= {overlay_color[4:0],3'b0, overlay_color[9:5],3'b0, overlay_color[14:10],3'b0};
        else
            rgb <= {px[COLOR_BITS-1:0], 4'b0,
                    px[COLOR_BITS*2-1:COLOR_BITS], 4'b0,
                    px[COLOR_BITS*3-1:COLOR_BITS*2], 4'b0};
    end else
        rgb <= 24'h000000;
end

assign overlay_x = src_x[7:0];
assign overlay_y = ((cy - ytop) >> 1);

// ---------------------------------------------------------------------------------------
// Audio: same shape as framebuffer_sync.sv, but divided from 26.875 MHz.
// ---------------------------------------------------------------------------------------
localparam AUDIO_CLK_DELAY = CLKFRQ * 1000 / AUDIO_RATE / 2;
logic [$clog2(AUDIO_CLK_DELAY)-1:0] audio_divider;
logic clk_audio;

always_ff @(posedge clk_pixel) begin
    if (audio_divider != AUDIO_CLK_DELAY - 1)
        audio_divider <= audio_divider + 1'd1;
    else begin
        clk_audio     <= ~clk_audio;
        audio_divider <= 0;
    end
end

reg [15:0] audio_sample_word [1:0], audio_sample_word0 [1:0];
always @(posedge clk_pixel) begin
    audio_sample_word0[0] <= audio_left;
    audio_sample_word[0]  <= audio_sample_word0[0];
    audio_sample_word0[1] <= audio_right;
    audio_sample_word[1]  <= audio_sample_word0[1];
end

// ---------------------------------------------------------------------------------------
// HDMI output: mode 201 (855 x 524, 720x480 active, declared VIC 2).
// ---------------------------------------------------------------------------------------
logic [2:0] tmds;
logic       tmdsClk;

hdmi #( .VIDEO_ID_CODE(201),
        .DVI_OUTPUT(0),
        .VIDEO_REFRESH_RATE(60.0),
        .IT_CONTENT(1),
        .AUDIO_RATE(AUDIO_RATE),
        .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
        .START_X(0),
        .START_Y(0) )
hdmi( .clk_pixel_x5(clk_5x_pixel),
        .clk_pixel(clk_pixel),
        .clk_audio(clk_audio),
        .rgb(rgb),
        .reset(1'b0),
        .vreset(vreset),
        .vreset_cy(vreset_cy),
        .audio_sample_word(audio_sample_word),
        .tmds(tmds),
        .tmds_clock(tmdsClk),
        .cx(cx),
        .cy(cy),
        .frame_width(),
        .frame_height() );

ELVDS_OBUF tmds_bufds [3:0] (
    .I({clk_pixel, tmds}),
    .O({tmds_clk_p, tmds_d_p}),
    .OB({tmds_clk_n, tmds_d_n})
);

endmodule
