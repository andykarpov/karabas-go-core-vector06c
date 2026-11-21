`timescale 1ns / 1ps
`default_nettype wire

/*
 Vector-06C core for Karabas Mini rev.G (HDMI, PCM5102). The board glue of core-specialist.

 The machine is v06c_system; all file work goes through the firmware: the boot ROM of core.json by
 the ROM loader, .rom / .edd / .c00 files and another boot ROM by the FL items, the floppy images
 (.fdd) by the F items Disk A / B (slots 4 / 5, the mounter of kg_mcu2).

 Clocks: a DCM makes 48 MHz of the 50 MHz crystal (24 / 25), a PLL on it (VCO 960 MHz): clk_sys
 48 MHz (/20: the machine), clk_pix 24 MHz (/40: the 576p of v06c_scan2x, 624 lines, 50.08 Hz),
 clk_hdmi 120 MHz and its inverse (/8, phase 0 / 180: the HDMI serialiser, 5 x clk_pix), clk_8
 8 MHz (/120, the FT812). clk_pix and clk_sys are of one PLL: the outputs of v06c_scan2x (on clk_sys,
 changing every second clock) are taken on clk_pix directly.

 Soft switches (the index of the item in the osd of core.json, file items included):
   0 Disk A (F 4)   1 Disk B (F 5)   2 ROM file (FL 1)   3 RAM disk .edd (FL 2)   4 C00 file (FL 3)
   5 Boot ROM (FL 7)   6 Tape .wav (FL 6)   7 CPU speed (3 / 6 MHz)   8 Palette on reset (Reset / Keep)
   9 Reset (to the boot ROM)   10 Start (reset, boot ROM off: the program in memory runs, BLK+VVOD)
   11 Cold reset (memory cleared)   12 Tape play (from the start)   13 Tape stop
*/

module karabas_minig_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N,
	output wire [1:0] MRD_N,

	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

	output wire SD_CS_N,
	output wire SD_CLK,
	output wire SD_DI,
	input wire SD_DO,
	input wire SD_DET_N,

	input wire [7:0] VGA_R,
	input wire [7:0] VGA_G,
	input wire [7:0] VGA_B,
	input wire VGA_HS,
	input wire VGA_VS,

	output wire [3:0] TMDS_P,
	output wire [3:0] TMDS_N,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	input wire FT_DE,
	output wire FT_CLK_OUT,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	output wire TAPE_OUT,
	input wire TAPE_IN,

	output wire DAC_BCK,
	output wire DAC_WS,
	output wire DAC_DAT,

	output wire ADC_CLK,
	inout wire ADC_BCK,
	inout wire ADC_LRCK,
	input wire ADC_DOUT,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	inout wire [5:0] MCU_IO, // [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n

	output wire MIDI_TX,

	output wire ESP32_SPI_CS_N,
	input wire ESP32_PCM_BCK,
	input wire ESP32_PCM_RLCK,
	input wire ESP32_PCM_DAT,

	output wire FLASH_CS_N,
	input wire FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N
);

// ------------------------------------------------------------------ unused

assign SDR_BA = 2'b11;
assign SDR_A = 13'h1FFF;
assign SDR_CLK = 1'b1;
assign SDR_DQM = 2'b11;
assign SDR_WE_N = 1'b1;
assign SDR_CAS_N = 1'b1;
assign SDR_RAS_N = 1'b1;
assign SDR_DQ = 16'bz;

assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;
assign WD = 16'bz;

assign ESP32_SPI_CS_N = 1'b1;
assign MIDI_TX = 1'b1;
assign UART_RX = 1'bz;
assign UART_TX = 1'bz;
assign UART_CTS = 1'bz;

assign FLASH_CS_N = 1'b1;   // Mini G2: also the SDRAM ~CS (SDRAM off)
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

assign ADC_CLK = 1'b0;
assign ADC_BCK = 1'bz;
assign ADC_LRCK = 1'bz;

assign MRD_N = 2'b00;  // SRAM /OE: always on, v06c_sram drives MD only with /WE

// ------------------------------------------------------------------ clocks

