#!/usr/bin/env python3
# Creates a .rp6502 ROM file from BIOS and BDOS binaries.
# Usage: mkrp6502rom.py bios_bin bios_addr bdos_bin bdos_addr output
#
# The ROM file format (classic):
#   #!RP6502\r\n
#   $ADDR $LEN $CRC32\r\n
#   <binary_bytes>  ...repeated for each segment...
#
# The firmware starts the 6502 when it sees data written to $FFFC/$FFFD.
# Chunks must be <= MBUF_SIZE (1024 bytes); larger binaries are split.

import sys
import struct
import zlib

MBUF_SIZE = 1024


def segment(addr, data):
    crc = zlib.crc32(data) & 0xFFFFFFFF
    header = f"${addr:X} ${len(data):X} ${crc:X}\r\n".encode()
    return header + data


def segments(addr, data):
    out = b""
    offset = 0
    while offset < len(data):
        chunk = data[offset:offset + MBUF_SIZE]
        out += segment(addr + offset, chunk)
        offset += len(chunk)
    return out


def main():
    if len(sys.argv) != 6:
        print(
            f"Usage: {sys.argv[0]} bios_bin bios_addr bdos_bin bdos_addr output",
            file=sys.stderr,
        )
        sys.exit(1)

    bios_file = sys.argv[1]
    bios_addr = int(sys.argv[2], 16)
    bdos_file = sys.argv[3]
    bdos_addr = int(sys.argv[4], 16)
    output = sys.argv[5]

    with open(bios_file, "rb") as f:
        bios_data = f.read()
    with open(bdos_file, "rb") as f:
        bdos_data = f.read()

    reset_vec = struct.pack("<H", bios_addr)

    with open(output, "wb") as f:
        f.write(b"#!RP6502\r\n")
        f.write(segments(bios_addr, bios_data))
        f.write(segments(bdos_addr, bdos_data))
        f.write(segment(0xFFFC, reset_vec))


if __name__ == "__main__":
    main()
