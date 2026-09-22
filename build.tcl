if {$argc == 0} {
    puts "Usage: $argv0 <device>"
    puts "          device: mega60k mega138k mega138kpro console60k console138k"
    puts "Currently supports ds2 and usb controller"
    exit 1
}

set dev [lindex $argv 0]

# EXACT LOCK (2026-09-22): console60k with the video clocks taken off the core's own VCO.
# Removes the 32-line buffer AND the once-per-frame core pause. See src/plla/pll_exact.v,
# src/framebuffer_exact.sv, hdmi mode 201.
set exact 0
if {$dev eq "console60k_exact"} {
    set exact 1
    set dev "console60k"
}
if {$dev eq "primer25k_exact"} {
    set exact 1
    set dev "primer25k"
}

if {$dev eq "mega60k"} {
    set_device GW5AT-LV60PG484AC1/I0 -device_version B
    add_file -type cst "src/boards/mega.cst"
    add_file -type verilog "src/plla/pll.v"
    add_file -type verilog "src/plla/pll_27.v"
    add_file -type verilog "src/plla/pll_74.v"
} elseif {$dev eq "console60k"} {
    set_device GW5AT-LV60PG484AC1/I0 -device_version B
    add_file -type verilog "src/boards/console.v"
    add_file -type cst "src/boards/console.cst"
    if {$exact} {
        add_file -type verilog "src/config_exact.v"
        add_file -type verilog "src/plla/pll_exact.v"
    } else {
        add_file -type verilog "src/plla/pll.v"
        add_file -type verilog "src/plla/pll_27.v"
        add_file -type verilog "src/plla/pll_74.v"
    }
    
    add_file -type verilog "src/usb_hid_host.v"
    add_file -type verilog "src/plla/pll_12.v"
} elseif {$dev eq "primer25k"} {
    # Primer 25K (GW5A-25A). EXACT LOCK ONLY: the stock video path needs 82 BSRAM blocks
    # and this device has 56. Same family and the same 50 MHz crystal as Console 60K, so
    # the exact-lock PLL is reused unchanged; only pins and the I/O guards differ.
    if {!$exact} { error "primer25k has 56 BSRAM; the stock video path needs 82. Use primer25k_exact." }
    set_device GW5A-LV25MG121NC1/I0 -device_version A
    add_file -type verilog "src/boards/primer25k.v"
    add_file -type cst "src/boards/primer25k.cst"
    add_file -type verilog "src/config_exact.v"
    add_file -type verilog "src/plla/pll_exact.v"
    # 68 regular I/O is not enough on its own, so free the dual-purpose pins as GPIO --
    # the same set pcetang uses on this board.
    set_option -use_mspi_as_gpio 1
    set_option -use_sspi_as_gpio 1
    set_option -use_done_as_gpio 1
    set_option -use_cpu_as_gpio 1
    set_option -use_ready_as_gpio 1
    set_option -use_i2c_as_gpio 1
    set_option -use_jtag_as_gpio 1
    # THE LAST BLOCK. Place-and-route's -convert_sdp32_36_to_sdp16_18 (Gowin option PNR30,
    # on by default in rtlplacerouteoptions5at.xml) splits every 36-bit-wide simple
    # dual-port BSRAM into two 18-bit ones. This design has exactly one: the VDP's
    # sprite-info table (64 x 35, vdp.v obj_spinfo). Synthesis counts it as 1 block, the
    # placer as 2, so 56 became 57 against this device's 56. Turning the conversion off
    # keeps it at one block.
    #
    # RISK, unresolved: Gowin defaults this on and does not document why -- it may be a
    # workaround for 36-bit SDP behaviour on this silicon. Nothing here proves otherwise;
    # the build fits and closes timing, and that is all it proves. Watch the sprites.
    #
    # Rejected alternative: moving that table into LUT RAM. Gowin ignored the attribute on
    # an inline 64 x 35 array and inferred it worse (58 blocks).
    set_option -convert_sdp32_36_to_sdp16_18 0
} elseif {$dev eq "console138k"} {
    set_device GW5AST-LV138PG484AC1/I0 -device_version B
    add_file -type verilog "src/boards/console.v"
    add_file -type cst "src/boards/console.cst"
    add_file -type verilog "src/pll/pll.v"
    add_file -type verilog "src/pll/pll_27.v"
    add_file -type verilog "src/pll/pll_74.v"    
    add_file -type verilog "src/usb_hid_host.v"
    add_file -type verilog "src/pll/pll_12.v"
} elseif {$dev eq "mega138k"} {
    set_device GW5AT-LV138PG484AC1/I0 -device_version B
    add_file -type cst "src/boards/mega.cst"
    add_file -type verilog "src/pll/pll.v"
    add_file -type verilog "src/pll/pll_27.v"
    add_file -type verilog "src/pll/pll_74.v"
} elseif {$dev eq "mega138kpro"} {
    set_device GW5AST-LV138FPG676AC1/I0 -device_version B
    add_file -type cst "src/boards/mega138kpro.cst"
    add_file -type verilog "src/pll/pll.v"
    add_file -type verilog "src/pll/pll_27.v"
    add_file -type verilog "src/pll/pll_74.v"
} else {
    error "Unknown device $dev"
}
if {$exact} {
    add_file -type sdc "src/mdtang_exact.sdc"
} else {
    add_file -type sdc "src/mdtang.sdc"
}
if {$exact} {
    set_option -output_base_name mdtang_${dev}_exact
} else {
    set_option -output_base_name mdtang_${dev}
}

