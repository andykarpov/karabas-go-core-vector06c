// The Vector-06C machine in simulation (verilator, tb_v06c): 48 MHz clocks.
//   --rom FILE:ADDR       a ROM of the core file into the SRAM before the start (boot ROM: 0x50000)
//   --file MS:SLOT:FILE   an FL load at MS milliseconds (v06c_loader slots: 1 .rom, 2 .edd, 3 .c00, 7 boot ROM)
//   --key MS:B,B,..       PS/2 set 2 bytes (hex) at MS, 50 us apart
//   --rst MS:boot|app|cold  an OSD reset at MS
//   --ms N                run N ms after the ROM load (default 1000)
//   --turbo               6 MHz
//   --frame FILE.ppm      the last full frame of the raster (768 x 312, 12 MHz pixels)
//   --frame2x FILE.ppm    the last full frame of the 576p output (640 x 576 active, v06c_scan2x)
//   --expect ADDR:VAL     an SRAM byte at the end (exit 1 if not)
//   --peek ADDR           print an SRAM byte at the end
//   --io N                print the first N IN / OUT cycles
//   --disk MS:FILE        mount FILE on drive A (F slot 4) at MS
//   --pc MS1:MS2          print the opcode fetch addresses between MS1 and MS2
//   --expect-disk OFF:VAL a byte of the image of drive A at the end (after the writes)
//   --trace               print the CPU address every 1 ms
// Prints the frames, the interrupt acknowledges and the clocks of 48 MHz between the last two of them.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include "Vtb_v06c.h"
#include "verilated.h"

static Vtb_v06c *top;
static uint64_t clks = 0;
static const uint64_t MS = 48000;

static void mcu_clk();
static bool has_disk = false;

static void tick() {
	top->clk = 0; top->eval();
	if (has_disk) mcu_clk();
	top->clk = 1; top->eval();
	clks++;
}

// the mcu model of core-specialist sim_boot.cpp (link v1 img_* stream; img_sdc in tb_v06c)
static std::vector<uint8_t> disks[8];       // by slot: 4 --disk
#define disk disks[mcu_slot]
static int mcu_slot = 4;
static uint32_t mcu_lba = 0;
static int mcu_op = 0, mcu_pos = -1, mcu_gap = 0, mcu_wcnt = 0, mcu_bank = 0, mcu_wsum_parts = 0;
static int64_t mcu_wait = -1;
static uint8_t mcu_wbuf[512];
static uint16_t mcu_wsum = 0;
static int64_t mount_wait = -1; static int mount_sd = 0;
static int disk_reads = 0, disk_writes = 0;

static void mcu_clk() {
	top->img_q_ack = 0;
	top->img_data_wr = 0;
	top->img_result_wr = 0;
	top->img_mounted = 0;
	if (mount_wait > 0 && --mount_wait == 0) {
		top->img_size = disks[4].size();
		top->img_mounted = 1 << 4;
		mount_sd = 2000;
	}
	if (mount_sd > 0 && --mount_sd == 0 && !disks[6].empty()) {
		top->img_size = disks[6].size();
		top->img_mounted = 1 << 6;
	}
	if (top->img_q_wr && !top->img_q_ack) {
		uint32_t w = top->img_q_di;
		uint8_t c = w >> 16, a = w >> 8, d = w;
		top->img_q_ack = 1;
		if (c == 0x42) {
			if (a == 0) mcu_lba = 0;
			mcu_lba |= (uint32_t)d << (8 * a);
		}
		else if (c == 0x43) {
			mcu_op = d;
			mcu_slot = a;
			mcu_wcnt = 0; mcu_wsum_parts = 0; mcu_wsum = 0;
			if (d == 1) { mcu_wait = 4000; disk_reads++; }
		}
		else if (c == 0x44 && mcu_op == 2) {
			if (a == 0) mcu_bank = d & 1;
			else if (a == 0x10) { mcu_wsum = (mcu_wsum & 0xFF00) | d; mcu_wsum_parts++; }
			else if (a == 0x11) {
				mcu_wsum = (mcu_wsum & 0x00FF) | (d << 8); mcu_wsum_parts++;
				if (mcu_wsum_parts == 2) {
					if (mcu_lba * 512 + 512 <= disk.size()) memcpy(&disk[mcu_lba * 512], mcu_wbuf, 512);
					disk_writes++;
					mcu_op = 0;
					mcu_wait = 4000;
				}
			}
		}
		else if (c == 0x45 && mcu_op == 2) {
			mcu_wbuf[mcu_bank * 256 + a] = d;
			mcu_wcnt++;
		}
	}
	if (mcu_wait > 0) mcu_wait--;
	else if (mcu_wait == 0) {
		mcu_wait = -1;
		if (mcu_op == 1) { mcu_pos = 0; mcu_gap = 0; }
		else { top->img_result = 1; top->img_result_wr = 1; }
	}
	if (mcu_pos >= 0 && ++mcu_gap == 11) {
		mcu_gap = 0;
		if (mcu_pos < 512) {
			size_t o = mcu_lba * 512ull + mcu_pos;
			uint8_t b = o < disk.size() ? disk[o] : 0;
			static uint16_t sum;
			if (mcu_pos == 0) sum = 0;
			sum += b;
			top->img_data_addr = mcu_pos;
			top->img_data = b;
			top->img_data_wr = 1;
			top->img_sum = sum;
			mcu_pos++;
		}
		else {
			mcu_pos = -1;
			mcu_op = 0;
			top->img_result = 1;
			top->img_result_wr = 1;
		}
	}
}


