`timescale 1ns / 1ps
`default_nettype wire

/*
 v06c_system.v — the Vector-06C machine.

 The machine part of Vector-06C.sv of Vector-06C_MiSTer (Sorgelig, 2016-2026, BSD-2 in its
 LICENSE.TXT; the files keep their own headers), brought to the rules of the karabas cores:

 - one clock, clk 48 MHz (the MiSTer core: 96 MHz with the enables made on the falling edge).
   A frame of 64 clocks (div) is four T-states of the CPU at 3 MHz, the memory cycle of the Vector:
   ce_f1 / ce_f2 the phases of the vm80a at 3 MHz (6 MHz turbo: every 8 clocks), ce_12mp / ce_12mn
   the two halves of the 12 MHz pixel clock, clk_pit 1.5 MHz (div[4]), the wait of the CPU as
   in the MiSTer core (the CPU waits for its slot of the memory cycle at 3 MHz).
 - the memory is the SRAM of the board (v06c_sram, from core-specialist): byte address
   {page[2:0], addr[15:0]} as the dpram of the MiSTer core: page 0 the main 64 KB, 1..4 the RAM
   disk (port 10h), 5 the boot ROM (up to 32 KB, loaded by the firmware). The screen (8000-FFFF of
   page 0) is copied into a block RAM as it is written (v06c_vram: 4 planes x 8 KB, read 32 bits
   at once by the video), so the video never waits for the SRAM.
 - the file loads come from kg_mcu (v06c_loader); the machine is held in reset meanwhile and
   until the erase after a .rom is done, as the MiSTer core does.
 - the floppy (Ф2): one KR1818VG93 (wd1793 of core-specialist, as the one FDC of the Vector for
   both drives; the MiSTer core has one per drive), the images A / B of the F items (slots 4 / 5,
   .fdd: 80 x 2 x 5 x 1024) cached in the SRAM by v06c_fdd_cache (060000, 12D000) from the mounter of
   kg_mcu2 (its sector interface sdc_*). A mount of disk A while the boot ROM is on resets into the
   boot ROM (as fdd_busy of the MiSTer core).
 - the AY (jt49 of core-specialist) on ports 14 (data) / 15 (register), 1.75 MHz; the sound in
   stereo ABC (L = 2A + B, R = 2C + B) with the 8253, the beeper and the covox, signed.
 - the tape: a .wav through FL slot 6 played by v06c_tape into PC4 (else the TAPE_IN pin).
 - backlog (docs/BACKLOG.md): the Z80, .cas files, the physical floppy of the Go.
*/

