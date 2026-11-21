`timescale 1ns / 1ps
`default_nettype wire

// v06c_system with a model of the SRAM (two lanes of 2M x 8, /OE low, as core-specialist tb_boot).
module tb_v06c (
	input  wire        clk,
	input  wire        reset,
	input  wire        turbo,
	input  wire        rst_boot,
	input  wire        rst_app,
	input  wire        rst_cold,
	input  wire        rom_active,
	input  wire [21:0] rom_addr,
	input  wire  [7:0] rom_data,
	input  wire        rom_wr,
	input  wire        file_active,
	input  wire  [7:0] file_slot,
	input  wire [31:0] file_addr,
	input  wire  [7:0] file_data,
	input  wire        file_wr,
	// the img_* stream of link v1 (the mcu model of sim_v06c) through img_sdc to the sdc_* of the system
	input  wire  [7:0] img_mounted,
	input  wire [63:0] img_size,
	input  wire        img_data_wr,
	input  wire  [8:0] img_data_addr,
	input  wire  [7:0] img_data,
	input  wire        img_result_wr,
	input  wire  [7:0] img_result,
	input  wire [15:0] img_sum,
	output wire        img_q_wr,
	output wire [23:0] img_q_di,
	input  wire        img_q_ack,
	input  wire  [7:0] kb_scancode,
	input  wire        kb_scancode_upd,
	input  wire  [7:0] joy_a,
	output wire [23:0] rgb,
	output wire        hblank,
	output wire        vblank,
	output wire        hsync,
	output wire        vsync,
	output wire  [9:0] hc,
	output wire  [8:0] vc,
	output wire        ce_pix,
	output wire [15:0] audio_l,
	output wire        running,
	output wire [15:0] cpu_addr,
	output wire        cpu_int_ack,
	output wire        dbg_io_wr,
	output wire        dbg_io_rd,
	output wire  [7:0] dbg_dout,
	output wire  [7:0] dbg_din,
	output wire        dbg_m1,
	output wire [23:0] o_rgb,
	output wire        o_hs,
	output wire        o_vs,
	output wire        o_de,
	output wire        o_ce,
	input  wire [21:0] dbg_addr,
	output wire  [7:0] dbg_q
);

wire [7:0] sdc_img_mounted, sdc_rd, sdc_wr, sdc_in_data, sdc_out;
wire [63:0] sdc_img_size;
wire [31:0] sdc_sector;
wire sdc_busy, sdc_done, sdc_error, sdc_in_strobe;
wire [2:0] sdc_slot;
wire [8:0] sdc_byte_addr;

img_sdc #(.OUT_LATENCY(3), .TIMEOUT(24'd9600000)) sdc (
	.clk(clk), .reset(1'b0),
	.img_mounted(img_mounted), .img_size(img_size), .img_data_wr(img_data_wr), .img_data_addr(img_data_addr),
	.img_data(img_data), .img_result_wr(img_result_wr), .img_result(img_result), .img_sum(img_sum),
	.img_q_wr(img_q_wr), .img_q_di(img_q_di), .img_q_ack(img_q_ack),
	.sdc_img_mounted(sdc_img_mounted), .sdc_img_size(sdc_img_size), .sdc_rd(sdc_rd), .sdc_wr(sdc_wr),
	.sdc_sector(sdc_sector), .sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(sdc_error), .sdc_slot(sdc_slot),
	.sdc_byte_in_strobe(sdc_in_strobe), .sdc_byte_addr(sdc_byte_addr), .sdc_byte_in_data(sdc_in_data),
	.sdc_byte_out_data(sdc_out), .active()
);

wire [20:0] MA;
wire [15:0] MD;
wire [1:0] MWR_N;

v06c_system sys (
	.clk(clk), .reset(reset), .turbo(turbo), .rst_boot(rst_boot), .rst_app(rst_app), .rst_cold(rst_cold), .pal_keep(1'b0),
	.rom_active(rom_active), .rom_addr(rom_addr), .rom_data(rom_data), .rom_wr(rom_wr),
	.file_active(file_active), .file_slot(file_slot), .file_addr(file_addr), .file_data(file_data), .file_wr(file_wr),
	.sdc_img_mounted(sdc_img_mounted), .sdc_img_size(sdc_img_size), .sdc_rd(sdc_rd), .sdc_wr(sdc_wr),
	.sdc_sector(sdc_sector), .sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(sdc_error), .sdc_slot(sdc_slot),
	.sdc_byte_in_strobe(sdc_in_strobe), .sdc_byte_addr(sdc_byte_addr), .sdc_byte_in_data(sdc_in_data),
	.sdc_byte_out_data(sdc_out), .img_wp(8'd0),
	.kb_scancode(kb_scancode), .kb_scancode_upd(kb_scancode_upd), .joy_a(joy_a), .joy_b(8'd0), .tape_in(1'b0),
	.pal(pal), .rgb(rgb), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .de(), .hc(hc), .vc(vc), .ce_pix(ce_pix),
	.audio_l(audio_l), .audio_r(), .tape_out(),
	.running(running), .cpu_addr(cpu_addr), .cpu_int_ack(cpu_int_ack), .dbg_io_wr(dbg_io_wr), .dbg_io_rd(dbg_io_rd), .dbg_dout(dbg_dout), .dbg_din(dbg_din), .dbg_m1(dbg_m1),
	.MA(MA), .MD(MD), .MWR_N(MWR_N)
);

wire [7:0] pal;
v06c_scan2x s2x (.clk(clk), .ce_pix(ce_pix), .hc(hc), .vc(vc), .pal(pal),
	.rgb(o_rgb), .hs(o_hs), .vs(o_vs), .de(o_de), .oce(o_ce));

reg [7:0] lo [0:2097151];
reg [7:0] hi [0:2097151];
assign MD = (MWR_N == 2'b11) ? { hi[MA], lo[MA] } : 16'bz;
assign dbg_q = dbg_addr[0] ? hi[dbg_addr[21:1]] : lo[dbg_addr[21:1]];

always @(posedge clk) begin
	if (!MWR_N[0]) lo[MA] <= MD[7:0];
	if (!MWR_N[1]) hi[MA] <= MD[15:8];
end

endmodule
