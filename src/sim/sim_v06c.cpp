// The Vector-06C machine in simulation (verilator, tb_v06c): 48 MHz clocks.
//   --rom FILE:ADDR       a ROM of the core file into the SRAM before the start (boot ROM: 0x50000)
//   --file MS:SLOT:FILE   an FL load at MS milliseconds (v06c_loader slots: 1 .rom, 2 .edd, 3 .c00, 7 boot ROM)
//   --key MS:B,B,..       PS/2 set 2 bytes (hex) at MS, 50 us apart
//   --rst MS:boot|app|cold  an OSD reset at MS
//   --ms N                run N ms after the ROM load (default 1000)
//   --turbo               6 MHz
//   --frame FILE.ppm      the last full frame of the raster (768 x 312, 12 MHz pixels)
//   --expect ADDR:VAL     an SRAM byte at the end (exit 1 if not)
//   --peek ADDR           print an SRAM byte at the end
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

static void tick() {
	top->clk = 0; top->eval();
	top->clk = 1; top->eval();
	clks++;
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
	std::vector<Ev> evs;
	int ms = 1000;
	const char *frame = nullptr;
	bool turbo = false, trace = false;
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
		else if (!strcmp(argv[i], "--turbo")) turbo = true;
		else if (!strcmp(argv[i], "--trace")) trace = true;
		else if (!strcmp(argv[i], "--ms")) ms = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--frame")) frame = argv[++i];
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
	int frames = 0, acks = 0;
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
	for (uint32_t a : peeks) printf("peek %06X = %02X\n", a, peek(a));
	int err = 0;
	for (auto &e : expects) {
		int v = peek(e.first);
		if (v != e.second) { printf("expect %06X = %02X, got %02X\n", e.first, e.second, v); err = 1; }
	}
	delete top;
	return err;
}
