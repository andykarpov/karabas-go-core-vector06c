`timescale 1ns / 1ps
`default_nettype wire

/*
 v06c_kbd.v — the keyboard matrix of the Vector-06C from PS/2 set 2 scancodes.

 From keyboard.sv of Vector-06C_MiSTer:
   Copyright (C) 2011 Dmitry Tselikov. This core is distributed under modified BSD license.
   For complete licence read LICENSE.TXT (upstream/vector06_mister/LICENSE.TXT).

 karabas: Verilog-2001; the input is the byte stream of kg_mcu (scancode, scancode_upd toggles with
 each byte; E0 and F0 prefixes) instead of the ps2_key word of MiSTer. The map is that of
 keyboard.sv: the extended keys (arrows, Home, PgUp, Del, Enter of the keypad, the right Ctrl /
 Alt) give the same code as the base key, as hps_io gave them (ps2_key[7:0] without the E0 flag).

 addr: the row select of PPI1 port A, active high here (the system inverts it); odata: the keys
 of the selected rows, active high. shift = {RUS/LAT (Alt), US (Ctrl), SS (Shift)}, active high.
 reset_key on F11 (78): {Alt, Shift, any of Ctrl / Shift / Alt} held with it, as keyboard.sv.
*/

module v06c_kbd (
	input  wire       clk,
	input  wire       reset,
	input  wire [7:0] scancode,
	input  wire       scancode_upd,
	input  wire [7:0] addr,
	output reg  [7:0] odata,
	output wire [2:0] shift,
	output reg  [2:0] reset_key = 3'd0
);

reg [7:0] keystate [0:10];
assign shift = keystate[8][2:0];

reg [2:0] c;
reg [3:0] r;
reg [7:0] kcode = 8'd0;
reg       pressed = 1'b0;
reg       stb = 1'b0;        // a key event in kcode / pressed
reg       release_pfx = 1'b0;
reg       upd_d = 1'b0;

always @(*) begin
	odata =
		(keystate[0] & {8{addr[0]}}) |
		(keystate[1] & {8{addr[1]}}) |
		(keystate[2] & {8{addr[2]}}) |
		(keystate[3] & {8{addr[3]}}) |
		(keystate[4] & {8{addr[4]}}) |
		(keystate[5] & {8{addr[5]}}) |
		(keystate[6] & {8{addr[6]}}) |
		(keystate[7] & {8{addr[7]}});
end

