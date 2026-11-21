`timescale 1ns / 1ps
`default_nettype wire

/*
 v06c_vram.v — the copy of the screen of the Vector-06C (8000-FFFF of the main RAM) in block RAM.

 Four planes of 8 KB (8000, A000, C000, E000: waddr[14:13]), each 8K x 8 (4 RAMB16). The video reads
 the four bytes of one offset at once: rdata = {E000, C000, A000, 8000}, as the 32-bit port of the
 dpram of the MiSTer core gave them. One clock from raddr to rdata.
*/

module v06c_vram (
	input  wire        clk,
	input  wire        we,
	input  wire [14:0] waddr,
	input  wire  [7:0] wdata,
	input  wire [12:0] raddr,
	output reg  [31:0] rdata = 32'd0
);

reg [7:0] p0 [0:8191];
reg [7:0] p1 [0:8191];
reg [7:0] p2 [0:8191];
reg [7:0] p3 [0:8191];

always @(posedge clk) begin
	if (we && waddr[14:13] == 2'd0) p0[waddr[12:0]] <= wdata;
	if (we && waddr[14:13] == 2'd1) p1[waddr[12:0]] <= wdata;
	if (we && waddr[14:13] == 2'd2) p2[waddr[12:0]] <= wdata;
	if (we && waddr[14:13] == 2'd3) p3[waddr[12:0]] <= wdata;
	rdata <= {p3[raddr], p2[raddr], p1[raddr], p0[raddr]};
end

endmodule
