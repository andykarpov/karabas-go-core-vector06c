`timescale 1ns / 1ps
`default_nettype wire

/*
 v06c_loader.v — what the firmware loads, and the erases of the MiSTer core, one master on the aux
 port of v06c_sram. The SRAM map is that of the dpram of Vector-06C_MiSTer (byte address
 {page, addr}): 00000 the main RAM, 10000-4FFFF the RAM disk, 50000 the boot ROM.

 - rom_*: the ROMs of the core file, at rom_addr; those at 50000-57FFF are the boot ROM, its size
   (the highest byte + 1) goes to rom_size.
 - an FL item (file_*), by its slot (the ioctl indexes of the MiSTer core):
     1  .rom / .com at 0100 (up to FF00 bytes): the boot ROM off, then the rest of the 64 KB is
        cleared from the end of the file around to 00FF (the CPU runs the NOPs up to 0100)
     2  .edd, the RAM disk image, at 10000 (256 KB): the boot ROM stays on
     3  .c00 at 0000 (64 KB): the boot ROM off
     7  another boot ROM at 50000 (up to 32 KB): rom_size
     6  a .wav for the tape (v06c_tape) at 200000 (up to 2 MB): the machine keeps running (not busy)
 - cold (a rising edge): the main RAM and the RAM disk cleared (00000-4FFFF).
 busy while a load runs, a write waits or an erase runs: the machine is in reset meanwhile.
 The mcu writes a byte in ten clocks or less often; a write here takes four to six.
*/

module v06c_loader (
	input  wire        clk,
	input  wire        cold,

	input  wire        rom_active,
	input  wire [21:0] rom_addr,
	input  wire  [7:0] rom_data,
	input  wire        rom_wr,

	input  wire        file_active,
	input  wire  [7:0] file_slot,
	input  wire [31:0] file_addr,
	input  wire  [7:0] file_data,
	input  wire        file_wr,

	output wire        busy,
	output reg         erasing = 1'b0,
	output wire        rom_off,
	output reg  [15:0] rom_size = 16'd0,
	output reg         rom_size_wr = 1'b0,

	output reg         aux_req = 1'b0,
	output wire        aux_we,
	output reg  [21:0] aux_addr = 22'd0,
	output reg   [7:0] aux_din = 8'd0,
	input  wire        aux_ack
);

assign aux_we = 1'b1;
assign rom_off = (file_slot == 8'd1) || (file_slot == 8'd3);

reg        pend = 1'b0;
reg [21:0] pend_addr = 22'd0;
reg  [7:0] pend_data = 8'd0;
reg        cold_d = 1'b0;
reg        fa_d = 1'b0;
reg [16:0] last = 17'd0;      // slot 1: the end of the file (0100 + length)
reg [21:0] er_addr = 22'd0;
reg [21:0] er_end = 22'd0;
reg        er_wrap = 1'b0;    // the erase after a .rom: 16-bit addresses
reg        er_pend = 1'b0;    // start it when the last write is out
reg [15:0] sz = 16'd0;

reg pend_tape = 1'b0;          // the write waiting is of a .wav (slot 6): not busy
wire tape_load = file_active && file_slot == 8'd6;
assign busy = (file_active & ~tape_load) | rom_active | ((pend | aux_req) & ~pend_tape) | erasing | er_pend;

// a file write into its SRAM address; 1 = out of range (dropped)
reg [21:0] f_addr;
reg        f_drop;
always @(*) begin
	f_drop = 1'b0;
	case (file_slot)
		8'd1: begin f_addr = 22'h000100 + file_addr[15:0]; f_drop = (file_addr >= 32'h0000FF00); end
		8'd2: begin f_addr = 22'h010000 + file_addr[17:0]; f_drop = (file_addr >= 32'h00040000); end
		8'd3: begin f_addr = {6'd0, file_addr[15:0]};      f_drop = (file_addr >= 32'h00010000); end
		8'd7: begin f_addr = 22'h050000 + file_addr[14:0]; f_drop = (file_addr >= 32'h00008000); end
		8'd6: begin f_addr = 22'h200000 + file_addr[20:0]; f_drop = (file_addr >= 32'h00200000); end
		default: begin f_addr = 22'd0; f_drop = 1'b1; end
	endcase
end

always @(posedge clk) begin
	cold_d <= cold;
	fa_d <= file_active;
	rom_size_wr <= 1'b0;

	// the start of a load
	if (file_active & ~fa_d) begin
		last <= 17'h00100;
		if (file_slot == 8'd7) begin sz <= 16'd0; rom_size <= 16'd0; rom_size_wr <= 1'b1; end
	end

	if (rom_wr) begin
		pend <= 1'b1; pend_addr <= rom_addr; pend_data <= rom_data; pend_tape <= 1'b0;
		if (rom_addr[21:15] == 7'b0001010 && {1'b0, rom_addr[14:0]} >= sz) begin
			sz <= {1'b0, rom_addr[14:0]} + 1'd1;
			rom_size <= {1'b0, rom_addr[14:0]} + 1'd1;
			rom_size_wr <= 1'b1;
		end
	end else if (file_wr && !f_drop) begin
		pend <= 1'b1; pend_addr <= f_addr; pend_data <= file_data; pend_tape <= (file_slot == 8'd6);
		if (file_slot == 8'd1) last <= {1'b0, f_addr[15:0]} + 1'd1;
		if (file_slot == 8'd7 && {1'b0, file_addr[14:0]} >= sz) begin
			sz <= {1'b0, file_addr[14:0]} + 1'd1;
			rom_size <= {1'b0, file_addr[14:0]} + 1'd1;
			rom_size_wr <= 1'b1;
		end
	end

	// the end of a .rom load: the erase from its end around to 00FF
	if (~file_active & fa_d & (file_slot == 8'd1)) er_pend <= 1'b1;

	// the writes
	if (aux_req) begin
		if (aux_ack) aux_req <= 1'b0;
	end else if (pend) begin
		aux_req <= 1'b1; aux_addr <= pend_addr; aux_din <= pend_data; pend <= 1'b0;
	end else if (erasing) begin
		if (er_addr == er_end) erasing <= 1'b0;
		else begin
			aux_req <= 1'b1; aux_addr <= er_addr; aux_din <= 8'd0;
			er_addr <= er_wrap ? {6'd0, er_addr[15:0] + 1'd1} : er_addr + 1'd1;
		end
	end else if (er_pend) begin
		er_pend <= 1'b0;
		erasing <= (last[15:0] != 16'h0100);
		er_wrap <= 1'b1;
		er_addr <= {6'd0, last[15:0]};
		er_end <= 22'h000100;
	end

	if (cold & ~cold_d) begin
		erasing <= 1'b1;
		er_wrap <= 1'b0;
		er_addr <= 22'h000000;
		er_end <= 22'h050000;
	end
end

endmodule
