#!/usr/bin/env python3
"""A floppy write (wd1793 Write Sector, A0): mkrom_fdw.py ROM.
At 0100: fills 2000-23FF with (i & FF) ^ 5A, selects drive A side 0 (OUT 1C,34), waits not busy,
sector 1 (OUT 19,01), A0 into 1B, then sends a byte on each DRQ (status bit 1) until not busy;
the final status goes to 0006, 5A to 0007 at the end; HLT. The image then has the pattern at
track 0 side 0 sector 1 (offset 0)."""
import sys
ORG = 0x100
code = bytearray()
def e(*b): code.extend(b)
def here(): return ORG + len(code)
def w(v): return (v & 0xFF, v >> 8)
e(0xF3, 0x31, 0x00, 0x01)                 # DI, LXI SP,0100
e(0x21, *w(0x2000), 0x01, *w(0x0400))     # LXI H,2000 / LXI B,0400
fill = here()
e(0x7D, 0xEE, 0x5A, 0x77, 0x23, 0x0B)     # MOV A,L / XRI 5A / MOV M,A / INX H / DCX B
e(0x78, 0xB1, 0xC2, *w(fill))             # MOV A,B / ORA C / JNZ fill
e(0x3E, 0x34, 0xD3, 0x1C)                 # MVI A,34 / OUT 1C
nb = here()
e(0xDB, 0x1B, 0x0F, 0xDA, *w(nb))         # IN 1B / RRC / JC nb (busy)
e(0x3E, 0x01, 0xD3, 0x19)                 # sector 1
e(0x21, *w(0x2000))                       # LXI H,2000
e(0x3E, 0xA0, 0xD3, 0x1B)                 # write sector
lp = here()
e(0xDB, 0x1B)                             # IN 1B
e(0xE6, 0x03)                             # ANI 03
e(0xCA, 0, 0)                             # JZ done (patched)
jz = len(code) - 2
e(0xE6, 0x02, 0xCA, *w(lp))               # ANI 02 / JZ lp (busy, no DRQ)
e(0x7E, 0xD3, 0x18, 0x23, 0xC3, *w(lp))   # MOV A,M / OUT 18 / INX H / JMP lp
done = here()
code[jz:jz + 2] = bytes(w(done))
e(0xDB, 0x1B, 0x32, *w(0x0006))           # IN 1B / STA 0006
e(0x3E, 0x5A, 0x32, *w(0x0007))           # MVI A,5A / STA 0007
e(0x76)
open(sys.argv[1], "wb").write(code)
