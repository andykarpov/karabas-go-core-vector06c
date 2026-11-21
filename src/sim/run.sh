#!/bin/bash
# The Vector-06C machine in simulation (verilator). Builds sim_v06c into src/sim/build, runs from src/.
# Frames in build/*.ppm (the raster, 768 x 312).
#  1. the boot ROM («Загрузчик», US = Ctrl held: it clears only the screen, not all 64 KB, ~0.5 s):
#     its screen (ВЕКТОР-06Ц, the tape / disk bars) in the C000 / E000 planes, the interrupt
#     comes once a frame (958464 clocks of 48 MHz, +- the instruction it ends).
#  2. a test .rom (mkrom_test.py) through FL slot 1: it starts at 0100 with the boot ROM off, fills
#     the 8000 plane; the bytes it writes are checked. 3. the same at 6 MHz: the same screen.
#  4. the wait states (mkrom_timing.py): INX D / JMP between two interrupts counts 2991 or 2992 (every
#     machine cycle 4 T-states, a frame 59904 T).
#  5. the RAM disk (mkrom_edd.py): an .edd through FL 2 (page 1 A000 = 77), a .rom reads it through
#     the window of port 10 and writes 55 into page 1 C000 (SRAM 1C000).
#  6. a floppy write (mkrom_fdw.py) on a blank image: Write Sector of 1024 bytes, the image has them,
#     status 00. With the disk cache filling the SRAM meanwhile (the machine has the slots first).
#  7. only with FDD=<a MicroDOS .fdd> (e.g. ryba.fdd of svofski/v06c-badapple; ~2.5 min): the image on
#     drive A at 100 ms resets into the boot ROM, it loads the boot sectors through wd1793 and the cache,
#     Start (BLK+VVOD) at 1200 ms runs MicroDOS: its screen (text in the 8000 plane) by 3 s.
set -eu
H=$(cd "$(dirname "$0")" && pwd)
S=$(cd "$H/.." && pwd)
B=$H/build
mkdir -p "$B"
R=$S/rtl
SRC="$H/tb_v06c.v $R/v06c/v06c_system.v $R/v06c/v06c_sram.v $R/v06c/v06c_loader.v $R/v06c/v06c_vram.v $R/v06c/v06c_video.v $R/v06c/v06c_scan2x.v $R/v06c/v06c_kbd.v $R/v06c/k580vv55.v $R/v06c/k580vi53.v $R/vm80a/vm80a.v $R/fdd/wd1793.v $R/v06c/v06c_fdd_cache.v $S/../modules/rtl/mcu/img_sdc.v $S/../modules/rtl/mem/kg_spram.v $S/../modules/rtl/mem/kg_sdpram.v"
verilator --language 1364-2005 --cc --exe --build -j 8 -O3 --top-module tb_v06c -Mdir "$B/obj" -o sim_v06c \
	-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-PINNOTFOUND \
	--x-initial fast -CFLAGS -O2 $SRC "$H/sim_v06c.cpp" > "$B/build.log" 2>&1 || { grep -E "Error|error" "$B/build.log" | head -30; exit 1; }
[ -z "${BUILD_ONLY:-}" ] || exit 0
cd "$S"
SIM=$B/obj/sim_v06c
BOOT="--rom roms/boot.rom:0x50000 --key 0:14"
err=0
fail() { echo "FAIL: $*"; err=1; }

"$SIM" $BOOT --ms 250 --frame "$B/boot.ppm" > "$B/boot.txt" || err=1; cat "$B/boot.txt"
p=$(sed -n 's/.*last period \([0-9]*\).*/\1/p' "$B/boot.txt")
[ "$p" -gt 956464 ] && [ "$p" -lt 960464 ] || fail "boot: the interrupt period $p is not a frame"
[ "$(sed -n 's/.*C000 \([0-9]*\).*/\1/p' "$B/boot.txt")" -gt 0 ] || fail "boot: nothing drawn"

python3 "$H/mkrom_test.py" "$B/test.rom"
"$SIM" $BOOT --ms 320 --file 120:1:"$B/test.rom" --frame "$B/test.ppm" \
	--expect 0x0003:0x5A --expect 0x8000:0xFF --expect 0xE0FF:0x0F > "$B/test.txt" || fail "test.rom"
cat "$B/test.txt"
"$SIM" $BOOT --turbo --ms 320 --file 120:1:"$B/test.rom" --frame "$B/test_turbo.ppm" --expect 0x0003:0x5A > /dev/null || fail "test.rom turbo"
cmp -s "$B/test.ppm" "$B/test_turbo.ppm" || fail "test: 3 and 6 MHz screens differ"

python3 "$H/mkrom_timing.py" "$B/timing.rom"
"$SIM" $BOOT --ms 250 --file 120:1:"$B/timing.rom" --peek 6 --peek 7 > "$B/timing.txt" || err=1
n=$(( 0x$(sed -n 's/peek 000007 = //p' "$B/timing.txt")$(sed -n 's/peek 000006 = //p' "$B/timing.txt") ))
echo "timing: $n loops a frame"
[ $n = 2991 ] || [ $n = 2992 ] || fail "timing: $n loops a frame, not 2991 / 2992"

python3 "$H/mkrom_edd.py" "$B/edd.rom" "$B/test.edd"
"$SIM" $BOOT --ms 260 --file 100:2:"$B/test.edd" --file 200:1:"$B/edd.rom" \
	--expect 0x0005:0x77 --expect 0x1C000:0x55 > "$B/edd.txt" || fail "RAM disk"

python3 "$H/mkrom_fdw.py" "$B/fdw.rom"
python3 -c "open('$B/blank.fdd', 'wb').write(bytes(819200))"
"$SIM" $BOOT --ms 500 --disk 100:"$B/blank.fdd" --file 300:1:"$B/fdw.rom" --expect 0x0007:0x5A --expect 0x0006:0x00 \
	--expect-disk 0:0x5A --expect-disk 1:0x5B --expect-disk 0x3FF:0xA5 --expect-disk 0x400:0 > "$B/fdw.txt" || fail "floppy write"

if [ -n "${FDD:-}" ]; then
	"$SIM" $BOOT --key 450:F0,14 --ms 3000 --disk 100:"$FDD" --rst 1200:app --frame2x "$B/mdos.ppm" > "$B/mdos.txt" || err=1
	cat "$B/mdos.txt"
	[ "$(sed -n 's/.*: 8000 \([0-9]*\),.*/\1/p' "$B/mdos.txt")" -gt 2000 ] || fail "disk: MicroDOS did not start"
fi

[ $err = 0 ] && echo "sim ok" || echo "sim FAILED"
exit $err
