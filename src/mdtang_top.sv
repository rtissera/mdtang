// Mega Drive / Genesis core for Tang FPGA boards
// nand2mario, 10/2024
module mdtang_top (
    input clk50,                    // 50Mhz

`ifdef VERILATOR
	input clk_sys,
    input clk_z80,                  // 1/2 clk_sys

	input [11:0] joy_btns,          // snes layout: R L X A RT LT DN UP START SELECT Y B, active high
    input [11:0] joy2_btns,

    input [2:0] loading,            // 0: gba on, 1: loading rom, 2: loading cartram, 3: set up flash backup
    input [7:0] loader_do,
    input loader_do_valid,
`endif

    // MicroSD
`ifndef PRIMER25K
    output sd_clk,
    inout  sd_cmd,                  // MOSI
    input  sd_dat0,                 // MISO
    output sd_dat1,
    output sd_dat2,
    output sd_dat3,

    // SPI flash
    output flash_spi_cs_n,          // chip select
    input flash_spi_miso,           // master in slave out
    output flash_spi_mosi,          // mster out slave in
    output flash_spi_clk,           // spi clock
    output flash_spi_wp_n,          // write protect
    output flash_spi_hold_n,        // hold operations
`endif

    // dualshock controller
    output ds_clk,
    input ds_miso,
    output ds_mosi,
    output ds_cs,
    output ds2_clk,
    input ds2_miso,
    output ds2_mosi,
    output ds2_cs,

    // USB1 and USB2
`ifdef USB1
    inout usb1_dp,
    inout usb1_dn,
`endif
`ifdef USB2
    inout usb2_dp,
    inout usb2_dn,
`endif

    // SDRAM
    output O_sdram_clk,
    output O_sdram_cs_n,            // chip select
    output O_sdram_cas_n,           // columns address select
    output O_sdram_ras_n,           // row address select
    output O_sdram_wen_n,           // write enable
    inout [15:0] IO_sdram_dq,       // 16 bit bidirectional data bus
    output [12:0] O_sdram_addr,     // 13 bit multiplexed address bus
    output [1:0] O_sdram_dqm,       // 
    output [1:0] O_sdram_ba,        // 4 banks

    // UART
    input UART_RXD,
    output UART_TXD,    

`ifdef PRIMER25K
    output [1:0] led,          // this board has two LEDs, and pins are the tight resource
`else
    output [7:0] led,
`endif
    input s0,
`ifndef PRIMER25K
    input s1,               // unused by this core beyond a commented-out start gate
`endif

    // HDMI output
    output       tmds_clk_n,
    output       tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p    
);

// Clocking and global signals -----------------------------------------------------------
// 53.69Mhz master clock
`ifndef VERILATOR

wire clk_sys, clk27;
wire hclk, hclk5;   // 74.25Mhz hdmi 720p pixel clock
wire clk_z80;       // 26.85Mhz (1/2 clk_sys)

// use interal OSC
// OSC u_osc (.OSCOUT(clk_in) );
// defparam u_osc.FREQ_DIV = 4;//210/4=52.5MHz

// pll_27b pll27(.clkin(clk_in),.clkout0(clk27));
// pll_all pllall(.clkout0(clk_sys),.clkout1(O_sdram_clk),.clkout2(hclk), .clkout3(hclk5),.clkin(clk27));

// use external osc
`ifdef EXACT_LOCK
// EXACT LOCK (2026-09-22): one VCO for core, SDRAM, Z80 and both video clocks, so every
// source line is exactly two output lines -- no frame buffer and no core pause needed.
// See src/plla/pll_exact.v and src/framebuffer_exact.sv.
// The Z80 clock is the PLL's own /2 output, phase 0, as in the stock build. An earlier
// version divided clk_sys with a CLKDIV instead; static timing passed, but on hardware
// Castlevania Bloodlines had no sound, flickered and could lock up going in-game, and
// taking the PLL output fixed all three (Console 60K, 2026-09-27).
pll_exact pll(.clkin(clk50), .clkout0(clk_sys), .clkout1(O_sdram_clk), .clkout2(clk_z80),
              .clkout3(hclk), .clkout4(hclk5));
assign clk27 = 1'b0;            // the 27 MHz chain existed only to reach 74.25 MHz
`else
pll pll(.clkin(clk50), .clkout0(clk_sys), .clkout1(O_sdram_clk), .clkout2(clk_z80));
pll_27 pll27(.clkin(clk50), .clkout0(clk27));
pll_74 pll74(.clkin(clk27), .clkout0(hclk), .clkout1(hclk5));
`endif

wire [2:0]  loading;
wire        loader_do_valid;
wire [7:0]  loader_do;
wire [11:0] joy_btns, joy2_btns;
wire [11:0] joy_usb1, joy_usb2;
wire [11:0] hid1, hid2;
`endif

localparam FREQ = 53_750_000;

// reset logic
reg        reset /* verilator public */ = 1;
reg [15:0]  reset_cnt = 65535;
always @(posedge clk_sys) begin
    if (reset_cnt != 0) reset_cnt <= reset_cnt - '1;
    // if (reset_cnt == 0 && s1 == 0)       // press s1 to start
    if (reset_cnt == 0)
        reset <= 0;
end


/* verilator public_on */
reg        md_on;
wire [1:0] resolution;          // {V30, H40}, V30: verticle 240 vs 224, H40: horizontal 320 vs 256
wire ce_pix, hblank, vblank, hsync;
wire       pause_core;
wire [3:0] red   /* xsynthesis syn_keep=1 */, 
           green /* xsynthesis syn_keep=1 */, 
           blue  /* xsynthesis syn_keep=1 */;
wire [15:0] audio_left, audio_right;
/* verilator public_off */

wire [24:1] mem_addr;
wire [15:0] mem_data, mem_wdata;
wire [1:0] mem_be;
wire mem_req, mem_ack, mem_we;

wire [11:0] joy1 = btn_snes2md(joy_btns | hid1 | joy_usb1);
wire [11:0] joy2 = btn_snes2md(joy2_btns | hid2 | joy_usb2);

// ROM loader address (declared here, before its first use below).
// 23 bits = 8 MB, the whole ROM area of the SDRAM (0000000-07FFFFF). It was 22 bits (4 MB):
// a ROM of exactly 4 MB wrapped the size to 0 (every ROM read returned 0, the game could not
// boot), and a larger one (SSF2, 5 MB) overwrote its own start.
reg [22:0] loader_addr, loader_addr_next;       // byte address, rom size after load complete

// Cartridge header snoop -----------------------------------------------------------------
// MiSTer Genesis (Genesis.sv) reads the serial number at 0x183-0x18A while the ROM
// downloads and switches on per-game quirks. Same table here, fed from our UART loader:
// the byte being written is at loader_addr_next when loader_do_valid pulses.
reg sram_quirk = 0, sram00_quirk = 0, eeprom_quirk = 0, fifo_quirk = 0, noram_quirk = 0;
reg fmbusy_quirk = 0, schan_quirk = 0;
reg [63:0] cart_id;
reg [2:0]  hdr_loading_r;
always @(posedge clk_sys) begin
    hdr_loading_r <= loading;
    if (loading && !hdr_loading_r)
        {fifo_quirk,eeprom_quirk,sram_quirk,sram00_quirk,noram_quirk,fmbusy_quirk,schan_quirk} <= 0;
    if (loader_do_valid) begin
        if (loader_addr_next >= 23'h183 && loader_addr_next <= 23'h18A)
            cart_id <= {cart_id[55:0], loader_do};
        if (loader_addr_next == 23'h18C) begin
                 if(cart_id == "T-081276") sram_quirk   <= 1; // NFL Quarterback Club
            else if(cart_id == "T-81406 ") sram_quirk   <= 1; // NBA Jam TE
            else if(cart_id == "T-081586") sram_quirk   <= 1; // NFL Quarterback Club '96
            else if(cart_id == "T-81576 ") sram_quirk   <= 1; // College Slam
            else if(cart_id == "T-81476 ") sram_quirk   <= 1; // Frank Thomas Big Hurt Baseball
            else if(cart_id == "MK-1215 ") eeprom_quirk <= 1; // Evander Real Deal Holyfield's Boxing
            else if(cart_id == "G-4060  ") eeprom_quirk <= 1; // Wonder Boy
            else if(cart_id == "00001211") eeprom_quirk <= 1; // Sports Talk Baseball
            else if(cart_id == "MK-1228 ") eeprom_quirk <= 1; // Greatest Heavyweights
            else if(cart_id == "G-5538  ") eeprom_quirk <= 1; // Greatest Heavyweights JP
            else if(cart_id == "00004076") eeprom_quirk <= 1; // Honoo no Toukyuuji Dodge Danpei
            else if(cart_id == "T-12046 ") eeprom_quirk <= 1; // Mega Man - The Wily Wars
            else if(cart_id == "T-12053 ") eeprom_quirk <= 1; // Rockman Mega World
            else if(cart_id == "G-4524  ") eeprom_quirk <= 1; // Ninja Burai Densetsu
            else if(cart_id == "T-113016") noram_quirk  <= 1; // Puggsy fake ram check
            else if(cart_id == "T-89016 ") fifo_quirk   <= 1; // Clue
            else if(cart_id == "T-35036 ") fmbusy_quirk <= 1; // Hellfire US
            else if(cart_id == "T-25073 ") fmbusy_quirk <= 1; // Hellfire JP
            else if(cart_id == "MK-1137-") fmbusy_quirk <= 1; // Hellfire EU
            else if(cart_id == "T-68???-") schan_quirk  <= 1; // Game no Kanzume Otokuyou
            else if(cart_id == " GM 0000") sram00_quirk <= 1; // Sonic 1 Remastered
            // Not wired: Pier Solar (T-574023/T-574013) and Virtua Racing (MK-1229/G-7001)
            // -- their EEPROM_STM95 / SVP blocks are commented out of system.sv.
        end
    end
end

// Region from the header, MiSTer Genesis's "auto" priority US > EU > JP (default US).
// 0x1F0 holds a letter or the new-style hex region code; 0x1F1/0x1F2 hold letters.
// Exact-lock builds only have an NTSC (262-line) raster, so an EU game gets NTSC export
// timing there (PAL would need the 855x626 raster -- separate project).
reg hdr_j = 0, hdr_u = 0, hdr_e = 0;
reg six_btn = 0;             // header I/O field (0x190-0x19F) lists '6' = 6-button pad
wire [3:0] hrgn = loader_do[3:0] - 4'd7;
always @(posedge clk_sys) begin
    if (loading && !hdr_loading_r) {hdr_j, hdr_u, hdr_e, six_btn} <= 0;
    if (loader_do_valid) begin
        if (loader_addr_next == 23'h1F0) begin
            if (loader_do == "J") hdr_j <= 1;
            else if (loader_do == "U") hdr_u <= 1;
            else if (loader_do == "E") hdr_e <= 1;
            else if (loader_do >= "0" && loader_do <= "9") {hdr_e, hdr_u, hdr_j} <= {loader_do[3], loader_do[2], loader_do[0]};
            else if (loader_do >= "A" && loader_do <= "F") {hdr_e, hdr_u, hdr_j} <= {hrgn[3], hrgn[2], hrgn[0]};
        end
        if (loader_addr_next == 23'h1F1 || loader_addr_next == 23'h1F2) begin
            if (loader_do == "J") hdr_j <= 1;
            else if (loader_do == "U") hdr_u <= 1;
            else if (loader_do == "E") hdr_e <= 1;
        end
        if (loader_addr_next >= 23'h190 && loader_addr_next <= 23'h19F && loader_do == "6")
            six_btn <= 1;
    end
end
wire region_us = hdr_u || !(hdr_e || hdr_j);      // US first, and the default
wire region_eu = !hdr_u && hdr_e;
wire md_export = region_us || region_eu;          // JP only when the cart is JP-only
`ifdef EXACT_LOCK
wire md_pal = 1'b0;
`else
wire md_pal = region_eu;
`endif

// MegaDrive system -------------------------------------------------------------------
`ifdef ZRAM_SDRAM
wire [24:1] zram_mem_addr;
wire [15:0] zram_mem_data, zram_mem_wdata;
wire        zram_mem_we, zram_mem_req, zram_mem_ack;
wire  [1:0] zram_mem_be;
`endif

system megadrive (
    .MCLK(clk_sys), .CLK_Z80(clk_z80), .RESET_N(md_on),
    .LPF_MODE(2'b00), .ENABLE_FM('1), .ENABLE_PSG('1), .DAC_LDATA(audio_left), .DAC_RDATA(audio_right),
    .LOADING(loading != 0), .PAL(md_pal), .EXPORT(md_export), .FAST_FIFO(fifo_quirk), .SRAM_QUIRK(sram_quirk), .SRAM00_QUIRK(sram00_quirk),
    .EEPROM_QUIRK(eeprom_quirk), .NORAM_QUIRK(noram_quirk), .PIER_QUIRK('0), .SVP_QUIRK('0),
    .FMBUSY_QUIRK(fmbusy_quirk), .SCHAN_QUIRK(schan_quirk), .TURBO('0), 
    .GG_RESET('0), .GG_EN('0), .GG_CODE('0), .GG_AVAILABLE(),
    .BRAM_A(), .BRAM_DI(), .BRAM_DO(), .BRAM_WE(), .BRAM_CHANGE(),
    .RED(red), .GREEN(green), .BLUE(blue), .VS(), .HS(hsync), .HBL(hblank), .VBL(vblank), .CE_PIX(ce_pix), 
    .BORDER('0), .CRAM_DOTS('0), .INTERLACE(), .FIELD(), .RESOLUTION(resolution),
    .J3BUT(~six_btn), .JOY_1(joy1), .JOY_2(joy2), .JOY_3(), .JOY_4(), .JOY_5(), .MULTITAP('0),
    .MOUSE('0), .MOUSE_OPT('0), .GUN_OPT('0), .GUN_TYPE('0), .GUN_SENSOR('0), .GUN_A('0),
    .GUN_B('0), .GUN_C('0), .GUN_START('0),
    .SERJOYSTICK_IN('0), .SERJOYSTICK_OUT(), .SER_OPT('0),
    .MEM_ADDR(mem_addr), .MEM_DATA(mem_data), .MEM_WDATA(mem_wdata), .MEM_WE(mem_we), .MEM_BE(mem_be),
    .MEM_REQ(mem_req), .MEM_ACK(mem_ack), .ROMSZ(loader_addr[22:1]),
`ifdef ZRAM_SDRAM
    .ZRAM_MEM_ADDR(zram_mem_addr), .ZRAM_MEM_DATA(zram_mem_data), .ZRAM_MEM_WDATA(zram_mem_wdata),
    .ZRAM_MEM_WE(zram_mem_we), .ZRAM_MEM_BE(zram_mem_be),
    .ZRAM_MEM_REQ(zram_mem_req), .ZRAM_MEM_ACK(zram_mem_ack),
`endif
    .EN_HIFI_PCM('0), .LADDER(1'b1), .OBJ_LIMIT_HIGH('0), .TRANSP_DETECT(),
    .PAUSE_EN(pause_core), .BGA_EN('1), .BGB_EN('1), .SPR_EN('1), .DBG_M68K_A(), .DBG_VBUS_A()
);


reg [2:0] loading_r;
reg loader_req;
wire sdram_busy;
always @(posedge clk_sys) begin
    if (loader_do_valid) begin
        loader_req <= ~loader_req;
        loader_addr <= loader_addr_next;
        loader_addr_next <= loader_addr_next + 1;
    end
    loading_r <= loading;
    if (loading  && !loading_r) begin           // start loading, turn megadrive off
        loader_addr_next <= 0;
        md_on <= 0;
    end else if (!loading && loading_r) begin   // loading finished, turn megadrive on
        loader_addr <= loader_addr_next;        // this is the proper ROMSZ
        md_on <= 1;
    end
end

`ifdef VERILATOR

sdram_sim u_sdram (
    .clk(clk_sys), .resetn(1'b1), .busy(sdram_busy),
    .addr0(mem_addr), .req0(mem_req), .ack0(mem_ack), .wr0(mem_we), .be0(mem_be),
	.din0(mem_wdata), .dout0(mem_data),
    .addr1(loader_addr[22:1]), .req1(loader_req), .ack1(), .wr1('1), .be1(loader_addr[0] ? 2'b01 : 2'b10),    // big-endian
	.din1({2{loader_do}}), .dout1(), 
    .addr2(), .req2(), .ack2(), .wr2(), .be2(),
	.din2('0), .dout2()
);

`else

// iosys RV memory interface
wire        rv_valid        /* xsynthesis syn_keep=1 */;
wire        rv_ready        /* xsynthesis syn_keep=1 */;
wire [22:0] rv_addr         /* xsynthesis syn_keep=1 */;
wire [31:0] rv_wdata        /* xsynthesis syn_keep=1 */;
wire [3:0]  rv_wstrb        /* xsynthesis syn_keep=1 */;
wire [31:0] rv_rdata        /* xsynthesis syn_keep=1 */;

// sdram-side interface
wire [22:1] rv_mem_addr     /* xsynthesis syn_keep=1 */;    // 8MB space for RV in bank 1
wire [15:0] rv_mem_din      /* xsynthesis syn_keep=1 */;
wire [1:0]  rv_mem_ds       /* xsynthesis syn_keep=1 */;
wire [15:0] rv_mem_dout     /* xsynthesis syn_keep=1 */;
wire        rv_mem_req      /* xsynthesis syn_keep=1 */;
wire        rv_mem_ack      /* xsynthesis syn_keep=1 */;
wire        rv_mem_we       /* xsynthesis syn_keep=1 */;

// SDRAM layout: total 32MB
// 0000000 - 07FFFFF: cartridge ROM (max Genesis game is 5MB, Super Street Fighter II: The New Challengers)
// 0800000 - 080FFFF: 68K RAM       (64KB)
// 0820000 - 083FFFF: SRAM          (128KB)
// 1000000 - 10FFFFF: Risc-V memory (1MB)
sdram #(.FREQ(FREQ)) u_sdram (
    .clk(clk_sys), .resetn(1'b1), .refresh_allowed(1'b1), .busy(sdram_busy),
    .addr0(mem_addr), .req0(mem_req), .ack0(mem_ack), .wr0(mem_we), .be0(mem_be),
	.din0(mem_wdata), .dout0(mem_data),

    .addr1(loader_addr[22:1]), .req1(loader_req), .ack1(), .wr1('1), .be1(loader_addr[0] ? 2'b01 : 2'b10),    // big-endian
	.din1({2{loader_do}}), .dout1(), 

`ifdef ZRAM_SDRAM
    // Channel 2 is the RISC-V's in the picorv32 build; with the BL616 companion it is
    // unused, so the Z80's 8 KB goes here instead of costing 4 BSRAM blocks. See the
    // ramZ80 comment in system.sv -- it is shared with the 68000 through the Z80 bus
    // window, and the ZBUS state machine already serialises the two.
    .addr2(zram_mem_addr), .req2(zram_mem_req), .ack2(zram_mem_ack), .wr2(zram_mem_we), .be2(zram_mem_be),
	.din2(zram_mem_wdata), .dout2(zram_mem_data),
`else
    .addr2({2'b10, rv_mem_addr}), .req2(rv_mem_req), .ack2(rv_mem_ack), .wr2(rv_mem_we), .be2(rv_mem_ds),
	.din2(rv_mem_din), .dout2(rv_mem_dout),
`endif

    .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba),      
    .SDRAM_nCS(O_sdram_cs_n), .SDRAM_nWE(O_sdram_wen_n),  .SDRAM_nRAS(O_sdram_ras_n), 
    .SDRAM_nCAS(O_sdram_cas_n), .SDRAM_CKE(O_sdram_cke), .SDRAM_DQM(O_sdram_dqm)
);

// iosys for menu, rom loading and other functions -----------------------------------------
wire iosys_loaded;
wire overlay;
wire [7:0] overlay_x;
wire [7:0] overlay_y;
wire [14:0] overlay_color;

iosys_bl616 #(.CORE_ID(4), .FREQ(FREQ), .COLOR_LOGO(15'b00000_00100_11111)) iosys (
    .clk(clk_sys), .hclk(hclk), .resetn(~reset),
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y), .overlay_color(overlay_color),
    .joy1(joy_btns | joy_usb1), .joy2(joy2_btns | joy_usb2), .hid1(hid1), .hid2(hid2),
    .rom_loading(loading), .rom_do(loader_do), .rom_do_valid(loader_do_valid), 
    .uart_tx(UART_TXD), .uart_rx(UART_RXD)
);

// Gamepads ------------------------------------------------------------------------------
dualshock_controller #(.FREQ(FREQ)) ds (
    .clk(clk_sys), .I_RSTn(1'b1), 
    .O_psCLK(ds_clk), .O_psSEL(ds_cs), .O_psTXD(ds_mosi), .I_psRXD(ds_miso),
    .O_RXD_1(), .O_RXD_2(), .O_RXD_3(), .O_RXD_4(), .O_RXD_5(), .O_RXD_6(),
    .snes_btns(joy_btns)
);

dualshock_controller #(.FREQ(FREQ)) ds2 (
    .clk(clk_sys), .I_RSTn(1'b1), 
    .O_psCLK(ds2_clk), .O_psSEL(ds2_cs), .O_psTXD(ds2_mosi), .I_psRXD(ds2_miso),
    .O_RXD_1(), .O_RXD_2(), .O_RXD_3(), .O_RXD_4(), .O_RXD_5(), .O_RXD_6(),
    .snes_btns(joy2_btns)
);

`ifdef USB1
wire clk12;
wire pll_lock_12;
wire usb_conerr;
wire [1:0] usb_type;
pll_12 pll12(.clkin(clk50), .clkout0(clk12), .lock(pll_lock_12));
usb_hid_host usb_hid_host (
    .usbclk(clk12), .usbrst_n(pll_lock_12),
    .usb_dm(usb1_dn), .usb_dp(usb1_dp),
    .game_snes(joy_usb1), .typ(usb_type), .conerr(usb_conerr)
);
`ifdef PRIMER25K
assign led = ~{usb_type[0], usb_conerr};
`else
assign led = ~{joy_usb1[4:0], usb_type, usb_conerr};
`endif
`else
assign joy_usb1 = 12'b0;
`ifdef PRIMER25K
assign led = 2'b11;                 // no USB host on this board: both LEDs off (active low)
`endif
`endif

`ifdef USB2
usb_hid_host usb_hid_host2 (
    .usbclk(clk12), .usbrst_n(pll_lock_12),
    .usb_dm(usb2_dn), .usb_dp(usb2_dp),
    .game_snes(joy_usb2)
);
`else
assign joy_usb2 = 12'b0;
`endif

// HDMI output ---------------------------------------------------------------------------
reg ce_pix_r, hblank_r;
reg [8:0] x;
reg [7:0] y;

// there are 15 dummy pixels after VBLANK before the first HBLANK
reg hsync_seen;
always @(posedge clk_sys) begin
    ce_pix_r <= ce_pix;

    // maintain y position
    if (vblank) begin
        y <= 0;
        hsync_seen <= 0;
    end
    if (hsync)
        hsync_seen <= 1;

    hblank_r <= hblank;
    if (hsync_seen) begin           // start frame after first hsync
        if (ce_pix & ~ce_pix_r & ~hblank & ~vblank)
            x <= x + 1;
        if (hblank) begin
            x <= 0;
            if (!hblank_r)
                y <= y + 1;
        end
    end
end

`ifdef EXACT_LOCK
framebuffer_exact #(
    .WIDTH(320), .HEIGHT(240), .COLOR_BITS(4)
) fb (
    .clk(clk_sys), .resetn(~reset), .clk_pixel(hclk), .clk_5x_pixel(hclk5),
    .ce_pix(ce_pix & hsync_seen), .r(red), .g(green), .b(blue), .x(x), .y(y),
    .width(resolution[0] ? 320 : 256), .height(resolution[1] ? 240 : 224), .vblank(vblank),
    .audio_left(audio_left), .audio_right(audio_right),
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y), .overlay_color(overlay_color),
    .pause_core(pause_core),
    .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
    .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p)
);
`else
framebuffer #(
    .WIDTH(320), .HEIGHT(240), .COLOR_BITS(4)
) fb (
    .clk(clk_sys), .resetn(~reset), .clk_pixel(hclk), .clk_5x_pixel(hclk5),
    .ce_pix(ce_pix & hsync_seen), .r(red), .g(green), .b(blue), .x(x), .y(y), 
    .width(resolution[0] ? 320 : 256), .height(resolution[1] ? 240 : 224),      // resolution: 0: 256x224, 1: 320x224, 2: 256x240, 3: 320x240
    .audio_left(audio_left), .audio_right(audio_right),
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y), .overlay_color(overlay_color),
    .pause_core(pause_core),
    
    .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
    .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p)
);
`endif

// assign led = ~{2'b0, vblank, md_on, loading != 0, overlay, iosys_loaded, ~reset};

`endif

// snes layout: R L X A RT LT DN UP START SELECT Y B, high active
// md layout:   Z,Y,X,Mode,Start,C,B,A,Up,Down,Left,Right
function [11:0] btn_snes2md([11:0] snes);
    reg [11:0] md;
    md[0] = snes[7];    // Right
    md[1] = snes[6];    // Left
    md[2] = snes[5];    // Down
    md[3] = snes[4];    // Up
    md[4] = snes[1];    // A
    md[5] = snes[0];    // B
    md[6] = snes[8];    // C
    md[7] = snes[3];    // Start
    md[8] = snes[2];    // Mode = Select
    md[9] = snes[10];   // X = L
    md[10] = snes[9];   // Y = X
    md[11] = snes[11];  // Z = R
    return md;
endfunction

endmodule
