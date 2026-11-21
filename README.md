# Vector-06C core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

A core of the Soviet home computer [Vector-06C](https://en.wikipedia.org/wiki/Vector-06C) (Вектор-06Ц, 1986) for the Karabas Go board family (Xilinx Spartan-6 XC6SLX25): KR580VM80A at 3 MHz with the exact wait states of the original, 64 KB RAM and the 256 KB RAM disk («квазидиск»), 256 × 256 graphics in 16 colours of 256 (or 512 × 256 in 4), the KR580VI53 three-voice timer sound, the AY, the KR1818VG93 floppy controller, the tape input.

| Board | Video | Sound |
|---|---|---|
| Karabas Go | VGA | I2S DAC (PCM5102) |
| Karabas Mini | HDMI | HDMI, analog output (sigma-delta) |
| Karabas Mini G | HDMI | HDMI, I2S DAC |

The core file `src/vector06c.kg` is one file for all three boards.

Status: checked on Mini G (the boot ROM, MicroDOS from a floppy image, drive B, programs, a program from a `.wav` tape, the 8253 sound, the AY). The Go and Mini builds have not been run on a board yet.

Contents: [Getting started](#getting-started) · [OSD menu](#osd-menu) · [Keys](#keys) · [Files](#files) · [Where to get software](#where-to-get-software) · [How the core works](#how-the-core-works) · [Building](#building) · [Tests](#tests) · [Licence and sources](#licence-and-sources)

## Getting started

1. Copy `src/vector06c.kg` to the root of the SD card and make the directory `/vector06c` on it. Put the programs (`.rom`), floppy images (`.fdd`), RAM disk images (`.edd`) and tape recordings (`.wav`) there.
2. Choose Vector-06C in the core menu. The boot ROM («Загрузчик») shows its screen: ВЕКТОР-06Ц, a tape icon, the tape bars. It waits for a tape or a disk.
3. A program: open the OSD (**Menu+Esc**), Files → ROM file (**Menu+F2**). It starts at once.
4. A disk: Disks → Disk A (**Menu+F7**). The boot ROM restarts and loads the boot sectors (a floppy icon, the bars fill). Then **Start** (**Menu+F11**, the БЛК+ВВОД of the original) runs it: a MicroDOS disk comes to `A>`.
5. A tape: Files → Tape .wav (**Menu+F4**) while the boot ROM waits (Reset, **F12**). The recording plays, the boot ROM loads it block by block (a tape icon, the bar fills); at the end **Start** runs the program. The boot ROM takes a mounted disk A first: eject it to load from the tape.

The OSD remembers the disk images: a core loaded again mounts them again.

"Menu" is the Windows key of the keyboard.

## OSD menu

| Item | Values | Hotkey |
|---|---|---|
| Disk A, Disk B | a `.fdd` image in `/vector06c` (read and write) | Menu+F7, Menu+F8 |
| ROM file | `.rom` / `.com` / `.r0m`: loaded at 0100 and started, the rest of the memory cleared | Menu+F2 |
| RAM disk | `.edd`: a dump of the 256 KB RAM disk; the boot ROM stays on | Menu+F3 |
| C00 file | `.c00`: loaded at 0000 and started | |
| Boot ROM | another boot ROM (up to 32 KB), instead of the built-in one until the core is loaded again | |
| Tape .wav | a `.wav` recording of a tape: it plays at once into the tape input (the machine keeps running) | Menu+F4 |
| CPU speed | 3 MHz (with the wait states of the original) / 6 MHz (no wait states) | Menu+S |
| Palette | Reset / Keep: the palette on a reset | |
| Reset | into the boot ROM (the memory stays) | F12 |
| Start | reset with the boot ROM off: the program in memory runs (БЛК+ВВОД) | Menu+F11 |
| Cold reset | the memory and the RAM disk cleared, the boot ROM | |
| Tape play, Tape stop | the `.wav` from its start again / stop | |

## Keys

The keyboard map is that of the MiSTer core: the Vector key at the place of the host key.

| Host key | Vector |
|---|---|
| Esc | АР2 |
| Ctrl | УС |
| Shift | СС |
| Alt | РУС/ЛАТ |
| Tab | ТАБ |
| Backspace | ЗБ |
| Enter | ВК |
| F1 … F5 | F1 … F5 |
| F6, Home (keypad 7) | ↖ |
| F7, PgUp (keypad 9) | СТР |
| Delete (keypad .) | ПС |
| `=` | `:` |
| Ctrl+F11, Shift+F11 | reset into the boot ROM |
| Alt+F11 | start the program in memory (as Start) |

Holding УС (Ctrl) while the boot ROM starts makes it clear only the screen, not all of the memory.

## Files

- `.rom` / `.com` / `.r0m`: a program, loaded at 0100 (up to 65 280 bytes) with the boot ROM off; the memory around it is cleared, so the CPU runs from 0000 into it.
- `.fdd`: a floppy image, 80 tracks × 2 sides × 5 sectors of 1024 bytes (819 200 bytes; a few images have 82 tracks). Writes go to the image on the card.
- `.edd`: the RAM disk, up to 256 KB (4 pages of 64 KB).
- `.wav`: a tape recording, PCM 8 or 16 bit, mono or stereo (the left channel), any sample rate, up to 2 MB (a 22 kHz 8-bit mono file of 1.5 minutes). The boot ROM loads from it as from a tape recorder; programs that read the tape do too.
- The boot ROM: `src/roms/boot.rom`, the «Загрузчик» of vector06cc (2 KB, the same as `bios.mif` of the MiSTer core).

## Where to get software

- Demos and intros by Viacheslav Slavinsky (svofski), the author of vector06cc, with ready `.rom` files: [v06c-timersound](https://github.com/svofski/v06c-timersound) (`release/timersound.rom`, also as `.wav`), [v06c-floppy](https://github.com/svofski/v06c-floppy) (`release/blksbr.rom`).
- A MicroDOS system floppy: `ryba.fdd` of [v06c-badapple](https://github.com/svofski/v06c-badapple).
- Tools: [bin2wav](https://github.com/svofski/bin2wav) (a binary into a tape `.wav`), [v06c-fddutil](https://github.com/svofski/v06c-fddutil) (floppy images), the emulators [vector06sdl](https://github.com/svofski/vector06sdl) and [vector06js](https://github.com/svofski/vector06js).

## How the core works

The machine is the MiSTer core of Sorgelig ([Vector-06C_MiSTer](https://github.com/MiSTer-devel/Vector-06C_MiSTer)), itself built on vector06cc, brought to the rules of the Karabas cores:

- one clock of 48 MHz with enables: the CPU (a cycle-exact KR580VM80A model by Vslav) at 3 MHz waits for its slot of the 4-T memory cycle as on the original (a frame is 59 904 T-states, checked in simulation);
- the memory is the SRAM of the board: the main 64 KB, the RAM disk, the boot ROM, the floppy images; the screen (8000–FFFF) is also copied into block RAM, so the video never waits;
- the video keeps the frame of the Vector: 768 × 312 pixels of 12 MHz, each line shown twice as 576p with 624 lines (50.08 Hz, 31.25 kHz as CEA 576p), 640 × 576 visible. No frame buffer: no frame is dropped or doubled;
- the floppy: one KR1818VG93 for both drives (as on the original), the images cached in the SRAM;
- all files come through the board firmware (the OSD items): there is no soft CPU in the core.

Sources: `src/rtl/v06c/` (the machine), `src/rtl/karabas_*_top.v` (the boards: Go and Mini are made from the Mini G top by `src/tools/mktops.py`), `docs/PLAN.md` and `docs/HARDWARE.md` (in Russian: the plan, the ports, the memory, the video).

## Building

ISE 14.7. `cd src && make` builds all three boards and `vector06c.kg`; `make minig` (or `go`, `mini`) one board, `make minig-report` its size and timing. `make v06c-xst` synthesises the machine alone. Clone with `--recursive` (the `modules` submodule). The upstream sources for reference: `tools/fetch_upstream.sh`.

## Tests

`src/sim/run.sh` (verilator, some 3 minutes): the boot ROM and the frame interrupt, a program from 0100 at 3 and 6 MHz, the wait states (a loop counted between two interrupts), the RAM disk, a floppy write, the AY, the tape from a `.wav`. With `FDD=<a MicroDOS .fdd>` it also boots MicroDOS (some 3 minutes more).

## Licence and sources

The core is GPL v3 (`LICENSE`). Its parts keep their licences: the MiSTer core of Sorgelig (BSD-2, `k580vi53` and the video GPL-3), the PPI and the keyboard of Dmitry Tselikov (BSD), vector06cc and the WD1793 of Viacheslav Slavinsky (BSD / GPL-2+), the KR580VM80A model of Vslav / 1801BM1 (CC BY 3.0), jt49 of Jose Tejada (GPL-3), the modules of karabas-go-modules.