static uint8_t peek(uint32_t a) {
	top->dbg_addr = a; top->eval();
	return top->dbg_q;
}

static std::vector<uint8_t> readfile(const char *name) {
	std::vector<uint8_t> d;
	FILE *f = fopen(name, "rb");
	if (!f) { perror(name); exit(2); }
	int c;
	while ((c = fgetc(f)) != EOF) d.push_back(c);
	fclose(f);
	return d;
}

struct Ev { uint64_t at; int kind; int slot; std::string file; std::vector<uint8_t> keys; bool done; };

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	top = new Vtb_v06c;
	std::vector<std::pair<std::string, uint32_t>> roms;
	std::vector<std::pair<uint32_t, int>> expects;
	std::vector<uint32_t> peeks;
	std::vector<std::pair<uint32_t, int>> dexp;
	std::vector<Ev> evs;
	int ms = 1000;
	const char *frame = nullptr, *frame2x = nullptr;
	static uint32_t o_img[576][640];
	std::vector<uint32_t> o_cur(640 * 576, 0);
	int ox = 0, oy = 0, o_lines = 0, o_frames = 0; bool o_prev_de = false, o_prev_vs = true, o_have = false;
	bool turbo = false, trace = false; int io_n = 0; double pc_from = -1, pc_to = -1;
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--rom") || !strcmp(argv[i], "--expect")) {
			bool rom = argv[i][2] == 'r';
			std::string s = argv[++i];
			size_t c = s.rfind(':');
			if (rom) roms.push_back({ s.substr(0, c), (uint32_t)strtoul(s.c_str() + c + 1, nullptr, 0) });
			else expects.push_back({ (uint32_t)strtoul(s.c_str(), nullptr, 0), (int)strtol(s.c_str() + c + 1, nullptr, 0) });
		}
		else if (!strcmp(argv[i], "--file")) {
			std::string s = argv[++i];
			size_t c1 = s.find(':'), c2 = s.find(':', c1 + 1);
			evs.push_back({ strtoull(s.c_str(), nullptr, 0) * MS, 0, atoi(s.c_str() + c1 + 1), s.substr(c2 + 1), {}, false });
		}
		else if (!strcmp(argv[i], "--key")) {
			std::string s = argv[++i];
			Ev e { strtoull(s.c_str(), nullptr, 0) * MS, 1, 0, "", {}, false };
			const char *p = strchr(s.c_str(), ':') + 1;
			while (*p) { e.keys.push_back(strtoul(p, (char **)&p, 16)); if (*p == ',') p++; }
			evs.push_back(e);
		}
		else if (!strcmp(argv[i], "--rst")) {
			std::string s = argv[++i];
			const char *k = strchr(s.c_str(), ':') + 1;
			int kind = !strcmp(k, "boot") ? 2 : !strcmp(k, "app") ? 3 : 4;
			evs.push_back({ strtoull(s.c_str(), nullptr, 0) * MS, kind, 0, "", {}, false });
		}
		else if (!strcmp(argv[i], "--peek")) peeks.push_back(strtoul(argv[++i], nullptr, 0));
		else if (!strcmp(argv[i], "--disk")) {
			std::string a = argv[++i];
			size_t c = a.find(':');
			mount_wait = strtoll(a.c_str(), nullptr, 0) * MS;
			FILE *f = fopen(a.c_str() + c + 1, "rb");
			if (!f) { perror(a.c_str() + c + 1); return 2; }
			int ch;
			while ((ch = fgetc(f)) != EOF) disks[4].push_back(ch);
			fclose(f);
			has_disk = true;
		}
		else if (!strcmp(argv[i], "--expect-disk")) { std::string a = argv[++i]; size_t c = a.find(':'); dexp.push_back({ (uint32_t)strtoul(a.c_str(), nullptr, 0), (int)strtol(a.c_str() + c + 1, nullptr, 0) }); }
		else if (!strcmp(argv[i], "--turbo")) turbo = true;
		else if (!strcmp(argv[i], "--trace")) trace = true;
		else if (!strcmp(argv[i], "--io")) io_n = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--pc")) { const char *a = argv[++i]; pc_from = atof(a); pc_to = atof(strchr(a, ':') + 1); }
		else if (!strcmp(argv[i], "--ms")) ms = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--frame")) frame = argv[++i];
		else if (!strcmp(argv[i], "--frame2x")) frame2x = argv[++i];
		else { fprintf(stderr, "bad option %s\n", argv[i]); return 2; }
	}
	top->turbo = turbo;
	top->reset = 1;
	for (int i = 0; i < 400; i++) tick();
	top->reset = 0; top->rom_active = 1;
	for (auto &r : roms) {
		std::vector<uint8_t> d = readfile(r.first.c_str());
		uint32_t a = r.second;
		for (uint8_t c : d) {
			top->rom_addr = a++; top->rom_data = c; top->rom_wr = 1; tick();
			top->rom_wr = 0;
			for (int i = 0; i < 11; i++) tick();
		}
	}
	for (int i = 0; i < 40; i++) tick();
	top->rom_active = 0;

	static uint32_t img[312][768];
	std::vector<uint32_t> cur(768 * 312, 0);
	int err_d = 0;
	int frames = 0, acks = 0; long snd_edges = 0, snd_edges_r = 0;
	uint64_t last_ack = 0, ack_period = 0, ack_min = UINT64_MAX, ack_max = 0;
	bool prev_ack = false, prev_vs = false, have_frame = false;
	uint64_t t0 = clks, end = t0 + (uint64_t)ms * MS, next_trace = t0 + MS;
	while (clks < end) {
		for (auto &e : evs) {
			if (e.done || clks - t0 < e.at) continue;
			e.done = true;
			if (e.kind == 0) {
				std::vector<uint8_t> d = readfile(e.file.c_str());
				top->file_slot = e.slot; top->file_active = 1;
				for (int i = 0; i < 20; i++) tick();
				for (size_t k = 0; k < d.size(); k++) {
					top->file_addr = k; top->file_data = d[k]; top->file_wr = 1; tick();
					top->file_wr = 0;
					for (int i = 0; i < 11; i++) tick();
				}
				for (int i = 0; i < 20; i++) tick();
				top->file_active = 0;
				printf("file slot %d: %zu bytes at %.1f ms\n", e.slot, d.size(), (clks - t0) / (double)MS);
			} else if (e.kind == 1) {
				for (uint8_t b : e.keys) {
					top->kb_scancode = b; top->kb_scancode_upd ^= 1;
					for (int i = 0; i < 2400; i++) tick();
				}
			} else {
				if (e.kind == 2) top->rst_boot = 1;
				if (e.kind == 3) top->rst_app = 1;
				if (e.kind == 4) top->rst_cold = 1;
				tick();
				top->rst_boot = 0; top->rst_app = 0; top->rst_cold = 0;
			}
		}
		tick();
		if (top->ce_pix && top->hc < 768 && top->vc < 312) {
			uint32_t v = top->rgb;
			if (top->hsync || top->vsync) v = 0x202020;
			cur[top->vc * 768 + top->hc] = v;
		}
		if (top->o_ce) {
			if (top->o_de) { if (ox < 640 && oy < 576) o_cur[oy * 640 + ox] = top->o_rgb; ox++; }
			else if (o_prev_de) { ox = 0; oy++; o_lines++; }
			o_prev_de = top->o_de;
			if (!top->o_vs && o_prev_vs) {
				if (o_frames++ > 0 && oy == 576) { memcpy(o_img, o_cur.data(), sizeof(o_img)); o_have = true; }
				oy = 0;
			}
			o_prev_vs = top->o_vs;
		}
		{
			static bool pw, pr;
			if (io_n > 0 && top->dbg_io_wr && !pw) { printf("%8.3f ms OUT %02X,%02X\n", (clks - t0) / (double)MS, top->cpu_addr & 0xFF, top->dbg_dout); io_n--; }
			static uint8_t rin; static uint16_t rport;
			if (top->dbg_io_rd) { rin = top->dbg_din; rport = top->cpu_addr & 0xFF; }
			if (io_n > 0 && !top->dbg_io_rd && pr) { printf("%8.3f ms IN  %02X = %02X\n", (clks - t0) / (double)MS, rport, rin); io_n--; }
			pw = top->dbg_io_wr; pr = top->dbg_io_rd;
		}
		{
			static bool pm;
			double t = (clks - t0) / (double)MS;
			if (pc_from >= 0 && t >= pc_from && t < pc_to && top->dbg_m1 && !pm) printf("%9.4f ms M1 %04X\n", t, top->cpu_addr);
			pm = top->dbg_m1;
		}
		{ static uint16_t pa, pr; if (top->audio_l != pa) { snd_edges++; pa = top->audio_l; } if (top->audio_r != pr) { snd_edges_r++; pr = top->audio_r; } }
		bool vs = top->vsync;
		if (vs && !prev_vs) {
			frames++;
			if (frames > 1) { memcpy(img, cur.data(), sizeof(img)); have_frame = true; }
		}
		prev_vs = vs;
		bool ack = top->cpu_int_ack;
		if (ack && !prev_ack && (!last_ack || clks - last_ack > 4800)) {  // one per interrupt (the INTA cycle and the HLT around it)
			acks++;
			if (last_ack) {
				ack_period = clks - last_ack;
				if (acks > 2) { if (ack_period < ack_min) ack_min = ack_period; if (ack_period > ack_max) ack_max = ack_period; }
			}
			last_ack = clks;
		}
		prev_ack = ack;
		if (trace && clks >= next_trace) {
			printf("%4.0f ms: pc %04X run %d\n", (clks - t0) / (double)MS, top->cpu_addr, top->running);
			next_trace += MS;
		}
	}
	printf("frames %d, interrupt acks %d, last period %llu clocks (min %llu max %llu; a frame is %d)\n", frames, acks,
		(unsigned long long)ack_period, (unsigned long long)(ack_min == UINT64_MAX ? 0 : ack_min),
		(unsigned long long)ack_max, 768 * 312 * 4);
	if (frame && have_frame) {
		FILE *f = fopen(frame, "wb");
		fprintf(f, "P6\n768 312\n255\n");
		for (int y = 0; y < 312; y++)
			for (int x = 0; x < 768; x++) {
				uint32_t v = img[y][x];
				fputc(v >> 16, f); fputc(v >> 8, f); fputc(v, f);
			}
		fclose(f);
	}
	{
		int nz[4] = {0, 0, 0, 0};
		for (uint32_t a = 0x8000; a < 0x10000; a++) if (peek(a)) nz[(a >> 13) & 3]++;
		printf("screen bytes not 0: 8000 %d, A000 %d, C000 %d, E000 %d\n", nz[0], nz[1], nz[2], nz[3]);
	}
	for (auto &e : dexp) { int v = e.first < disks[4].size() ? disks[4][e.first] : -1; if (v != e.second) { printf("expect disk %06X = %02X, got %02X\n", e.first, e.second, v); err_d = 1; } }
	for (uint32_t a : peeks) printf("peek %06X = %02X\n", a, peek(a));
	if (has_disk) printf("disk: %d sectors read, %d written\n", disk_reads, disk_writes);
	printf("sound changes %ld, right %ld\n", snd_edges, snd_edges_r);
	printf("576p: frames %d, active lines of the last frame %d\n", o_frames, oy);
	if (frame2x && o_have) {
		FILE *f = fopen(frame2x, "wb");
		fprintf(f, "P6\n640 576\n255\n");
		for (int y = 0; y < 576; y++)
			for (int x = 0; x < 640; x++) { uint32_t v = o_img[y][x]; fputc(v >> 16, f); fputc(v >> 8, f); fputc(v, f); }
		fclose(f);
	}
	int err = err_d;
	for (auto &e : expects) {
		int v = peek(e.first);
		if (v != e.second) { printf("expect %06X = %02X, got %02X\n", e.first, e.second, v); err = 1; }
	}
	delete top;
	return err;
}
