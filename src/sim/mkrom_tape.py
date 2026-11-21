#!/usr/bin/env python3
"""The tape: mkrom_tape.py ROM WAV. WAV: 8-bit mono 22050 Hz, a 1 kHz square for 1 s (the samples
00 / FF, 11 per half period: 1002 Hz). ROM (at 0100): 5000 loops reading PC4 (IN 01, ANI 10); each
change counts in DE; DE goes to 0006 / 0007; 5A to 0008; HLT. At 3 MHz the loops take some 90 ms:
about 180 changes."""
import sys, struct
rate, n = 22050, 22050
data = bytes((0xFF if (i // 11) % 2 else 0x00) for i in range(n))
hdr = b'RIFF' + struct.pack('<I', 36 + len(data)) + b'WAVEfmt ' + struct.pack('<IHHIIHH', 16, 1, 1, rate, rate, 1, 8) \
    + b'data' + struct.pack('<I', len(data))
open(sys.argv[2], "wb").write(hdr + data)
ORG = 0x100
code = bytearray()
def e(*b): code.extend(b)
def here(): return ORG + len(code)
def w(v): return (v & 0xFF, v >> 8)
e(0xF3, 0x31, *w(0x0100))
e(0x11, *w(0))                     # LXI D,0
e(0x21, *w(5000))                  # LXI H,5000
e(0xDB, 0x01, 0xE6, 0x10, 0x47)    # IN 01 / ANI 10 / MOV B,A
lp = here()
e(0xDB, 0x01, 0xE6, 0x10)          # IN 01 / ANI 10
e(0xB8)                            # CMP B
e(0xCA, 0, 0); j = len(code) - 2   # JZ same
e(0x47, 0x13)                      # MOV B,A / INX D
same = here(); code[j:j + 2] = bytes(w(same))
e(0x2B, 0x7C, 0xB5, 0xC2, *w(lp))  # DCX H / MOV A,H / ORA L / JNZ lp
e(0xEB, 0x22, *w(0x0006))          # XCHG / SHLD 0006
e(0x3E, 0x5A, 0x32, *w(0x0008), 0x76)
open(sys.argv[1], "wb").write(code)
