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
	input  wire [21:0] dbg_addr,
	output wire  [7:0] dbg_q
);

wire [20:0] MA;
wire [15:0] MD;
wire [1:0] MWR_N;

v06c_system sys (
	.clk(clk), .reset(reset), .turbo(turbo), .rst_boot(rst_boot), .rst_app(rst_app), .rst_cold(rst_cold), .pal_keep(1'b0),
	.rom_active(rom_active), .rom_addr(rom_addr), .rom_data(rom_data), .rom_wr(rom_wr),
	.file_active(file_active), .file_slot(file_slot), .file_addr(file_addr), .file_data(file_data), .file_wr(file_wr),
	.kb_scancode(kb_scancode), .kb_scancode_upd(kb_scancode_upd), .joy_a(joy_a), .joy_b(8'd0), .tape_in(1'b0),
	.pal(), .rgb(rgb), .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync), .de(), .hc(hc), .vc(vc), .ce_pix(ce_pix),
	.audio_l(audio_l), .audio_r(), .tape_out(),
	.running(running), .cpu_addr(cpu_addr), .cpu_int_ack(cpu_int_ack),
	.MA(MA), .MD(MD), .MWR_N(MWR_N)
);

reg [7:0] lo [0:2097151];
reg [7:0] hi [0:2097151];
assign MD = (MWR_N == 2'b11) ? { hi[MA], lo[MA] } : 16'bz;
assign dbg_q = dbg_addr[0] ? hi[dbg_addr[21:1]] : lo[dbg_addr[21:1]];

always @(posedge clk) begin
	if (!MWR_N[0]) lo[MA] <= MD[7:0];
	if (!MWR_N[1]) hi[MA] <= MD[15:8];
end

endmodule
