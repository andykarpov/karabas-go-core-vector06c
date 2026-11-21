#!/usr/bin/env python3
"""The RAM disk (port 10): mkrom_edd.py ROM EDD.
EDD: 256 KB, page 1 (the first page) byte A000 = 77.
ROM (at 0100): OUT 10,20 (the window A000-DFFF on page 1), LDA A000 -> STA 0005 after OUT 10,00;
MVI A,55 / STA C000 in the window -> page 1 C000 (SRAM 1C000), the main C000 stays (0003 = its value
read back after OUT 10,00); HLT."""
import sys
code = bytearray()
def e(*b): code.extend(b)
e(0xF3, 0x31, 0x00, 0x01)              # DI, LXI SP,0100
e(0x3E, 0x20, 0xD3, 0x10)              # MVI A,20 / OUT 10
e(0x3A, 0x00, 0xA0)                    # LDA A000 (page 1)
e(0x47)                                # MOV B,A
e(0x3E, 0x55, 0x32, 0x00, 0xC0)        # MVI A,55 / STA C000 (page 1)
e(0x3E, 0x00, 0xD3, 0x10)              # MVI A,0 / OUT 10
e(0x78, 0x32, 0x05, 0x00)              # MOV A,B / STA 0005
e(0x3A, 0x00, 0xC0, 0x32, 0x03, 0x00)  # LDA C000 (main) / STA 0003
e(0x76)                                # HLT
open(sys.argv[1], "wb").write(code)
edd = bytearray(256 * 1024)
edd[0xA000] = 0x77
open(sys.argv[2], "wb").write(edd)
