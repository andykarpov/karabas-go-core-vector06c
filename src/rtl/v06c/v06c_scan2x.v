`timescale 1ns / 1ps
`default_nettype wire

/*
 v06c_scan2x.v — the raster of the Vector-06C (768 x 312 pixels of 12 MHz, 64 us a line) as 576p
 with the frame of the machine: 768 x 624 pixels of 24 MHz (32 us a line: 31.25 kHz as CEA 576p,
 624 lines, 50.08 Hz), active 640 x 576, negative syncs. No frame buffer: each line of the machine
 is shown twice while the next one is written (user 2026-11-21, docs/PLAN.md). vector06cc on the
 Tang Nano 9K drives HDMI the same way.

 Everything runs on clk (48 MHz) and is locked to the counters of the machine: an output pixel
 every two clocks (the second half of each 12 MHz pixel period), the outputs change on those
 clocks only, so the top takes them on clk_pix (24 MHz of the same PLL).

 A display line is the machine pixels hc 708..767 of one line and 0..707 of the next (the left
 border comes at the end of the line before, hblank of the machine is 563..723): wx = hc - 708
 mod 768 is the write address, the line buffer half (bank) toggles at wx 0. While one half is
 written the other is read twice: output line A at wx 0..383, B at wx 384..767, x = 2 * (wx mod
 384) + the half of the 12 MHz period. Display line dl = the line of the machine at its pixel 0;
 it is shown as output lines 2 * vy, 2 * vy + 1 with vy = dl + 20 mod 312: active vy 0..287 (the
 lines 292..311 and 0..267 of the machine), the screen (vc 0..255) at output y 40..551; the screen
 columns (hc 0..511) at x 60..571.
*/

module v06c_scan2x (
	input  wire        clk,
	input  wire        ce_pix,     // ce_12mp of the machine: hc / vc / pal change after it
	input  wire  [9:0] hc,
	input  wire  [8:0] vc,
	input  wire  [7:0] pal,        // B2 G3 R3

	output reg  [23:0] rgb = 24'd0,
	output reg         hs = 1'b1,   // negative
	output reg         vs = 1'b1,
	output reg         de = 1'b0,
	output reg         oce = 1'b0   // a clock where the outputs change (for the sim)
);

localparam H_ACTIVE = 640, H_SYNC = 656, H_SYNC_END = 720;
localparam V_ACTIVE = 576, V_SYNC = 581, V_SYNC_END = 586;

// the phase in the 12 MHz pixel period (4 clocks): 0 at the clock after ce_pix
reg [1:0] ph = 2'd0;
always @(posedge clk) ph <= ce_pix ? 2'd0 : ph + 1'd1;

// write: at ce_pix the values of the last pixel
wire [9:0] wx = (hc >= 10'd708) ? hc - 10'd708 : hc + 10'd60;
reg bank = 1'b0;
reg [8:0] dl = 9'd0;          // the display line being written
reg [8:0] dl_show = 9'd0;     // the one shown
reg [7:0] lbuf [0:2047];
always @(posedge clk) begin
	if (ce_pix) begin
		if (wx == 10'd0) begin
			bank <= ~bank;
			dl_show <= dl;
			dl <= (vc == 9'd311) ? 9'd0 : vc + 1'd1;   // its pixels from hc 0 on are of the next machine line
		end
		// the pixel of wx 0 (at the end of its period) is the first of the new half
		lbuf[{(wx == 10'd0) ? ~bank : bank, wx}] <= pal;
	end
end

// read: output x / y from the write position
wire       half = (wx >= 10'd384);
wire [9:0] ox = {(half ? wx - 10'd384 : wx), 1'b0} | {9'd0, ph[1]};
// during the period of wx 0 the toggle has not come yet: the line just written is in bank, its
// number in dl
wire       rbank = (wx == 10'd0) ? bank : ~bank;
wire [8:0] shown = (wx == 10'd0) ? dl : dl_show;
wire [9:0] vy0 = {1'b0, shown} + 10'd20;
wire [8:0] vy = (vy0 >= 10'd312) ? vy0 - 10'd312 : vy0[8:0];
wire [9:0] oy = {vy, half};

reg  [7:0] p = 8'd0;
reg  [9:0] ox_d = 10'd0, oy_d = 10'd0;
reg        ph_d = 1'b0;
always @(posedge clk) begin
	p <= lbuf[{rbank, ox}];
	ox_d <= ox; oy_d <= oy;
	ph_d <= ph[0];
	oce <= 1'b0;
	if (ph_d) begin           // the clock after the second clock of each half: an output pixel
		oce <= 1'b1;
		de <= (ox_d < H_ACTIVE) && (oy_d < V_ACTIVE);
		hs <= ~((ox_d >= H_SYNC) && (ox_d < H_SYNC_END));
		vs <= ~((oy_d >= V_SYNC) && (oy_d < V_SYNC_END));
		rgb <= ((ox_d < H_ACTIVE) && (oy_d < V_ACTIVE)) ?
			{p[2:0], p[2:0], p[2:1], p[5:3], p[5:3], p[5:4], p[7:6], p[7:6], p[7:6], p[7:6]} : 24'd0;
	end
end

endmodule