always @(*) begin
	case (kcode)
		8'h0D: {c,r} = 7'h00; // tab
		8'h71: {c,r} = 7'h10; // . del
		8'h5A: {c,r} = 7'h20; // enter
		8'h66: {c,r} = 7'h30; // bksp
		8'h6B: {c,r} = 7'h40; // KP4 left
		8'h75: {c,r} = 7'h50; // KP8 up
		8'h74: {c,r} = 7'h60; // KP6 right
		8'h72: {c,r} = 7'h70; // KP2 down

		8'h6C: {c,r} = 7'h01; // KP7 home
		8'h7D: {c,r} = 7'h11; // KP9 pgup
		8'h76: {c,r} = 7'h21; // esc
		8'h05: {c,r} = 7'h31; // F1
		8'h06: {c,r} = 7'h41; // F2
		8'h04: {c,r} = 7'h51; // F3
		8'h0C: {c,r} = 7'h61; // F4
		8'h03: {c,r} = 7'h71; // F5

		8'h0B: {c,r} = 7'h01; // F6 -> home
		8'h83: {c,r} = 7'h11; // F7 -> str

		8'h45: {c,r} = 7'h02; // 0
		8'h16: {c,r} = 7'h12; // 1
		8'h1E: {c,r} = 7'h22; // 2
		8'h26: {c,r} = 7'h32; // 3
		8'h25: {c,r} = 7'h42; // 4
		8'h2E: {c,r} = 7'h52; // 5
		8'h36: {c,r} = 7'h62; // 6
		8'h3D: {c,r} = 7'h72; // 7

		8'h3E: {c,r} = 7'h03; // 8
		8'h46: {c,r} = 7'h13; // 9
		8'h55: {c,r} = 7'h23; // =
		8'h0E: {c,r} = 7'h33; // `
		8'h41: {c,r} = 7'h43; // ,
		8'h4E: {c,r} = 7'h53; // -
		8'h49: {c,r} = 7'h63; // .
		8'h4A: {c,r} = 7'h73; // gray/ + /

		8'h4C: {c,r} = 7'h04; // ;
		8'h1C: {c,r} = 7'h14; // A
		8'h32: {c,r} = 7'h24; // B
		8'h21: {c,r} = 7'h34; // C
		8'h23: {c,r} = 7'h44; // D
		8'h24: {c,r} = 7'h54; // E
		8'h2B: {c,r} = 7'h64; // F
		8'h34: {c,r} = 7'h74; // G

		8'h33: {c,r} = 7'h05; // H
		8'h43: {c,r} = 7'h15; // I
		8'h3B: {c,r} = 7'h25; // J
		8'h42: {c,r} = 7'h35; // K
		8'h4B: {c,r} = 7'h45; // L
		8'h3A: {c,r} = 7'h55; // M
		8'h31: {c,r} = 7'h65; // N
		8'h44: {c,r} = 7'h75; // O

		8'h4D: {c,r} = 7'h06; // P
		8'h15: {c,r} = 7'h16; // Q
		8'h2D: {c,r} = 7'h26; // R
		8'h1B: {c,r} = 7'h36; // S
		8'h2C: {c,r} = 7'h46; // T
		8'h3C: {c,r} = 7'h56; // U
		8'h2A: {c,r} = 7'h66; // V
		8'h1D: {c,r} = 7'h76; // W

		8'h22: {c,r} = 7'h07; // X
		8'h35: {c,r} = 7'h17; // Y
		8'h1A: {c,r} = 7'h27; // Z
		8'h54: {c,r} = 7'h37; // [
		8'h52: {c,r} = 7'h47; // '
		8'h5B: {c,r} = 7'h57; // ]
		8'h5D: {c,r} = 7'h67; // \!
		8'h29: {c,r} = 7'h77; // space

		8'h12: {c,r} = 7'h08; // lshift
		8'h59: {c,r} = 7'h08; // rshift
		8'h14: {c,r} = 7'h18; // rctrl + lctrl
		8'h11: {c,r} = 7'h28; // lalt

		default: {c,r} = 7'h7F;
	endcase
end

// karabas: the byte stream into key events (E0 is dropped: the code alone, as hps_io ps2_key[7:0])
always @(posedge clk) begin
	stb <= 1'b0;
	upd_d <= scancode_upd;
	if (upd_d != scancode_upd) begin
		if (scancode == 8'hE0) ;
		else if (scancode == 8'hF0) release_pfx <= 1'b1;
		else begin
			kcode <= scancode;
			pressed <= ~release_pfx;
			release_pfx <= 1'b0;
			stb <= 1'b1;
		end
	end
end

reg old_reset = 1'b0;
reg malt = 1'b0, mctrl = 1'b0, mshift = 1'b0;
integer i, j;

always @(posedge clk) begin
	old_reset <= reset;
	if (!old_reset && reset) begin
		for (i = 0; i <= 10; i = i + 1) keystate[i] <= 8'd0;
	end else if (stb) begin
		if (kcode == 8'h11) malt <= pressed;
		if (kcode == 8'h14) mctrl <= pressed;
		if (kcode == 8'h12) mshift <= pressed;
		if (kcode == 8'h59) mshift <= pressed;
		if (kcode == 8'h78) reset_key <= {(malt & pressed), (mshift & pressed), ((mctrl | mshift | malt) & pressed)};
		// karabas: constant indexes (XST makes tristates of keystate[r][c] <= ..)
		for (i = 0; i <= 10; i = i + 1)
			for (j = 0; j < 8; j = j + 1)
				if (r == i && c == j) keystate[i][j] <= pressed;
	end
end

initial for (i = 0; i <= 10; i = i + 1) keystate[i] = 8'd0;

endmodule
