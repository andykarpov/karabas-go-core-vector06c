#!/usr/bin/env python3
"""Makes rtl/karabas_mini_top.v and rtl/karabas_go_top.v from rtl/karabas_minig_top.v, and
karabas_mini.ucf / karabas_go.ucf from the pin parts tools/pins_<board>.ucf (those of core-specialist)
and the timing part of karabas_minig.ucf (the shape of core-criss tools/mktops.py). The port lists
are tools/ports_<board>.v (core-specialist).

The three tops share everything but the board: change the Mini G top, then run this (every
replacement must match once, else it stops).

Mini (before rev.G): MCU_SCK not on a clock pin (no BUFG), 4 MCU_IO, sigma-delta audio on
  AUDIO_L / AUDIO_R instead of the PCM5102, FT_RESET, the ESP pins (the module runs: not driven).
Go: VGA 8:8:8 with V_CLK = the INVERTED pixel clock (the DAC latches on its rising edge, mid-pixel:
  notes go-vclk-phase) instead of HDMI, the FT812 off the video bus (FT_OE_N = 1), the MCU link on
  MCU_SPI_*, DAC_LRCK / DAC_MUTE, the floppy connector unused (its outputs 0: the board inverts
  them), no FT_CLK_OUT, no ADC.
Both: the SAM2695 synth is not used (reset off, no clock: as core-specialist). GPL-3 (LICENSE).
"""
import os
import sys

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RTL = os.path.join(SRC, "rtl")
TOOLS = os.path.join(SRC, "tools")


def sub(s, old, new, what):
    if s.count(old) != 1:
        sys.exit("mktops.py: %s: %d matches of %r" % (what, s.count(old), old[:70]))
    return s.replace(old, new)


def cut(s, a_mark, b_mark, new, what):
    if s.count(a_mark) != 1 or s.count(b_mark) != 1:
        sys.exit("mktops.py: %s: marks %r / %r" % (what, a_mark[:40], b_mark[:40]))
    a = s.index(a_mark)
    b = s.index(b_mark, a)
    return s[:a] + new + s[b:]


def ports(s, board):
    body = open(os.path.join(TOOLS, "ports_%s.v" % board)).read()
    a = s.index("module karabas_minig_top (")
    b = s.index("\n);\n", a) + 4
    return s[:a] + body.rstrip("\n") + "\n" + s[b:]


HEADER_G = " Vector-06C core for Karabas Mini rev.G (HDMI, PCM5102). The board glue of core-specialist.\n"

MCU_SCK_G = """// MCU_SCK on a global buffer; the FT812 and SD2 get the IBUFG output (a BUFG drives no pad)
wire mcu_sck_ibufg, mcu_sck;
IBUFG ibufg_mcu_sck (.I(MCU_SCK), .O(mcu_sck_ibufg));
BUFG bufg_mcu_sck (.I(mcu_sck_ibufg), .O(mcu_sck));
"""
MCU_SCK_OLD = """// MCU_SCK is not on a clock pin on this board (CLOCK_DEDICATED_ROUTE = FALSE in the ucf)
wire mcu_sck = MCU_SCK, mcu_sck_ibufg = MCU_SCK;
"""

PCM = """kg_pcm5102 #(.DIV_BITS(2)) dac (
	.clk(clk_sys),
	.reset(areset),
	.left(audio_l),
	.right(audio_r),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_WS)
);
"""


def mini(s):
    s = sub(s, HEADER_G, " Vector-06C core for Karabas Mini before rev.G (HDMI, sigma-delta audio). Made by tools/mktops.py\n"
            " from karabas_minig_top.v (do not edit: change that one and run it): the same except the pins,\n"
            " the MCU link (MCU_SCK not on a clock pin), the audio (AUDIO_L / AUDIO_R).\n", "header")
    s = ports(s, "mini")
    s = sub(s, "assign ESP32_SPI_CS_N = 1'b1;\n",
            "assign ESP_RESET_N = 1'bz;\nassign ESP_BOOT_N = 1'bz;\nassign FT_RESET = 1'b1;\n"
            "assign MIDI_CLK = 1'b1;\nassign MIDI_RESET_N = 1'b1;\n", "ESP")
    s = sub(s, MCU_SCK_G, MCU_SCK_OLD, "MCU_SCK")
    s = sub(s, "assign MCU_IO[5:2] = 4'bzzzz;\n", "assign MCU_IO[3:2] = 2'bzz;\n", "MCU_IO")
    s = sub(s, PCM, "// no I2S DAC on this board: sigma-delta outputs into an RC filter (offset binary)\n"
            "kg_sigma_delta_dac dac_l (.clk(clk_sys), .reset(areset), .din(audio_l ^ 16'h8000), .dout(AUDIO_L));\n"
            "kg_sigma_delta_dac dac_r (.clk(clk_sys), .reset(areset), .din(audio_r ^ 16'h8000), .dout(AUDIO_R));\n", "DAC")
    return s