wire clk48_dcm, locked_dcm;
kg_dcm #(
	.CLKIN_PERIOD(20.0),
	.CLKFX_MULTIPLY(24),
	.CLKFX_DIVIDE(25),
	.IBUFG(1)
) dcm (
	.clk_in(CLK_50MHZ),
	.rst(1'b0),
	.clk_fx(clk48_dcm),
	.clk_fx180(),
	.clk_0(),
	.locked(locked_dcm)
);

wire [5:0] pll_clk;
wire locked;
kg_pll #(
	.CLKIN_PERIOD(20.833),
	.DIVCLK_DIVIDE(1),
	.CLKFBOUT_MULT(20),      // VCO 960 MHz
	.CLKOUT0_DIVIDE(20),     // 48 MHz
	.CLKOUT1_DIVIDE(40),     // 24 MHz
	.CLKOUT2_DIVIDE(8),      // 120 MHz
	.CLKOUT3_DIVIDE(8),      // 120 MHz, 180
	.CLKOUT3_PHASE(180.0),
	.CLKOUT4_DIVIDE(120),    // 8 MHz
	.BUFG_MASK(6'b011111),
	.IBUFG(0)
) pll (
	.clk_in(clk48_dcm),
	.rst(~locked_dcm),
	.clk_out(pll_clk),
	.locked(locked)
);
wire clk_sys = pll_clk[0];
wire clk_pix = pll_clk[1];
wire clk_hdmi = pll_clk[2];
wire clk_hdmi_n = pll_clk[3];
wire clk_8 = pll_clk[4];
wire areset = ~locked;

// the clock of the FT812
ODDR2 oddr_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8), .C1(~clk_8), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU

// MCU_SCK on a global buffer; the FT812 and SD2 get the IBUFG output (a BUFG drives no pad)
wire mcu_sck_ibufg, mcu_sck;
IBUFG ibufg_mcu_sck (.I(MCU_SCK), .O(mcu_sck_ibufg));
BUFG bufg_mcu_sck (.I(mcu_sck_ibufg), .O(mcu_sck));

wire mcu_int;
assign MCU_IO[1] = mcu_int;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;

localparam SW_N = 14;
wire [15:0] joy_l16, joy_r16;
wire [1:0] ld_kind;
wire [7:0] ld_slot, ld_data;
wire [31:0] ld_addr;
wire ld_active, ld_wr;
wire [SW_N*8-1:0] sw;
wire mcu_busy;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on, sd2_cs_n, sd2_mosi;
wire [7:0] ps2_code;
wire ps2_kind, ps2_wr;
wire osd_wr, osd_en, osd_zoom;
wire [7:0] img_wp;
// the disks: the mounter of kg_mcu2 (the sector interface of img_sdc) to v06c_system
wire [7:0] sdc_img_mounted, sdc_rd, sdc_wr, sdc_byte_in_data, sdc_byte_out_data;
wire [63:0] sdc_img_size;
wire [31:0] sdc_sector;
wire sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe;
wire [2:0] sdc_slot;
wire [8:0] sdc_byte_addr;
wire [11:0] osd_waddr;
wire [7:0] osd_wdata;
wire [23:0] osd_fg, osd_bg;
wire [1:0] osd_alpha, osd_place;
wire [4:0] osd_px, osd_ph;
wire [3:0] osd_py;
wire [5:0] osd_pw;

