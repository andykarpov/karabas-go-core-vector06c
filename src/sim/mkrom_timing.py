#!/usr/bin/env python3
"""A timing test .rom of the Vector-06C: the loop INX D / JMP counts between two frame interrupts; the
RST 7 handler at 0038 stores the count at 0006 and clears it.

On the Vector every machine cycle takes 4 T-states (the CPU waits for its slot of the memory cycle):
INX D 8, JMP 12, the loop 20 T. The handler with the RST: RST 16, XCHG 4, SHLD 20, LXI 12, XCHG 4,
EI 4, RET 12 = 72. A frame is 59904 T: (59904 - 72) / 20 = 2991.6, so the count is 2991 or 2992
(0BAF / 0BB0). A plain 8080 (loop 15 T) would give about 3990."""
import sys

ORG = 0x100
code = bytearray()
def emit(*b): code.extend(b)
def w(v): return (v & 0xFF, v >> 8)
def here(): return ORG + len(code)

handler = [0xEB, 0x22, 0x06, 0x00, 0x21, 0x00, 0x00, 0xEB, 0xFB, 0xC9]
emit(0xF3)                               # DI
emit(0x31, *w(0x0100))                   # LXI SP,0100
for i, b in enumerate(handler):          # MVI A,b / STA 0038+i
	emit(0x3E, b); emit(0x32, *w(0x38 + i))
emit(0x11, *w(0))                        # LXI D,0
emit(0xFB)                               # EI
loop = here()
emit(0x13)                               # INX D
emit(0xC3, *w(loop))                     # JMP loop

open(sys.argv[1], "wb").write(code)
