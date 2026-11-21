`timescale 1ns / 1ps
`default_nettype wire

/*
 v06c_video.v — the video of the Vector-06C in its own raster.

 From video.sv of Vector-06C_MiSTer:
   Copyright (c) 2016 Sorgelig
   This source file is free software: you can redistribute it and/or modify it under the terms of
   the GNU General Public License as published by the Free Software Foundation, either version 3
   of the License, or (at your option) any later version.

 karabas: Verilog-2001 for XST; the MiSTer video_mixer / scandoubler / gamma bus are gone. The
 output is the raster of the machine: 768 x 312 clocks of 12 MHz (64 us a line, 19.968 ms a frame),
 one pixel per ce_12mp, the 8-bit palette value (B2 G3 R3 of the Vector) and the blanks / syncs of
 video.sv. The top doubles the lines into 576p (624 lines). pix_ce tells a new pixel in the 512
 mode; in the 256 mode a point lasts two 12 MHz pixels, the colour is the same on both.

 hc / vc go out for the line doubler: hc 0..767, vc 0..311, the screen is hc 0..511, vc 0..255
 (rows 255..0 of the memory after the scroll).
*/

module v06c_video (
	input  wire        clk,
	input  wire        reset,       // the palette to its defaults
	input  wire        ce_12mp,
	input  wire        ce_12mn,

	output wire [12:0] vaddr,
	input  wire [31:0] vdata,       // {E000, C000, A000, 8000 planes} at vaddr

	input  wire  [7:0] din,
	input  wire        io_we,       // the palette port (0Ch), a level

	input  wire  [7:0] scroll,
	input  wire  [3:0] border,
	input  wire        mode512,
	output reg         retrace = 1'b0,

	output wire  [7:0] pal,         // the palette value of the current pixel (0 in the blanks)
	output wire [23:0] rgb,
	output reg         hblank = 1'b0,
	output reg         vblank = 1'b0,
	output reg         hsync = 1'b0,
	output reg         vsync = 1'b0,
	output wire        de,
	output reg   [9:0] hc = 10'd0,
	output reg   [8:0] vc = 9'd0
);

wire [8:0] vcr = vc + {1'b1, ~roll};    // karabas: ~roll of 9 bits as in video.sv (8-bit roll widened by ~)
reg  [7:0] roll = 8'd0;
reg        viden = 1'b0, dot = 1'b0;
reg  [7:0] idx0 = 8'd0, idx1 = 8'd0, idx2 = 8'd0, idx3 = 8'd0;
reg  [7:0] border_d = 8'd0;
reg        mode512_acc = 1'b0;
reg        mode512_lock = 1'b0;

assign vaddr = {hc[8:4], ~vcr[7:0]};

always @(posedge clk) begin
	if (ce_12mp) begin
		if (hc == 10'd767) begin
			hc <= 10'd0;
			if (vc == 9'd311) vc <= 9'd0;
			else vc <= vc + 1'd1;
			if (vc == 9'd271) begin
				retrace <= 1'b1;
				mode512_lock <= mode512_acc;
				mode512_acc <= 1'b0;
			end
			if (vc == 9'd281) retrace <= 1'b0;
		end else begin
			hc <= hc + 1'd1;
		end

		if ((vc == 9'd311) && (hc == 10'd759)) roll <= scroll;
		if (hc == 10'd563) begin
			hblank <= 1'b1;
			if (vc == 9'd267) vblank <= 1'b1;
		end
		if (hc == 10'd597) begin
			hsync <= 1'b1;
			if (vc == 9'd271) vsync <= 1'b1;
			if (vc == 9'd281) vsync <= 1'b0;
		end
		if (hc == 10'd653) hsync <= 1'b0;
		if (hc == 10'd723) begin
			hblank <= 1'b0;
			if (vc == 9'd295) vblank <= 1'b0;
		end
	end

	if (ce_12mn) begin
		if (hc[0]) begin
			idx0 <= {idx0[6:0], border_d[4]};
			idx1 <= {idx1[6:0], border_d[5]};
			idx2 <= {idx2[6:0], border_d[6]};
			idx3 <= {idx3[6:0], border_d[7]};
			if ((hc[3:1] == 3'd2) & ~hc[9] & ~vc[8]) {idx0, idx1, idx2, idx3} <= vdata;
			border_d <= {border_d[3:0], border};
		end
		dot <= ~hc[0];
		viden <= ~hblank & ~vblank;
		if (~hblank & ~vblank) mode512_acc <= mode512_acc | mode512;
	end
end

// the palette: 16 x 8 bits, written by OUT 0Ch at the index of the current pixel
reg  [7:0] palette [0:15];
wire [3:0] color_idx = {{2{~(mode512 & ~dot)}} & {idx3[7], idx2[7]}, {2{~(mode512 & dot)}} & {idx1[7], idx0[7]}};
reg old_we = 1'b0;
integer i;

always @(posedge clk) begin
	old_we <= io_we;
	if (reset) begin
		palette[0]  <= ~8'b11111111;
		palette[1]  <= ~8'b01010101;
		palette[2]  <= ~8'b11010111;
		palette[3]  <= ~8'b10000111;
		palette[4]  <= ~8'b11101010;
		palette[5]  <= ~8'b01101000;
		palette[6]  <= ~8'b11010000;
		palette[7]  <= ~8'b11000000;
		palette[8]  <= ~8'b10111101;
		palette[9]  <= ~8'b01111010;
		palette[10] <= ~8'b11000111;
		palette[11] <= ~8'b00111111;
		palette[12] <= ~8'b11101000;
		palette[13] <= ~8'b11010010;
		palette[14] <= ~8'b10010000;
		palette[15] <= ~8'b00000010;
	end else if (~old_we & io_we) begin
		palette[color_idx] <= din;
	end
end

wire [7:0] p = palette[color_idx];
assign pal = viden ? p : 8'd0;
// R3 G3 B2 to 8 bits each (video.sv takes 4 bits; here the same bits repeated)
assign rgb = viden ? {p[2:0], p[2:0], p[2:1], p[5:3], p[5:3], p[5:4], p[7:6], p[7:6], p[7:6], p[7:6]} : 24'd0;
assign de = viden;

// karabas: mode512_lock / the ce_pix of video.sv: the scandoubler of MiSTer took a pixel each
// ce_12mp in the 512 mode, every second one in the 256 mode; our doubler takes them all.
wire unused_lock = mode512_lock;

endmodule
