#!/usr/bin/env python3
"""The AY (ports 15 register, 14 data): tone A period 0100 (R0 = 00, R1 = 01), mixer R7 = 3E (tone A
only), volume A R8 = 0F; R8 read back through port 14 into 0005; then a loop. The sound: the left
channel moves (2A + B), the right one does not (2C + B)."""
import sys
code = bytearray()
def e(*b): code.extend(b)
e(0xF3, 0x31, 0x00, 0x01)
for r, v in [(0, 0x00), (1, 0x01), (7, 0x3E), (8, 0x0F)]:
    e(0x3E, r, 0xD3, 0x15, 0x3E, v, 0xD3, 0x14)
e(0x3E, 0x08, 0xD3, 0x15, 0xDB, 0x14, 0x32, 0x05, 0x00)   # R8 -> 0005
e(0xC3, 0x00 + len(code) + 0x00, 0x01)                   # JMP here (patched below)
code[-2] = (0x100 + len(code) - 3) & 0xFF
code[-1] = (0x100 + len(code) - 3) >> 8
open(sys.argv[1], "wb").write(code)
