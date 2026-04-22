# CP/M-65 for the RP6502 Picocomputer

A port of [CP/M-65](https://github.com/davidgiven/cpm65) — a 65xx CP/M implementation — to the
[RP6502 Picocomputer](https://picocomputer.github.io/).

This repository contains a pre-built ROM and disk image so you can get up and running without a
build toolchain.

---

## What you need

- An [RP6502 Picocomputer](https://picocomputer.github.io/) with up-to-date firmware
- A USB flash drive formatted as **FAT32**
- A USB hub (if you want a B: drive later)

---

## Quick start

### 1. Copy the files to your flash drive

Place both files in the **root directory** of your FAT32 flash drive:

| File | Purpose |
|------|---------|
| `CPM65.RP6` | CP/M-65 ROM (BIOS + BDOS) |
| `CPMFS` | CP/M disk image (A: drive, 8MB, pre-loaded with utilities) |

> **Important:** `CPMFS` must have no file extension — the firmware opens it by that exact name.

### 2. Load the ROM on the RP6502

1. Insert the flash drive into the RP6502
2. Power on (or press reset)
3. At the firmware menu, navigate to the ROM loader and select `CPM65.RP6`

The firmware will load the ROM into RAM and start the 6502. You should see:

```
CP/M-65 for the RP6502 Picocomputer
A>
```

### 3. You're in CP/M!

Type `DIR` to list files. The included utilities are:

| Command | Description |
|---------|-------------|
| `DIR` | List files |
| `TYPE filename` | Print a file |
| `COPY src dst` | Copy files |
| `LS` | Unix-style directory listing |
| `STAT` | Disk statistics |
| `ASM` | 6502 assembler |
| `DUMP` | Hex dump |
| `MKFS` | Create a new filesystem |
| `SYS` | System info |
| `CPUINFO` | CPU/hardware info |

---

## B: drive (optional — copy files between drives)

You can add a second drive (`B:`) by placing a second CP/M filesystem image named `CPMFSB` on the
same flash drive (or on a second USB device if your hub supports it).

### Create a blank B: drive image

```bash
python3 tools/mkblankfs.py          # creates CPMFSB (1MB)
```

Copy `CPMFSB` to the flash drive alongside `CPMFS`.

From CP/M you can then copy files between drives:

```
A> COPY B:MYFILE.COM=A:MYFILE.COM
A> B:
B> DIR
```

B: is detected lazily — if the file isn't present at boot, CP/M will try again the next time you
access `B:`, so you can add it without rebooting.

> **B: drive capacity:** 1MB, 128 directory entries. Use `tools/mkblankfs.py --drive a` to create a
> fresh 8MB A: image instead.

---

## USB serial terminal (VCP0)

If you connect a second USB serial adapter to the RP6502 hub, CP/M console I/O is automatically
mirrored to it. This lets you use a modern terminal emulator (e.g. PuTTY, minicom, screen) at
the same time as the RP6502's own display/keyboard.

No configuration needed — the BIOS opens `VCP0:` at startup and silently skips it if not present.

---

## Building from source

If you want to modify the BIOS or rebuild the ROM from scratch you need the full
[cpm65](https://github.com/davidgiven/cpm65) source tree and the
[llvm-mos](https://github.com/llvm-mos/llvm-mos-sdk) toolchain.

```bash
git clone https://github.com/davidgiven/cpm65
cd cpm65
# install llvm-mos per https://github.com/llvm-mos/llvm-mos-sdk#getting-started
make src/arch/rp6502+rom
make src/arch/rp6502+cpmfs
```

The RP6502 BIOS source files in this repo (`source/`) are the ones submitted to the cpm65 project:

| File | Description |
|------|-------------|
| `source/rp6502.S` | BIOS — console, disk I/O, VCP0 mirroring |
| `source/rp6502.ld` | Linker script — BIOS at `$D000`, BDOS at `$E800` |
| `source/build.py` | Build rules for the cpm65 build system |
| `tools/mkrp6502rom.py` | Standalone ROM packager (used by the build) |

### ROM packaging (standalone)

If you already have BIOS and BDOS binaries you can repackage them without the full build system:

```bash
python3 tools/mkrp6502rom.py bios.bin 0xd000 bdos.bin 0xe800 CPM65.RP6
```

---

## Disk geometry

| Drive | File | Sectors | Block size | Directory entries | Total |
|-------|------|---------|------------|-------------------|-------|
| A: | `CPMFS` | 65536 × 128B | 4096B | 1024 | 8MB |
| B: | `CPMFSB` | 8192 × 128B | 4096B | 128 | 1MB |

The matching `diskdefs` entries (for use with `mkcpmfs` / `cpmtools`) are:

```
diskdef rp6502
    seclen 128
    tracks 512
    sectrk 128
    blocksize 4096
    maxdir 1024
    boottrk 0
    os 2.2
end

diskdef rp6502b
    seclen 128
    tracks 64
    sectrk 128
    blocksize 4096
    maxdir 128
    boottrk 0
    os 2.2
end
```

---

## Credits

- **[CP/M-65](https://github.com/davidgiven/cpm65)** by David Given — the underlying CP/M
  implementation for 65xx processors. BDOS, CCP, and all applications are from this project.
- **[RP6502 Picocomputer](https://picocomputer.github.io/)** by Rumbledethumps — the hardware
  platform and firmware this BIOS targets.
- **[llvm-mos](https://github.com/llvm-mos/llvm-mos-sdk)** — the 6502 LLVM toolchain used to
  build the BIOS.

This port is licensed under the same terms as cpm65: the
[2-clause BSD license](https://opensource.org/licenses/BSD-2-Clause).