add_file -type verilog "src/iosys/iosys_bl616.v"
add_file -type verilog "src/iosys/uart_fixed.v"

add_file -type verilog "src/iosys/textdisp.v"
add_file -type verilog "src/iosys/gowin_dpb_menu.v"
add_file -type verilog "src/iosys/dualshock_controller.v"

add_file -type verilog "src/common/dpram.v"
add_file -type verilog "src/common/dpram32_block.v"
add_file -type verilog "src/common/dpram_block.v"
add_file -type verilog "src/fx68k/fx68k.sv"
add_file -type verilog "src/fx68k/fx68kAlu.sv"
add_file -type verilog "src/fx68k/uaddrPla.sv"
add_file -type verilog "src/hdmi/audio_clock_regeneration_packet.sv"
add_file -type verilog "src/hdmi/audio_info_frame.sv"
add_file -type verilog "src/hdmi/audio_sample_packet.sv"
add_file -type verilog "src/hdmi/auxiliary_video_information_info_frame.sv"
add_file -type verilog "src/hdmi/hdmi.sv"
add_file -type verilog "src/hdmi/packet_assembler.sv"
add_file -type verilog "src/hdmi/packet_picker.sv"
add_file -type verilog "src/hdmi/serializer.sv"
add_file -type verilog "src/hdmi/source_product_description_info_frame.sv"
add_file -type verilog "src/hdmi/tmds_channel.sv"
if {$exact} {
    add_file -type verilog "src/framebuffer_exact.sv"
} else {
    add_file -type verilog "src/framebuffer_sync.sv"
}
add_file -type verilog "src/jt12/adpcm/jt10_adpcm_div.v"
add_file -type verilog "src/jt12/jt12.v"
add_file -type verilog "src/jt12/jt12_acc.v"
add_file -type verilog "src/jt12/jt12_csr.v"
add_file -type verilog "src/jt12/jt12_div.v"
add_file -type verilog "src/jt12/jt12_dout.v"
add_file -type verilog "src/jt12/jt12_eg.v"
add_file -type verilog "src/jt12/jt12_eg_cnt.v"
add_file -type verilog "src/jt12/jt12_eg_comb.v"
add_file -type verilog "src/jt12/jt12_eg_ctrl.v"
add_file -type verilog "src/jt12/jt12_eg_final.v"
add_file -type verilog "src/jt12/jt12_eg_pure.v"
add_file -type verilog "src/jt12/jt12_eg_step.v"
add_file -type verilog "src/jt12/jt12_exprom.v"
add_file -type verilog "src/jt12/jt12_kon.v"
add_file -type verilog "src/jt12/jt12_lfo.v"
add_file -type verilog "src/jt12/jt12_logsin.v"
add_file -type verilog "src/jt12/jt12_mmr.v"
add_file -type verilog "src/jt12/jt12_mod.v"
add_file -type verilog "src/jt12/jt12_op.v"
add_file -type verilog "src/jt12/jt12_pcm_interpol.v"
add_file -type verilog "src/jt12/jt12_pg.v"
add_file -type verilog "src/jt12/jt12_pg_comb.v"
add_file -type verilog "src/jt12/jt12_pg_dt.v"
add_file -type verilog "src/jt12/jt12_pg_inc.v"
add_file -type verilog "src/jt12/jt12_pg_sum.v"
add_file -type verilog "src/jt12/jt12_pm.v"
add_file -type verilog "src/jt12/jt12_reg.v"
add_file -type verilog "src/jt12/jt12_rst.v"
add_file -type verilog "src/jt12/jt12_sh.v"
add_file -type verilog "src/jt12/jt12_sh24.v"
add_file -type verilog "src/jt12/jt12_sh_rst.v"
add_file -type verilog "src/jt12/jt12_single_acc.v"
add_file -type verilog "src/jt12/jt12_sumch.v"
add_file -type verilog "src/jt12/jt12_timers.v"
add_file -type verilog "src/jt12/jt12_top.v"
add_file -type verilog "src/jt12/mixer/jt12_comb.v"
add_file -type verilog "src/jt12/mixer/jt12_decim.v"
add_file -type verilog "src/jt12/mixer/jt12_fm_uprate.v"
add_file -type verilog "src/jt12/mixer/jt12_genmix.v"
add_file -type verilog "src/jt12/mixer/jt12_interpol.v"
add_file -type verilog "src/jt89/jt89.v"
add_file -type verilog "src/jt89/jt89_mixer.v"
add_file -type verilog "src/jt89/jt89_noise.v"
add_file -type verilog "src/jt89/jt89_tone.v"
add_file -type verilog "src/jt89/jt89_vol.v"
add_file -type verilog "src/mdtang_top.sv"
add_file -type verilog "src/memory/rv_sdram_adapter.v"
add_file -type verilog "src/memory/sdram.v"
add_file -type verilog "src/peripherals/audio_iir_filter.v"
add_file -type verilog "src/peripherals/fourway.v"
add_file -type verilog "src/peripherals/gen_io.sv"
add_file -type verilog "src/peripherals/genesis_lpf.v"
add_file -type verilog "src/peripherals/lightgun.sv"
add_file -type verilog "src/peripherals/multitap.sv"
add_file -type verilog "src/peripherals/teamplayer.sv"
add_file -type verilog "src/system.sv"
add_file -type verilog "src/t80/t80.v"
add_file -type verilog "src/t80/t80_alu.v"
add_file -type verilog "src/t80/t80_mcode.v"
add_file -type verilog "src/t80/t80_reg.v"
add_file -type verilog "src/t80/t80s.v"
add_file -type verilog "src/vdp/vdp.v"
add_file -type verilog "src/vdp/vdp_common.v"
add_file -type verilog "src/vdp/vram.v"

set_option -synthesis_tool gowinsynthesis
set_option -top_module mdtang_top
set_option -include_path {"src/common"}
set_option -verilog_std sysv2017
set_option -vhdl_std vhd2008
set_option -ireg_in_iob 1
set_option -oreg_in_iob 1
set_option -ioreg_in_iob 1
set_option -use_sspi_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -use_cpu_as_gpio 1

# use the slower but timing-optimized place algorithm
if {$exact} {
    # PLACEMENT, not structure, decided whether the two clk_sys -> clk_z80 control paths
    # (Z80 bus request and reset, crossed with a single flop in system.sv) met hold: with
    # place_option 2 they missed by 14 and 26 ps, with 1 or 3 they pass outright. Option 1
    # also leaves the most core-clock margin (+8.7% vs +0.8% for option 3).
    # `set_option -correct_hold_violation 1` did NOT fix them, and neither did phase-
    # shifting the Z80 clock output.
    set_option -place_option 1
} else {
    set_option -place_option 2
}

run all