module v06c_system (
	input  wire        clk,            // 48 MHz
	input  wire        reset,          // power-on / board reset: as a cold reset
	input  wire        turbo,          // 6 MHz
	input  wire        rst_boot,       // a pulse: reset into the boot ROM (the memory stays)
	input  wire        rst_app,        // a pulse: reset with the boot ROM off (start the program)
	input  wire        rst_cold,       // a pulse: clear the memory, boot ROM
	input  wire        pal_keep,       // the palette stays on reset (MiSTer "Reset Palette: No")

	// the loads of the firmware (link v2 loader signals, as spec_system)
	input  wire        rom_active,     // the ROMs of the core file
	input  wire [21:0] rom_addr,
	input  wire  [7:0] rom_data,
	input  wire        rom_wr,
	input  wire        file_active,    // an FL item
	input  wire  [7:0] file_slot,
	input  wire [31:0] file_addr,
	input  wire  [7:0] file_data,
	input  wire        file_wr,

	// the images of the F items: the sector interface of the mounter of kg_mcu2 (img_sdc names)
	input  wire  [7:0] sdc_img_mounted,
	input  wire [63:0] sdc_img_size,
	output wire  [7:0] sdc_rd,
	output wire  [7:0] sdc_wr,
	output wire [31:0] sdc_sector,
	input  wire        sdc_busy,
	input  wire        sdc_done,
	input  wire        sdc_error,
	input  wire  [2:0] sdc_slot,
	input  wire        sdc_byte_in_strobe,
	input  wire  [8:0] sdc_byte_addr,
	input  wire  [7:0] sdc_byte_in_data,
	output wire  [7:0] sdc_byte_out_data,
	input  wire  [7:0] img_wp,

	input  wire  [7:0] kb_scancode,
	input  wire        kb_scancode_upd,
	input  wire  [7:0] joy_a,          // MiSTer order: right, left, down, up, fire 1, fire 2 in bits 0..5
	input  wire  [7:0] joy_b,
	input  wire        tape_in,
	input  wire        tape_play,      // a pulse: the .wav from its start
	input  wire        tape_stop,
	output wire        tape_playing,

	// the video in the raster of the machine (v06c_video)
	output wire  [7:0] pal,
	output wire [23:0] rgb,
	output wire        hblank,
	output wire        vblank,
	output wire        hsync,
	output wire        vsync,
	output wire        de,
	output wire  [9:0] hc,
	output wire  [8:0] vc,
	output wire        ce_pix,         // ce_12mp: a pixel of the raster

	output wire [15:0] audio_l,        // two's complement (kg_pcm5102, hdmi_tx)
	output wire [15:0] audio_r,
	output wire        tape_out,

	output wire        running,        // the CPU is out of reset (sim)
	output wire [15:0] cpu_addr,       // sim
	output wire        cpu_int_ack,    // sim: an interrupt acknowledge cycle
	output wire        dbg_io_wr,      // sim: an OUT / IN cycle (level), cpu_addr[7:0] the port
	output wire        dbg_io_rd,
	output wire  [7:0] dbg_dout,
	output wire  [7:0] dbg_din,
	output wire        dbg_m1,         // sim: the status of an M1 (opcode fetch) at cpu_addr

	output wire [20:0] MA,
	inout  wire [15:0] MD,
	output wire  [1:0] MWR_N
);

// ---------------------------------------------------------------- clocks
reg  [5:0] div = 6'd0;
reg        ce_f1 = 1'b0, ce_f2 = 1'b0;
reg        ce_12mp = 1'b0, ce_12mn = 1'b0;
reg        clk_pit = 1'b0;
reg        turbo_r = 1'b0;
reg        cpu_ready = 1'b1;
wire       cpu_sync;
wire       mreq;

