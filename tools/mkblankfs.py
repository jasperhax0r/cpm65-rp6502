#!/usr/bin/env python3
"""
Create a blank CP/M filesystem image for the RP6502 Picocomputer.

Usage:
  python3 mkblankfs.py            # Creates CPMFSB (1MB B: drive image)
  python3 mkblankfs.py --drive a  # Creates CPMFS  (8MB A: drive image)

The resulting file should be placed on the FAT32 flash drive:
  CPMFS  -> A: drive (8MB, 1024 directory entries)
  CPMFSB -> B: drive (1MB,  128 directory entries)
"""

import argparse
import sys

# A: drive geometry (matches define_dpb dpb, 65536, 4096, 1024, 0)
A_SECTORS   = 65536
A_BLOCKSIZE = 4096
A_DIRENTS   = 1024

# B: drive geometry (matches define_dpb dpb_b, 8192, 4096, 128, 0)
B_SECTORS   = 8192
B_BLOCKSIZE = 4096
B_DIRENTS   = 128


def make_blank_fs(sectors, blocksize, dirents, output):
    dir_blocks = (dirents * 32 + blocksize - 1) // blocksize
    dir_bytes  = dir_blocks * blocksize
    total_bytes = sectors * 128

    print(f"Creating {output}: {total_bytes // 1024 // 1024}MB "
          f"({sectors} sectors, {blocksize}B blocks, {dirents} dirents)")
    print(f"  Initialising {dir_bytes // 1024}KB directory area with 0xE5...")

    with open(output, "wb") as f:
        f.write(b"\xe5" * dir_bytes)
        remaining = total_bytes - dir_bytes
        # Write the rest in 64KB chunks to avoid large allocations
        chunk = b"\x00" * 65536
        written = 0
        while written < remaining:
            n = min(65536, remaining - written)
            f.write(chunk[:n])
            written += n

    print(f"Done: {output} ({total_bytes // 1024}KB)")


def main():
    p = argparse.ArgumentParser(description="Create blank RP6502 CP/M filesystem image")
    p.add_argument("--drive", choices=["a", "b"], default="b",
                   help="Which drive image to create (default: b)")
    p.add_argument("--output", help="Output filename (default: CPMFS or CPMFSB)")
    args = p.parse_args()

    if args.drive == "a":
        output = args.output or "CPMFS"
        make_blank_fs(A_SECTORS, A_BLOCKSIZE, A_DIRENTS, output)
    else:
        output = args.output or "CPMFSB"
        make_blank_fs(B_SECTORS, B_BLOCKSIZE, B_DIRENTS, output)


if __name__ == "__main__":
    main()