def go(s):
    s = sub(s, HEADER_G, " Vector-06C core for Karabas Go (VGA, PCM5102). Made by tools/mktops.py from karabas_minig_top.v\n"
            " (do not edit: change that one and run it): the same except the pins, the MCU link (MCU_SCK not\n"
            " on a clock pin) and the video: 24 bit RGB to the VGA DAC, V_CLK the inverted pixel clock, the\n"
            " FT812 off that bus (FT_OE_N = 1), no HDMI. The floppy connector is not used.\n", "header")
    s = ports(s, "go")
    s = sub(s, "assign ESP32_SPI_CS_N = 1'b1;\n",
            "assign ESP_RESET_N = 1'bz;\nassign ESP_BOOT_N = 1'bz;\n"
            "assign MIDI_CLK = 1'b1;\nassign MIDI_RESET_N = 1'b1;\n"
            "assign FT_OE_N = 1'b1;     // the FT812 does not drive the video DAC\n"
            "assign BEEPER = 1'b0;\n"
            "assign DAC_MUTE = 1'b1;    // soft mute of the PCM5102: 1 = sound on\n\n"
            "// the floppy connector is not used: its outputs 0 (the board inverts them: high = active)\n"
            "assign FDC_DRIVE = 2'b00;\nassign FDC_MOTOR = 1'b0;\nassign FDC_DIR = 1'b0;\nassign FDC_STEP = 1'b0;\n"
            "assign FDC_WDATA = 1'b0;\nassign FDC_WGATE = 1'b0;\nassign FDC_SIDE_N = 1'b0;\n", "ESP / unused Go")
    s = sub(s, "assign ADC_CLK = 1'b0;\nassign ADC_BCK = 1'bz;\nassign ADC_LRCK = 1'bz;\n", "", "ADC")
    s = sub(s, "ODDR2 oddr_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8), .C1(~clk_8), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));\n",
            "// the pixel clock of the VGA DAC, inverted: the DAC latches on the rising V_CLK, mid-pixel (no FT_CLK_OUT\n"
            "// on Go: the FT812 has its crystal)\n"
            "ODDR2 oddr_v_clk (.Q(V_CLK), .C0(clk_pix), .C1(~clk_pix), .CE(1'b1), .D0(1'b0), .D1(1'b1), .R(1'b0), .S(1'b0));\n",
            "V_CLK")
    s = sub(s, MCU_SCK_G, MCU_SCK_OLD, "MCU_SCK")
    s = sub(s, "assign MCU_IO[1] = mcu_int;\nassign MCU_IO[0] = 1'bz;\nassign MCU_IO[5:2] = 4'bzzzz;\n",
            "assign MCU_SPI_IO[0] = mcu_int;   // INT of link v2 on N9 (IO1 of the firmware)\nassign MCU_SPI_IO[1] = 1'bz;\n", "MCU_IO")
    s = sub(s, "	.MCU_SPI_FT_SS(MCU_IO[3]),\n	.MCU_SPI_SD2_SS(MCU_IO[2]),\n",
            "	.MCU_SPI_FT_SS(MCU_SPI_FT_CS_N),\n	.MCU_SPI_SD2_SS(MCU_SPI_SD2_CS_N),\n", "MCU SS")
    s = sub(s, "	.lrck(DAC_WS)\n", "	.lrck(DAC_LRCK)\n", "DAC_LRCK")
    s = cut(s, "// the HDMI audio:", "endmodule",
            """// ------------------------------------------------------------------ VGA

// the 576p of v06c_scan2x (negative syncs already), black outside de (the DAC has no blank input);
// registered on clk_pix (IOB flip-flops)
reg vga_hs = 1'b1, vga_vs = 1'b1;
reg [23:0] vga_rgb = 24'd0;
always @(posedge clk_pix) begin
	vga_hs <= osd_hs;
	vga_vs <= osd_vs;
	vga_rgb <= osd_de ? osd_rgb : 24'd0;
end
assign VGA_R = vga_rgb[23:16];
assign VGA_G = vga_rgb[15:8];
assign VGA_B = vga_rgb[7:0];
assign VGA_HS = vga_hs;
assign VGA_VS = vga_vs;

""", "HDMI")
    return s


MARK = "# ------------------------------------------------------------------------------------------------------------\n# Timing constraints"


def ucf(board):
    g = open(os.path.join(SRC, "karabas_minig.ucf")).read()
    if g.count(MARK) != 1:
        sys.exit("mktops.py: no timing mark in karabas_minig.ucf")
    timing = g[g.index(MARK):]
    timing = sub(timing, "karabas_minig_top.v", "karabas_%s_top.v" % board, "ucf top")
    if board == "go":
        timing = sub(timing, "#   pll_clk<2>, <3> 120 MHz, 0 / 180: the HDMI serialiser;  pll_clk<4> 8 MHz: FT_CLK_OUT\n",
                     "#   pll_clk<2>, <3>, <4>: not used on Go (no HDMI, no FT_CLK_OUT); V_CLK = ~clk_pix (an ODDR2)\n",
                     "ucf go clocks")
        a = timing.index("# the HDMI encoder runs on clk_pix")
        timing = timing[:a]
    pins = open(os.path.join(TOOLS, "pins_%s.ucf" % board)).read()
    path = os.path.join(SRC, "karabas_%s.ucf" % board)
    open(path, "w").write(pins.rstrip("\n") + "\n\n" + timing)
    print(os.path.normpath(path))


src = open(os.path.join(RTL, "karabas_minig_top.v")).read()
for name, f in (("karabas_mini_top.v", mini), ("karabas_go_top.v", go)):
    out = os.path.join(RTL, name)
    open(out, "w").write(f(src))
    print(os.path.normpath(out))
for board in ("mini", "go"):
    ucf(board)