always @(posedge clk) begin
	div <= div + 1'd1;
	if (&div) turbo_r <= turbo;
	if (turbo_r) begin
		ce_f1 <= !div[2] & !div[1:0];
		ce_f2 <=  div[2] & !div[1:0];
		cpu_ready <= 1'b1;
	end else begin
		ce_f1 <= !div[3] & !div[2:0];
		ce_f2 <=  div[3] & !div[2:0];
		if (div[5:3] == 3'b100) cpu_ready <= 1'b1;
		else if (!div[3:1] & cpu_sync & mreq) cpu_ready <= 1'b0;
	end
	ce_12mp <= !div[1] & !div[0];
	ce_12mn <=  div[1] & !div[0];
	clk_pit <= div[4];
end
assign ce_pix = ce_12mp;

// ---------------------------------------------------------------- reset
wire       load_busy;              // a load or the erase after it
wire       disk_mount_a;           // an image mounted on drive A
wire       erasing;
wire       load_rom_off;           // the last file load turns the boot ROM off (.rom / .com / .c00)
wire       load_done;              // a pulse at the end of a file load
wire [2:0] reset_key;
reg        reset_flg = 1'b1;
reg        cpu_reset = 1'b1;
reg        cold_reset = 1'b1;
reg [13:0] reset_hold = 14'd0;
reg        rom_enable = 1'b1;
reg        key_d = 1'b0;
wire       key_rst = reset_key[0] & ~key_d;

always @(posedge clk) begin
	key_d <= reset_key[0];
	if (reset | rst_cold) begin
		reset_flg <= 1'b1;
		rom_enable <= 1'b1;
		cold_reset <= 1'b1;
	end
	if (load_busy) begin
		reset_flg <= 1'b1;
		cpu_reset <= 1'b1;
		if (file_active) rom_enable <= ~load_rom_off;
	end else begin
		if (reset_flg) begin
			reset_flg <= 1'b0;
			cpu_reset <= 1'b1;
			reset_hold <= 14'd10000;
		end else if (reset_hold != 14'd0) reset_hold <= reset_hold - 1'd1;
		else begin
			cpu_reset <= 1'b0;
			cold_reset <= 1'b0;
		end
		// the reset keys (F11 with Ctrl / Shift / Alt) and the OSD
		if (key_rst | rst_boot | rst_app | (disk_mount_a & rom_enable)) begin
			rom_enable <= ~(reset_key[2] | rst_app);   // Alt: the boot ROM off
			reset_flg <= 1'b1;
		end
	end
end
assign running = ~cpu_reset;

// ---------------------------------------------------------------- CPU
wire [15:0] addr;
wire  [7:0] cpu_o;
reg   [7:0] cpu_i;
wire        cpu_inte;
wire        cpu_rd;
wire        cpu_wr_n;
reg         cpu_int = 1'b0;

vm80a_core cpu (
	.pin_clk(clk),
	.pin_f1(ce_f1),
	.pin_f2(ce_f2),
	.pin_reset(cpu_reset),
	.pin_a(addr),
	.pin_dout(cpu_o),
	.pin_din(cpu_i),
	.pin_aena(),
	.pin_dena(),
	.pin_hold(1'b0),
	.pin_hlda(),
	.pin_ready(cpu_ready),
	.pin_wait(),
	.pin_int(cpu_int),
	.pin_inte(cpu_inte),
	.pin_sync(cpu_sync),
	.pin_dbin(cpu_rd),
	.pin_wr_n(cpu_wr_n)
);
assign cpu_addr = addr;

reg [7:0] status_word = 8'd0;
reg       old_sync = 1'b0;
always @(posedge clk) begin
	old_sync <= cpu_sync;
	if (~old_sync & cpu_sync) status_word <= cpu_o;
end

wire int_ack  = status_word[0];
wire write_n  = status_word[1];
wire io_stack = status_word[2];
wire io_write = status_word[4];
wire io_read  = status_word[6];
wire ram_read = status_word[7];
assign mreq = (ram_read | ~write_n) & ~io_write & ~io_read;
assign cpu_int_ack = int_ack & cpu_sync;

wire io_rd = io_read & cpu_rd;
wire io_wr = io_write & ~cpu_wr_n;
assign dbg_io_wr = io_wr;
assign dbg_io_rd = io_rd;
assign dbg_dout = cpu_o;
assign dbg_din = cpu_i;
assign dbg_m1 = cpu_sync & cpu_o[5];

// ---------------------------------------------------------------- I/O decode
reg ppi1_sel, joy_sel, vox_sel, pit_sel, pal_sel, psg_sel, edsk_sel, fdd_sel;
reg [7:0] io_data;
wire [7:0] ppi1_o, pit_o, psg_o, fdd_o;
wire [7:0] joyP_o, joyPU_o, joyA_o, joyB_o;

always @(*) begin
	ppi1_sel = 1'b0; joy_sel = 1'b0; vox_sel = 1'b0; pit_sel = 1'b0;
	pal_sel = 1'b0; edsk_sel = 1'b0; psg_sel = 1'b0; fdd_sel = 1'b0;
	io_data = 8'hFF;
	casex (addr[7:0])
		8'b000000XX: begin ppi1_sel = 1'b1; io_data = ppi1_o;  end
		8'b0000010X: begin joy_sel  = 1'b1; io_data = 8'h00;   end
		8'b00000110: begin                  io_data = joyP_o;  end
		8'b00000111: begin vox_sel  = 1'b1; io_data = joyPU_o; end
		8'b000010XX: begin pit_sel  = 1'b1; io_data = pit_o;   end
		8'b0000110X: begin pal_sel  = 1'b1;                    end
		8'b00001110: begin pal_sel  = 1'b1; io_data = joyA_o;  end
		8'b00001111: begin pal_sel  = 1'b1; io_data = joyB_o;  end
		8'b00010000: begin edsk_sel = 1'b1;                    end
		8'b0001010X: begin psg_sel  = 1'b1; io_data = psg_o;   end
		8'b000110XX: begin fdd_sel  = 1'b1; io_data = fdd_o;   end
		8'b000111XX: begin fdd_sel  = 1'b1;                    end
		default: ;
	endcase
end


// ---------------------------------------------------------------- memory
wire [7:0] ram_o;
reg  [15:0] rom_size = 16'd0;
reg  [2:0] ed_page;
wire read_rom = rom_enable && (addr < rom_size) && !ed_page && ram_read;

always @(*) begin
	casex ({int_ack, io_read})
		2'b01: cpu_i = io_data;
		2'b1X: cpu_i = 8'hFF;      // RST 7
		default: cpu_i = ram_o;
	endcase
end

wire [18:0] ram_addr = {read_rom ? 3'h5 : ed_page, addr};
wire        cpu_we = ~cpu_wr_n & ~io_write & ~cpu_reset;

// the aux port of the SRAM: the loader / eraser (own 1), the disk caches A (2) and B (3)
wire        aux_req, aux_we, aux_ack;
wire [21:0] aux_addr;
wire  [7:0] aux_din, aux_dout;
reg   [2:0] own = 3'd0;             // the aux port: 1 loader, 2 / 3 disk caches, 4 the tape
wire        tp_req;
wire [21:0] tp_addr;
wire        tp_bit;
wire        ld_req, ld_we;
wire [21:0] ld_addr;
wire  [7:0] ld_din;

v06c_sram sram (
	.clk(clk),
	.addr({3'b000, ram_addr}),
	.we(cpu_we),
	.din(cpu_o),
	.din_hi(8'd0),
	.wr16(1'b0),
	.dout(ram_o),
	.rd_ok(),
	.aux_req(aux_req),
	.aux_we(aux_we),
	.aux_addr(aux_addr),
	.aux_din(aux_din),
	.aux_ack(aux_ack),
	.aux_dout(aux_dout),
	.vid_req(1'b0),
	.vid_addr(21'd0),
	.vid_dout(),
	.vid_valid(),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N)
);

wire [15:0] load_rom_size;
wire        load_rom_size_wr;
always @(posedge clk) if (load_rom_size_wr) rom_size <= load_rom_size;

v06c_loader loader (
	.clk(clk),
	.cold(cold_reset),
	.rom_active(rom_active),
	.rom_addr(rom_addr),
	.rom_data(rom_data),
	.rom_wr(rom_wr),
	.file_active(file_active),
	.file_slot(file_slot),
	.file_addr(file_addr),
	.file_data(file_data),
	.file_wr(file_wr),
	.busy(load_busy),
	.erasing(erasing),
	.rom_off(load_rom_off),
	.rom_size(load_rom_size),
	.rom_size_wr(load_rom_size_wr),
	.aux_req(ld_req),
	.aux_we(ld_we),
	.aux_addr(ld_addr),
	.aux_din(ld_din),
	.aux_ack(aux_ack && own == 3'd1)
);

// the copy of the screen (page 0, 8000-FFFF): the CPU writes and the writes of the loader
reg cpu_we_d = 1'b0;
always @(posedge clk) cpu_we_d <= cpu_we;
wire cpu_vwr = cpu_we & ~cpu_we_d & (ram_addr[18:15] == 4'b0001);
wire aux_vwr = aux_ack & (own == 3'd1) & (aux_addr[21:15] == 7'b0000001);
wire        vwr  = aux_vwr | cpu_vwr;
wire [14:0] vwa  = aux_vwr ? aux_addr[14:0] : addr[14:0];
wire  [7:0] vwd  = aux_vwr ? aux_din : cpu_o;

wire [12:0] vaddr;
wire [31:0] vdata;

v06c_vram vram (
	.clk(clk),
	.we(vwr),
	.waddr(vwa),
	.wdata(vwd),
	.raddr(vaddr),
	.rdata(vdata)
);


// ---------------------------------------------------------------- floppy (KR1818VG93)
reg  fdd_drive = 1'b0, fdd_side = 1'b0;
reg  fctl_we_d = 1'b0;
wire fctl_we = io_wr & fdd_sel & addr[2];
always @(posedge clk) begin
	fctl_we_d <= fctl_we;
	if (cold_reset) fdd_drive <= 1'b0;
	if (~fctl_we_d & fctl_we) {fdd_side, fdd_drive} <= {~cpu_o[2], cpu_o[0]};
end

reg disk_a = 1'b0, disk_b = 1'b0;
always @(posedge clk) begin
	if (sdc_img_mounted[4]) disk_a <= |sdc_img_size[31:0];
	if (sdc_img_mounted[5]) disk_b <= |sdc_img_size[31:0];
end
assign disk_mount_a = sdc_img_mounted[4] & (|sdc_img_size[31:0]);
wire fdd_ready = fdd_drive ? disk_b : disk_a;

wire [31:0] sd_lba;
wire sd_rd, sd_wr, sd_ack_a, sd_ack_b, sd_bwr_a, sd_bwr_b;
wire [8:0] sd_addr_a, sd_addr_b;
wire [7:0] sd_do_a, sd_do_b, sd_buff_din;
wire [7:0] fdc_do;

wd1793 #(.RWMODE(1), .EDSK(0)) fdc (
	.clk_sys(clk),
	.ce(ce_f1),
	.reset(cpu_reset),
	.io_en(fdd_sel & fdd_ready & ~addr[2]),
	.rd(io_rd),
	.wr(io_wr),
	.addr(~addr[1:0]),
	.din(cpu_o),
	.dout(fdc_do),
	.drq(),
	.intrq(),
	.busy(),
	.wp(fdd_drive ? img_wp[5] : img_wp[4]),
	.size_code(3'd3),         // 5 sectors of 1024 bytes
	.layout(1'b0),            // track, side, sector
	.side(fdd_side),
	.ready(fdd_ready),
	.img_mounted(sdc_img_mounted[4] | sdc_img_mounted[5]),
	.img_size(sdc_img_size[19:0]),
	.prepare(),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack_a | sd_ack_b),
	.sd_buff_addr(fdd_drive ? sd_addr_b : sd_addr_a),
	.sd_buff_dout(fdd_drive ? sd_do_b : sd_do_a),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_bwr_a | sd_bwr_b),
	.input_active(1'b0),
	.input_addr(20'd0),
	.input_data(8'd0),
	.input_wr(1'b0),
	.buff_addr(),
	.buff_read(),
	.buff_din(8'd0)
);
assign fdd_o = fdd_ready ? fdc_do : 8'h00;

wire fd_req_a, fd_we_a, fd_req_b, fd_we_b;
wire [21:0] fd_addr_a, fd_addr_b;
wire [7:0] fd_din_a, fd_din_b;
wire [7:0] sdc_out_a, sdc_out_b;
wire [31:0] sdc_sector_a, sdc_sector_b;
wire sdc_rd_a, sdc_wr_a, sdc_rd_b, sdc_wr_b;
wire loading = rom_active | file_active;

v06c_fdd_cache #(.BASE(22'h060000), .MAXSEC(1640), .SLOT(3'd4)) cache_a (
	.clk(clk),
	.img_mounted(sdc_img_mounted[4]), .img_size(sdc_img_size[31:0]),
	.sd_rd(sd_rd & ~fdd_drive), .sd_wr(sd_wr & ~fdd_drive), .sd_lba(sd_lba), .sd_ack(sd_ack_a),
	.sd_buff_addr(sd_addr_a), .sd_buff_dout(sd_do_a), .sd_buff_wr(sd_bwr_a), .sd_buff_din(sd_buff_din),
	.sdc_rd(sdc_rd_a), .sdc_wr(sdc_wr_a), .sdc_sector(sdc_sector_a), .sdc_busy(sdc_busy), .sdc_done(sdc_done),
	.sdc_error(sdc_error), .sdc_slot(sdc_slot), .sdc_byte_in_strobe(sdc_byte_in_strobe),
	.sdc_byte_addr(sdc_byte_addr), .sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_out_a),
	.pause(loading),
	.aux_req(fd_req_a), .aux_we(fd_we_a), .aux_addr(fd_addr_a), .aux_din(fd_din_a),
	.aux_ack(aux_ack && own == 3'd2), .aux_dout(aux_dout),
	.filling(), .filled()
);

v06c_fdd_cache #(.BASE(22'h12D000), .MAXSEC(1640), .SLOT(3'd5)) cache_b (
	.clk(clk),
	.img_mounted(sdc_img_mounted[5]), .img_size(sdc_img_size[31:0]),
	.sd_rd(sd_rd & fdd_drive), .sd_wr(sd_wr & fdd_drive), .sd_lba(sd_lba), .sd_ack(sd_ack_b),
	.sd_buff_addr(sd_addr_b), .sd_buff_dout(sd_do_b), .sd_buff_wr(sd_bwr_b), .sd_buff_din(sd_buff_din),
	.sdc_rd(sdc_rd_b), .sdc_wr(sdc_wr_b), .sdc_sector(sdc_sector_b), .sdc_busy(sdc_busy), .sdc_done(sdc_done),
	.sdc_error(sdc_error), .sdc_slot(sdc_slot), .sdc_byte_in_strobe(sdc_byte_in_strobe),
	.sdc_byte_addr(sdc_byte_addr), .sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_out_b),
	.pause(loading),
	.aux_req(fd_req_b), .aux_we(fd_we_b), .aux_addr(fd_addr_b), .aux_din(fd_din_b),
	.aux_ack(aux_ack && own == 3'd3), .aux_dout(aux_dout),
	.filling(), .filled()
);

assign sdc_rd = {2'b00, sdc_rd_b, sdc_rd_a, 4'd0};
assign sdc_wr = {2'b00, sdc_wr_b, sdc_wr_a, 4'd0};
assign sdc_sector = (sdc_rd_a || sdc_wr_a) ? sdc_sector_a : sdc_sector_b;
assign sdc_byte_out_data = (sdc_slot == 3'd5) ? sdc_out_b : sdc_out_a;

// a master holds its request until the ack and drops it at that edge
always @(posedge clk) begin
	if (aux_ack) own <= 3'd0;
	else if (own == 3'd0) own <= ld_req ? 3'd1 : fd_req_a ? 3'd2 : fd_req_b ? 3'd3 : tp_req ? 3'd4 : 3'd0;
end
assign aux_req  = own == 3'd1 ? ld_req  : own == 3'd2 ? fd_req_a  : own == 3'd3 ? fd_req_b  : own == 3'd4 ? tp_req : 1'b0;
assign aux_we   = own == 3'd1 ? ld_we   : own == 3'd2 ? fd_we_a   : own == 3'd3 ? fd_we_b   : 1'b0;
assign aux_addr = own == 3'd1 ? ld_addr : own == 3'd2 ? fd_addr_a : own == 3'd3 ? fd_addr_b : tp_addr;
assign aux_din  = own == 3'd1 ? ld_din  : own == 3'd2 ? fd_din_a  : fd_din_b;

// ---------------------------------------------------------------- the tape (.wav of FL slot 6)
v06c_tape tape (
	.clk(clk),
	.play(tape_play),
	.stop(tape_stop),
	.file_active(file_active && file_slot == 8'd6),
	.file_addr(file_addr),
	.file_data(file_data),
	.file_wr(file_wr && file_slot == 8'd6),
	.aux_req(tp_req),
	.aux_addr(tp_addr),
	.aux_ack(aux_ack && own == 3'd4),
	.aux_dout(aux_dout),
	.bit_out(tp_bit),
	.playing(tape_playing)
);
wire tape_bit = tape_playing ? tp_bit : tape_in;

// ---------------------------------------------------------------- RAM disk 256 KB
reg [7:0] ed_reg = 8'd0;
reg       ed_we_d = 1'b0;
wire      edsk_we = io_wr & edsk_sel;
always @(posedge clk) begin
	ed_we_d <= edsk_we;
	if (cpu_reset) ed_reg <= 8'd0;
	else if (~ed_we_d & edsk_we) ed_reg <= cpu_o;
end

wire ed_win   = addr[15] & ((addr[13] ^ addr[14]) | (ed_reg[7] & addr[13] & addr[14]) | (ed_reg[6] & ~addr[13] & ~addr[14]));
wire ed_ram   = ed_reg[5] & ed_win & (ram_read | ~write_n);
wire ed_stack = ed_reg[4] & io_stack & (ram_read | ~write_n);

always @(*) begin
	casex ({ed_stack, ed_ram, ed_reg[3:0]})
		6'b1X00XX, 6'b01XX00: ed_page = 3'd1;
		6'b1X01XX, 6'b01XX01: ed_page = 3'd2;
		6'b1X10XX, 6'b01XX10: ed_page = 3'd3;
		6'b1X11XX, 6'b01XX11: ed_page = 3'd4;
		default: ed_page = 3'd0;
	endcase
end

// ---------------------------------------------------------------- video
wire retrace;
wire [7:0] ppi1_a, ppi1_b, ppi1_c;

v06c_video video (
	.clk(clk),
	.reset(cpu_reset & ~pal_keep),
	.ce_12mp(ce_12mp),
	.ce_12mn(ce_12mn),
	.vaddr(vaddr),
	.vdata(vdata),
	.din(cpu_o),
	.io_we(pal_sel & io_wr),
	.scroll(ppi1_a),
	.border(ppi1_b[3:0]),
	.mode512(ppi1_b[4]),
	.retrace(retrace),
	.pal(pal),
	.rgb(rgb),
	.hblank(hblank),
	.vblank(vblank),
	.hsync(hsync),
	.vsync(vsync),
	.de(de),
	.hc(hc),
	.vc(vc)
);

reg old_retrace = 1'b0;
always @(posedge clk) begin
	old_retrace <= retrace;
	if (!cpu_inte) cpu_int <= 1'b0;
	else if (~old_retrace & retrace) cpu_int <= 1'b1;
end

// ---------------------------------------------------------------- keyboard, PPI1
wire [7:0] kbd_o;
wire [2:0] kbd_shift;

v06c_kbd kbd (
	.clk(clk),
	.reset(cold_reset),
	.scancode(kb_scancode),
	.scancode_upd(kb_scancode_upd),
	.addr(~ppi1_a),
	.odata(kbd_o),
	.shift(kbd_shift),
	.reset_key(reset_key)
);

k580vv55 ppi1 (
	.clk_sys(clk),
	.reset(1'b0),
	.addr(~addr[1:0]),
	.we_n(~(io_wr & ppi1_sel)),
	.idata(cpu_o),
	.odata(ppi1_o),
	.ipa(8'hFF),
	.opa(ppi1_a),
	.ipb(~kbd_o),
	.opb(ppi1_b),
	.ipc({~kbd_shift, tape_bit, 4'b1111}),
	.opc(ppi1_c)
);
assign tape_out = ppi1_c[0];

// ---------------------------------------------------------------- joysticks (as the MiSTer core)
wire [7:0] joyPU = joy_a | joy_b;
assign joyPU_o = {joyPU[3], joyPU[0], joyPU[2], joyPU[1], joyPU[4], joyPU[5], 2'b00};
assign joyA_o  = ~{joy_a[5], joy_a[4], 2'b00, joy_a[2], joy_a[3], joy_a[1], joy_a[0]};
assign joyB_o  = ~{joy_b[5], joy_b[4], 2'b00, joy_b[2], joy_b[3], joy_b[1], joy_b[0]};

reg  [7:0] joy_port = 8'd0;
reg        joy_we_d = 1'b0;
wire       joy_we = io_wr & joy_sel;
always @(posedge clk) begin
	joy_we_d <= joy_we;
	if (cpu_reset) joy_port <= 8'd0;
	else if (~joy_we_d & joy_we) begin
		if (addr[0]) joy_port <= cpu_o;
		else if (!cpu_o[7]) joy_port[cpu_o[3:1]] <= cpu_o[0];
	end
end

reg [7:0] joyP_r;
always @(*) begin
	case (joy_port[6:5])
		2'b00: joyP_r = joyA_o & joyB_o;
		2'b01: joyP_r = joyA_o;
		2'b10: joyP_r = joyB_o;
		default: joyP_r = 8'hFF;
	endcase
end
assign joyP_o = joyP_r;

// ---------------------------------------------------------------- sound
wire [2:0] pit_out, pit_active;
wire [2:0] pit_snd = pit_out & pit_active;

k580vi53 pit (
	.reset(cpu_reset),
	.clk_sys(clk),
	.clk_timer({clk_pit, clk_pit, clk_pit}),
	.addr(~addr[1:0]),
	.wr(io_wr & pit_sel),
	.rd(io_rd & pit_sel),
	.din(cpu_o),
	.dout(pit_o),
	.gate(3'b111),
	.out(pit_out),
	.sound_active(pit_active)
);

// karabas: 3 bits (the MiSTer core sums the four into 2 bits, 4 wraps to 0)
wire [2:0] legacy_audio = {2'b00, ppi1_c[0]} + pit_snd[0] + pit_snd[1] + pit_snd[2];

reg  [7:0] covox = 8'd0;
reg [26:0] covox_timeout = 27'd0;
reg        vox_we_d = 1'b0;
wire       vox_we = io_wr & vox_sel & (covox_timeout == 27'd0);
always @(posedge clk) begin
	if (cpu_reset | rom_enable) covox_timeout <= 27'd100000000;   // 2 s
	else if (covox_timeout != 27'd0) covox_timeout <= covox_timeout - 1'd1;
	vox_we_d <= vox_we;
	if (cpu_reset) covox <= 8'd0;
	else if (~vox_we_d & vox_we) covox <= cpu_o;
end

// ---------------------------------------------------------------- AY (ports 14 data, 15 register)
reg       ay_ce = 1'b0;
reg [6:0] ay_acc = 7'd0;
reg [3:0] ay_reg = 4'd0;
reg       psg_we_d = 1'b0;
wire      psg_we = io_wr & psg_sel;
wire      psg_wp = psg_we & ~psg_we_d;
wire [7:0] ay_a, ay_b, ay_c;
always @(posedge clk) begin
	psg_we_d <= psg_we;
	ay_ce <= ay_acc >= 7'd89;                               // 48 MHz * 7 / 96 = 3.5 MHz (jt49 sel 0: / 2)
	ay_acc <= (ay_acc >= 7'd89) ? ay_acc + 7'd7 - 7'd96 : ay_acc + 7'd7;
	if (cpu_reset) ay_reg <= 4'd0;
	else if (psg_wp && addr[0]) ay_reg <= cpu_o[3:0];
end

jt49 ay (
	.rst_n(~cpu_reset),
	.clk(clk),
	.clk_en(ay_ce),
	.addr(ay_reg),
	.cs_n(1'b0),
	.wr_n(~(psg_wp && !addr[0])),
	.din(cpu_o),
	.sel(1'b0),
	.dout(psg_o),
	.sound(),
	.A(ay_a),
	.B(ay_b),
	.C(ay_c),
	.sample(),
	.IOA_in(8'hFF),
	.IOA_out(),
	.IOB_in(8'hFF),
	.IOB_out()
);

// The mix: {legacy, 8'd0} + {covox, 1'b0} as the MiSTer core (0..1534) and the AY in ABC stereo
// (2A + B, 2C + B: 0..765), 0..2299, unsigned. karabas: the DAC and HDMI take two's complement: centred
// on 0 (- 1150) and x 16, +-18400. Taken unsigned (as AUDIO_S 0 of the MiSTer core), the three 8253
// channels and the beeper all high gave 8000, the most negative value: the sound broke up on the DAC
// (user 2026-11-21).
wire [11:0] mix_base = {1'b0, legacy_audio, 8'd0} + {3'b000, covox, 1'b0};
wire [11:0] mix_l = mix_base + {3'b000, ay_a, 1'b0} + {4'b0000, ay_b};
wire [11:0] mix_r = mix_base + {3'b000, ay_c, 1'b0} + {4'b0000, ay_b};
wire signed [15:0] mix_ls = ($signed({4'd0, mix_l}) - 16'sd1150) <<< 4;
wire signed [15:0] mix_rs = ($signed({4'd0, mix_r}) - 16'sd1150) <<< 4;
assign audio_l = mix_ls;
assign audio_r = mix_rs;

endmodule
