#!/usr/bin/env python3
"""A test .rom of the Vector-06C (loaded at 0100, started there): marker 5A at 0003, plane 8000-9FFF
filled with FF (the screen in colour 8), E0FF = 0F, an RST 7 handler (EI, RET) at 0038, then HLT and a
count of the interrupts at 0004."""
import sys

ORG = 0x100
code = bytearray()
labels = {}

def emit(*b): code.extend(b)
def w(v): return (v & 0xFF, v >> 8)
def here(): return ORG + len(code)

emit(0xF3)                         # DI
emit(0x31, *w(0x0100))             # LXI SP,0100
emit(0x3E, 0x5A); emit(0x32, *w(0x0003))   # MVI A,5A / STA 0003
emit(0x3E, 0xFB); emit(0x32, *w(0x0038))   # EI at 0038
emit(0x3E, 0xC9); emit(0x32, *w(0x0039))   # RET at 0039
emit(0x3E, 0x88); emit(0xD3, 0x00)         # PPI1 mode
emit(0x3E, 0xFF); emit(0xD3, 0x03)         # scroll FF
emit(0x3E, 0x00); emit(0xD3, 0x02)         # border 0, 256 mode
emit(0x21, *w(0x8000))                     # LXI H,8000
loop = here()
emit(0x36, 0xFF)                           # MVI M,FF
emit(0x23)                                 # INX H
emit(0x7C)                                 # MOV A,H
emit(0xFE, 0xA0)                           # CPI A0
emit(0xC2, *w(loop))                       # JNZ loop
emit(0x21, *w(0xE0FF)); emit(0x36, 0x0F)   # LXI H,E0FF / MVI M,0F
emit(0xFB)                                 # EI
halt = here()
emit(0x76)                                 # HLT
emit(0x3A, *w(0x0004)); emit(0x3C); emit(0x32, *w(0x0004))   # LDA / INR A / STA 0004
emit(0xC3, *w(halt))                       # JMP halt

open(sys.argv[1], "wb").write(code)
