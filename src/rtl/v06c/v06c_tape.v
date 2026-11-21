`timescale 1ns / 1ps
`default_nettype wire

/*
 v06c_tape.v — a .wav file as the tape input of the Vector-06C.

 The file comes through FL slot 6 into the SRAM at BASE (up to 2 MB; v06c_loader writes it, the
 machine keeps running). This module watches the same bytes: the "fmt " fields at their canonical
 offsets (channels 22, sample rate 24..27, bits 34) and the start of the samples after the "data"
 tag and its size, wherever it is. At the end of the load it plays: one sample per 1 / rate (an
 accumulator on clk), read through its own request on the aux port of v06c_sram (the left channel,
 the high byte of a 16-bit sample), and turns it into the tape bit with a hysteresis around the
 middle (8-bit unsigned; 16-bit signed: the top bit inverted). The bit goes to PC4 of PPI1 (the tape
 input of the machine), OR the TAPE_IN pin while nothing plays.

 play (a pulse): from the start again; stop (a pulse): silence. A new load plays it from the start.
*/

module v06c_tape #(
	parameter [21:0] BASE = 22'h200000,
	parameter CLK_HZ = 48000000
) (
	input  wire        clk,
	input  wire        play,
	input  wire        stop,

	input  wire        file_active,   // FL slot 6
	input  wire [31:0] file_addr,
	input  wire  [7:0] file_data,
	input  wire        file_wr,

	output reg         aux_req = 1'b0,
	output reg  [21:0] aux_addr = 22'd0,
	input  wire        aux_ack,
	input  wire  [7:0] aux_dout,

	output reg         bit_out = 1'b0,
	output reg         playing = 1'b0
);

// ------------------------------------------------------------------ the header
reg  [7:0] h_ch = 8'd1, h_bits = 8'd8;
reg [31:0] h_rate = 32'd22050;
reg [20:0] d_start = 21'd44, d_end = 21'd0;
reg [31:0] tag = 32'd0;
reg  [2:0] after_data = 3'd0;    // the bytes of the size after "data", then the samples
reg        got_data = 1'b0;
reg        fa_d = 1'b0;

always @(posedge clk) begin
	fa_d <= file_active;
	if (file_active & ~fa_d) begin
		got_data <= 1'b0;
		after_data <= 3'd0;
		tag <= 32'd0;
		d_end <= 21'd0;
	end
	if (file_wr && file_addr < 32'h00200000) begin
		tag <= {tag[23:0], file_data};
		d_end <= file_addr[20:0] + 1'd1;
		case (file_addr)
			32'd22: h_ch <= file_data;
			32'd24: h_rate[7:0] <= file_data;
			32'd25: h_rate[15:8] <= file_data;
			32'd26: h_rate[23:16] <= file_data;
			32'd27: h_rate[31:24] <= file_data;
			32'd34: h_bits <= file_data;
			default: ;
		endcase
		if (!got_data) begin
			if (after_data != 3'd0) begin
				if (after_data == 3'd4) begin
					got_data <= 1'b1;
					d_start <= file_addr[20:0] + 1'd1;
				end
				after_data <= after_data + 1'd1;
			end
			else if ({tag[23:0], file_data} == 32'h64617461)   // "data"
				after_data <= 3'd1;
		end
	end
end

// ------------------------------------------------------------------ the player
// the bytes of one frame (all the channels of one sample time)
wire [2:0] fstep = (h_bits == 8'd16) ? ((h_ch == 8'd2) ? 3'd4 : 3'd2) : ((h_ch == 8'd2) ? 3'd2 : 3'd1);
wire       hi_byte = (h_bits == 8'd16);      // read the high byte of a 16-bit sample (offset + 1)

reg [20:0] pos = 21'd0;
reg [31:0] acc = 32'd0;
reg        due = 1'b0;

always @(posedge clk) begin
	if (aux_ack) aux_req <= 1'b0;

	if (~file_active & fa_d & got_data) begin      // the end of a load: play it
		pos <= d_start;
		acc <= 32'd0;
		playing <= 1'b1;
	end
	if (play && got_data && !file_active) begin
		pos <= d_start;
		acc <= 32'd0;
		playing <= 1'b1;
	end
	if (stop || file_active) begin
		playing <= 1'b0;
		due <= 1'b0;
	end

	if (playing) begin
		if (acc + h_rate >= CLK_HZ) begin
			acc <= acc + h_rate - CLK_HZ;
			due <= 1'b1;
		end
		else
			acc <= acc + h_rate;

		if (due && !aux_req) begin
			if (pos >= d_end) begin
				playing <= 1'b0;
				bit_out <= 1'b0;
			end
			else begin
				aux_req <= 1'b1;
				aux_addr <= BASE + {1'b0, pos} + (hi_byte ? 22'd1 : 22'd0);
				pos <= pos + fstep;
			end
			due <= 1'b0;
		end
	end
	else
		bit_out <= 1'b0;

	// the byte of the request: a hysteresis around the middle
	if (aux_ack && playing) begin
		if ((hi_byte ? (aux_dout ^ 8'h80) : aux_dout) > 8'h88) bit_out <= 1'b1;
		else if ((hi_byte ? (aux_dout ^ 8'h80) : aux_dout) < 8'h78) bit_out <= 1'b0;
	end
end

endmodule