kg_mcu2 #(
	.CAPS(16'h0004),     // write protected images
	.SW_N(SW_N),
	.CS_FILTER(3),
	.ENABLE_OSD(1),
	.ENABLE_IMG(1),      // the floppy images of the F items
	.IMG_OUT_LATENCY(3),
	.ENABLE_FT(1),
	.ENABLE_SD2(1)
) mcu (
	.CLK(clk_sys),
	.N_RESET(~areset),

	.MCU_SCK(mcu_sck),
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SS(MCU_CS_N),
	.MCU_INT(mcu_int),
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),

	.SW(sw), .SW_WR(), .SW_INDEX(), .SW_VALUE(), .HW_ID(), .DVI_ONLY(dvi_only), .CORE_BUILD(), .FW_BUILD(),
	.BUSY(mcu_busy), .BTNS(), .RELOAD_REQ(1'b0), .RELOAD_CORE(8'd0),

	.KBD(), .KBD_WR(), .PS2_CODE(ps2_code), .PS2_KIND(ps2_kind), .PS2_WR(ps2_wr),
	.MS_X(), .MS_Y(), .MS_Z(), .MS_B(), .MS_WR(),
	.JOY_L(joy_l16), .JOY_R(joy_r16), .JOY_WR(),
	.PS2_CMD(16'h0000), .PS2_CMD_WR(1'b0),

	.LD_KIND(ld_kind), .LD_SLOT(ld_slot), .LD_SIZE(), .LD_START(), .LD_ACTIVE(ld_active), .LD_END(),
	.LD_ADDR(ld_addr), .LD_DATA(ld_data), .LD_WR(ld_wr), .LD_READY(1'b1),

	.OSD_WR(osd_wr), .OSD_WADDR(osd_waddr), .OSD_WDATA(osd_wdata), .OSD_EN(osd_en),
	.OSD_FG(osd_fg), .OSD_BG(osd_bg), .OSD_ALPHA(osd_alpha), .OSD_PX(osd_px), .OSD_PY(osd_py),
	.OSD_PW(osd_pw), .OSD_PH(osd_ph), .OSD_PLACE(osd_place), .OSD_ZOOM(osd_zoom),

	.SDC_IMG_MOUNTED(sdc_img_mounted), .SDC_IMG_SIZE(sdc_img_size),
	.SDC_RD(sdc_rd), .SDC_WR(sdc_wr), .SDC_SECTOR(sdc_sector),
	.SDC_BUSY(sdc_busy), .SDC_DONE(sdc_done), .SDC_ERROR(sdc_error), .SDC_SLOT(sdc_slot),
	.SDC_BYTE_IN_STROBE(sdc_byte_in_strobe), .SDC_BYTE_ADDR(sdc_byte_addr),
	.SDC_BYTE_IN_DATA(sdc_byte_in_data), .SDC_BYTE_OUT_DATA(sdc_byte_out_data),
	.IMG_WP(img_wp), .IMG_PHYS_WR(), .IMG_PHYS(), .IMG_FLUSH(), .FDD_CHNG_WR(), .FDD_CHNG(),
	.FDD_CHNG_REQ(1'b0), .FDD_CHNG_DS(2'd0), .IMG_ACTIVE(),

	.PORT_OUT_DATA(), .PORT_OUT_WR(), .PORT_OUT_READY(4'b1111), .PORT_IN_DATA(32'd0), .PORT_IN_WR(4'd0),
	.PORT_CFG(128'd0), .PORT_IN_FULL(), .PORT_STAT(), .PORT_STAT_WR(),
	.RTC_A(8'd0), .RTC_DI(8'd0), .RTC_CS(1'b0), .RTC_WR_N(1'b1), .MATRIX_CMD(24'd0), .MATRIX_CMD_WR(1'b0),
	.DEBUG_ADDR(16'd0), .DEBUG_DATA(16'd0), .RTC_DO(),

	.FT_SPI_ON(ft_spi_on), .FT_VGA_ON(), .FT_RESET(), .FT_SCK(), .FT_MOSI(ft_mosi), .FT_MISO(FT_SPI_MISO),
	.FT_CS_N(ft_cs_n),
	.SD2_SCK(), .SD2_MOSI(sd2_mosi), .SD2_MISO(SD_DO), .SD2_CS_N(sd2_cs_n)
);

// the loads of link v2: the roms of the core file (LD kind 0), the FL items (kind 2)
wire rom_active = ld_active && ld_kind == 2'd0;
wire rom_wr = ld_wr && ld_kind == 2'd0;
wire file_active = ld_active && ld_kind == 2'd2;
wire file_wr = ld_wr && ld_kind == 2'd2;

// the PS/2 scancode (set 2) as a toggle with each byte
reg kb_upd_t = 1'b0;
reg [7:0] kb_code_r = 8'd0;
always @(posedge clk_sys) begin
	if (ps2_wr && !ps2_kind) begin
		kb_code_r <= ps2_code;
		kb_upd_t <= ~kb_upd_t;
	end
end

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;
assign SD_CS_N = sd2_cs_n;
assign SD_DI = sd2_mosi;
assign SD_CLK = mcu_sck_ibufg;

// ------------------------------------------------------------------ soft switches

wire sw_turbo = sw[7*8];
wire sw_pal_keep = sw[8*8];
wire sw_reset = sw[9*8];
wire sw_start = sw[10*8];
wire sw_cold = sw[11*8];
wire sw_tplay = sw[12*8];
wire sw_tstop = sw[13*8];

// the triggers as pulses
reg [4:0] trg_d = 5'd0;
always @(posedge clk_sys) trg_d <= { sw_tstop, sw_tplay, sw_cold, sw_start, sw_reset };
wire rst_boot = sw_reset & ~trg_d[0];
wire rst_app = sw_start & ~trg_d[1];
wire rst_cold = sw_cold & ~trg_d[2];
wire tape_play = sw_tplay & ~trg_d[3];
wire tape_stop = sw_tstop & ~trg_d[4];

// the joysticks of the mcu (1 up, 2 down, 3 left, 4 right, 6 A, 7 B) in the order of the MiSTer
// core (0 right, 1 left, 2 down, 3 up, 4 fire 1, 5 fire 2)
wire [7:0] joy_a = { 2'b00, joy_l16[7], joy_l16[6], joy_l16[1], joy_l16[2], joy_l16[3], joy_l16[4] };
wire [7:0] joy_b = { 2'b00, joy_r16[7], joy_r16[6], joy_r16[1], joy_r16[2], joy_r16[3], joy_r16[4] };

// ------------------------------------------------------------------ the machine

wire [7:0] pal;
wire [9:0] hc;
wire [8:0] vc;
wire ce_pix;
wire [15:0] audio_l, audio_r;
wire tape_out;

v06c_system sys (
	.clk(clk_sys),
	.reset(areset),
	.turbo(sw_turbo),
	.rst_boot(rst_boot),
	.rst_app(rst_app),
	.rst_cold(rst_cold),
	.pal_keep(sw_pal_keep),
	.rom_active(rom_active),
	.rom_addr(ld_addr[21:0]),
	.rom_data(ld_data),
	.rom_wr(rom_wr),
	.file_active(file_active),
	.file_slot(ld_slot),
	.file_addr(ld_addr),
	.file_data(ld_data),
	.file_wr(file_wr),
	.sdc_img_mounted(sdc_img_mounted), .sdc_img_size(sdc_img_size), .sdc_rd(sdc_rd), .sdc_wr(sdc_wr),
	.sdc_sector(sdc_sector), .sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(sdc_error), .sdc_slot(sdc_slot),
	.sdc_byte_in_strobe(sdc_byte_in_strobe), .sdc_byte_addr(sdc_byte_addr), .sdc_byte_in_data(sdc_byte_in_data),
	.sdc_byte_out_data(sdc_byte_out_data), .img_wp(img_wp),
	.kb_scancode(kb_code_r),
	.kb_scancode_upd(kb_upd_t),
	.joy_a(joy_a),
	.joy_b(joy_b),
	.tape_in(TAPE_IN),
	.tape_play(tape_play),
	.tape_stop(tape_stop),
	.tape_playing(),
	.pal(pal),
	.rgb(),
	.hblank(),
	.vblank(),
	.hsync(),
	.vsync(),
	.de(),
	.hc(hc),
	.vc(vc),
	.ce_pix(ce_pix),
	.audio_l(audio_l),
	.audio_r(audio_r),
	.tape_out(tape_out),
	.running(),
	.cpu_addr(),
	.cpu_int_ack(),
	.dbg_io_wr(), .dbg_io_rd(), .dbg_dout(), .dbg_din(), .dbg_m1(),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N)
);
assign TAPE_OUT = tape_out;

// ------------------------------------------------------------------ video

wire [23:0] s2_rgb;
wire s2_hs, s2_vs, s2_de;
v06c_scan2x s2x (
	.clk(clk_sys), .ce_pix(ce_pix), .hc(hc), .vc(vc), .pal(pal),
	.rgb(s2_rgb), .hs(s2_hs), .vs(s2_vs), .de(s2_de), .oce()
);

// into clk_pix (of the same PLL; the outputs of s2x change every second clock of clk_sys)
reg [23:0] v_rgb = 24'd0;
reg v_hs = 1'b1, v_vs = 1'b1, v_de = 1'b0;
always @(posedge clk_pix) begin
	v_rgb <= s2_rgb;
	v_hs <= s2_hs;
	v_vs <= s2_vs;
	v_de <= s2_de;
end

// the bitmap OSD of link v2: written on clk_sys, shown on clk_pix, centred in de
wire [23:0] osd_rgb;
wire osd_hs, osd_vs, osd_de;
kg_l2_osd_overlay osd (
	.wclk(clk_sys),
	.osd_wr(osd_wr), .osd_waddr(osd_waddr), .osd_wdata(osd_wdata), .osd_en(osd_en),
	.osd_fg(osd_fg), .osd_bg(osd_bg), .osd_alpha(osd_alpha), .osd_px(osd_px), .osd_py(osd_py),
	.osd_pw(osd_pw), .osd_ph(osd_ph), .osd_place(osd_place), .osd_zoom(osd_zoom),
	.icon_on(8'd0), .icon_act(8'd0),
	.clk(clk_pix),
	.rgb_i(v_rgb), .hs_i(v_hs), .vs_i(v_vs), .de_i(v_de),
	.rgb_o(osd_rgb), .hs_o(osd_hs), .vs_o(osd_vs), .de_o(osd_de)
);

// ------------------------------------------------------------------ audio

kg_pcm5102 #(.DIV_BITS(2)) dac (
	.clk(clk_sys),
	.reset(areset),
	.left(audio_l),
	.right(audio_r),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_WS)
);

// the HDMI audio: a sample every 1000 clocks of clk_sys (48 kHz), taken on clk_pix at the change of
// the synchronised toggle; the sample clock of hdmi_tx: every 500 clocks of clk_pix
reg [15:0] smp_l = 16'd0, smp_r = 16'd0;
reg smp_tog = 1'b0;
reg [9:0] smp_cnt = 10'd0;
always @(posedge clk_sys) begin
	if (smp_cnt == 10'd999) begin
		smp_cnt <= 10'd0;
		smp_l <= audio_l;
		smp_r <= audio_r;
		smp_tog <= ~smp_tog;
	end else
		smp_cnt <= smp_cnt + 1'd1;
end
wire smp_tog_pix;
kg_sync smp_sync (.clk(clk_pix), .d(smp_tog), .q(smp_tog_pix));
reg smp_tog_pix_d = 1'b0;
reg [23:0] hdmi_l = 24'd0, hdmi_r = 24'd0;
always @(posedge clk_pix) begin
	smp_tog_pix_d <= smp_tog_pix;
	if (smp_tog_pix != smp_tog_pix_d) begin
		hdmi_l <= { smp_l, 8'd0 };
		hdmi_r <= { smp_r, 8'd0 };
	end
end

reg [8:0] aud_cnt = 9'd0;
reg aud_stb = 1'b0;
always @(posedge clk_pix) begin
	aud_stb <= (aud_cnt == 9'd499);
	aud_cnt <= (aud_cnt == 9'd499) ? 9'd0 : aud_cnt + 1'd1;
end
wire dvi_only_pix;
kg_sync dvi_sync (.clk(clk_pix), .d(dvi_only), .q(dvi_only_pix));

// syncs negative (576p); v06c_scan2x gives them negative already
hdmi_tx #(.SAMPLE_FREQ(48000)) hdmi (
	.clk(clk_pix),
	.sclk(clk_hdmi),
	.sclk_n(clk_hdmi_n),
	.reset(areset),
	.rgb(osd_rgb),
	.vsync(osd_vs),
	.hsync(osd_hs),
	.de(osd_de),
	.audio_en(~dvi_only_pix),
	.audio_l(hdmi_l),
	.audio_r(hdmi_r),
	.audio_clk(aud_stb),
	.tx_clk_n(TMDS_N[3]),
	.tx_clk_p(TMDS_P[3]),
	.tx_d_n(TMDS_N[2:0]),
	.tx_d_p(TMDS_P[2:0])
);

endmodule
