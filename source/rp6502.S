; CP/M-65 Copyright © 2022 David Given
; This file is licensed under the terms of the 2-clause BSD license. Please
; see the COPYING file in the root project directory for the full text.
;
; CP/M-65 BIOS for the RP6502 Picocomputer

#include "zif.inc"
#include "cpm65.inc"
#include "driver.inc"

; RIA register addresses
RIA_READY   = $FFE0     ; bit 7 = TX FIFO not full; bit 6 = RX FIFO has data
RIA_TX      = $FFE1     ; UART transmit
RIA_RX      = $FFE2     ; UART receive
RIA_XSTACK  = $FFEC     ; extended stack (push/pop)
RIA_OP      = $FFEF     ; OS operation trigger
RIA_SPIN    = $FFF1     ; JSR here to spin-wait for OS op
RIA_A       = $FFF4     ; A register result / last argument
RIA_X       = $FFF6     ; X register (high byte of 16-bit args)

; OS operation codes
OP_OPEN         = $14
OP_READ_XSTACK  = $16
OP_WRITE_XSTACK = $18
OP_LSEEK_LLVM   = $1D

; RP6502 open flags (not standard POSIX: O_RDONLY=1, O_WRONLY=2, O_RDWR=3)
FIOMODE_RDONLY  = 1
FIOMODE_RDWR    = 3

; BDOS load address (must be above end of BIOS code)
MEMBASE = $E800

ZEROPAGE

.global ptr
.global ptr1
ptr:            .word 0
ptr1:           .word 0
dma:            .word 0         ; current DMA address

; --- Startup code ----------------------------------------------------------

zproc _start
    jmp cold_start
zendproc

zproc cold_start
    ldx #$ff
    txs
    cld

    jsr open_disk
    bcs disk_error

    lda disk_fd
    sta active_fd
    lda #$ff
    sta disk_fd_b

    jsr init_system

    ; Relocate the BDOS (already loaded at MEMBASE by the ROM loader).
    lda #>MEMBASE
    ldx zp_base
    jsr bios_RELOCATE

    ; Jump to BDOS startup, passing the BIOS entry address in A/X.
    lda #>MEMBASE
    pha
    lda #COMHDR_ENTRY-1
    pha
    lda #<biosentry
    ldx #>biosentry
    rts                 ; indirect jump to BDOS startup

disk_error:
    ldy #0
disk_err_loop:
    lda disk_err_msg, y
    beq disk_err_hang
    pha
    zrepeat
        bit RIA_READY
    zuntil mi
    pla
    sta RIA_TX
    iny
    bne disk_err_loop
disk_err_hang:
    jmp disk_err_hang
zendproc

; --- Disk file open --------------------------------------------------------

zproc open_disk
    ; Push "CPMFS\0" onto xstack last-byte-first so firmware reads it forward.
    ldy #(disk_filename_end - disk_filename) - 1
    zrepeat
        lda disk_filename, y
        sta RIA_XSTACK
        dey
    zuntil mi

    lda #0
    sta RIA_X
    lda #FIOMODE_RDWR
    sta RIA_A
    lda #OP_OPEN
    sta RIA_OP
    jsr RIA_SPIN        ; A = fd, or negative on error

    bpl open_disk_ok
    sec
    rts

open_disk_ok:
    sta disk_fd
    clc
    rts
zendproc

; --- Disk B: file open (lazy, hot-plug) ------------------------------------

; Open "CPMFSB" on the boot device as B:. Returns carry clear on success
; (disk_fd_b and active_fd set), carry set if not found.
zproc open_disk_b
    ldy #(disk_b_filename_end - disk_b_filename) - 1
    zrepeat
        lda disk_b_filename, y
        sta RIA_XSTACK
        dey
    zuntil mi

    lda #0
    sta RIA_X
    lda #FIOMODE_RDWR
    sta RIA_A
    lda #OP_OPEN
    sta RIA_OP
    jsr RIA_SPIN
    bmi open_disk_b_fail

    sta disk_fd_b
    sta active_fd
    clc
    rts

open_disk_b_fail:
    sec
    rts
zendproc

; --- VCP0 open (USB serial terminal mirroring) -----------------------------

; Try to open "VCP0:" for read+write. Sets vcp_fd = $FF if not available.
zproc open_vcp
    lda #$ff
    sta vcp_fd

    ldy #(vcp_filename_end - vcp_filename) - 1
    zrepeat
        lda vcp_filename, y
        sta RIA_XSTACK
        dey
    zuntil mi

    lda #0
    sta RIA_X
    lda #FIOMODE_RDWR
    sta RIA_A
    lda #OP_OPEN
    sta RIA_OP
    jsr RIA_SPIN        ; A = fd, or negative if no terminal connected

    bmi vcp_not_present
    sta vcp_fd
vcp_not_present:
    rts
zendproc

; --- Initialisation --------------------------------------------------------

zproc init_system
    lda #0
    sta pending_key
    jsr initdrivers
    jsr open_vcp

    ; Print startup banner via TTY (mirrors to VCP0 if connected).
    ldy #0
    zloop
        lda banner_msg, y
        zbreakif eq
        jsr tty_conout
        iny
    zendloop
    rts
zendproc

; --- Driver table ----------------------------------------------------------

.data
.global drvtop
drvtop: .word drv_TTY

defdriver TTY, DRVID_TTY, drvstrat_TTY, 0

; TTY driver strategy routine. Y = opcode.
zproc drvstrat_TTY
    pha
    lda tty_jmptable_lo, y
    sta ptr+0
    lda tty_jmptable_hi, y
    sta ptr+1
    pla
    jmp (ptr)

tty_jmptable_lo:
    .byte tty_const@mos16lo
    .byte tty_conin@mos16lo
    .byte tty_conout@mos16lo
tty_jmptable_hi:
    .byte tty_const@mos16hi
    .byte tty_conin@mos16hi
    .byte tty_conout@mos16hi
zendproc

; --- Console I/O -----------------------------------------------------------

; Check for a pending keypress (non-blocking). Returns $FF/carry-clear if
; available, $00/carry-clear if not.
zproc tty_const
    lda pending_key
    zif ne
        lda #$FF
        clc
        rts
    zendif

    ; Check primary UART.
    bit RIA_READY
    bvc tty_const_chk_vcp   ; bit 6 clear = no UART data, try VCP

    lda RIA_RX
    sta pending_key
    lda #$FF
    clc
    rts

tty_const_chk_vcp:
    ; Check VCP0 if connected.
    lda vcp_fd
    cmp #$ff
    beq tty_const_empty

    ; Non-blocking read of 1 byte from VCP0.
    lda #0
    sta RIA_XSTACK          ; count high byte
    lda #1
    sta RIA_XSTACK          ; count low byte
    lda #0
    sta RIA_X
    lda vcp_fd
    sta RIA_A
    lda #OP_READ_XSTACK
    sta RIA_OP
    jsr RIA_SPIN            ; A = bytes read: 1=got byte, 0=empty, neg=error

    bmi tty_const_vcp_err   ; error: disconnect VCP
    cmp #1
    bne tty_const_empty     ; 0 = no data

    lda RIA_XSTACK          ; pop the received byte
    sta pending_key
    lda #$FF
    clc
    rts

tty_const_vcp_err:
    lda #$ff
    sta vcp_fd

tty_const_empty:
    lda #0
    clc
    rts
zendproc

; Wait for a keypress and return it in A.
zproc tty_conin
    lda pending_key
    zif ne
        ldx #0
        stx pending_key
        clc
        rts
    zendif

tty_conin_poll:
    ; Check primary UART.
    bit RIA_READY
    bvc tty_conin_chk_vcp
    lda RIA_RX
    clc
    rts

tty_conin_chk_vcp:
    ; If VCP not connected, spin on UART.
    lda vcp_fd
    cmp #$ff
    beq tty_conin_poll

    ; Non-blocking read of 1 byte from VCP0.
    lda #0
    sta RIA_XSTACK
    lda #1
    sta RIA_XSTACK
    lda #0
    sta RIA_X
    lda vcp_fd
    sta RIA_A
    lda #OP_READ_XSTACK
    sta RIA_OP
    jsr RIA_SPIN

    bmi tty_conin_vcp_err   ; error: disconnect VCP
    cmp #1
    bne tty_conin_poll      ; 0 = no data, keep polling

    lda RIA_XSTACK          ; pop received byte
    clc
    rts

tty_conin_vcp_err:
    lda #$ff
    sta vcp_fd
    bne tty_conin_poll      ; A=$FF != 0, always branches
zendproc

; Write character in A to the console, mirroring to VCP0 if connected.
zproc tty_conout
    sta vcp_char            ; save char (sta does not modify A)

    zrepeat
        bit RIA_READY
    zuntil mi               ; wait until TX FIFO not full
    sta RIA_TX              ; A = original char (bit does not modify A)

    ; Mirror to VCP0 if connected.
    lda vcp_fd
    cmp #$ff
    beq tty_conout_done

    lda vcp_char
    sta RIA_XSTACK          ; push char as write payload
    lda #0
    sta RIA_X
    lda vcp_fd
    sta RIA_A
    lda #OP_WRITE_XSTACK
    sta RIA_OP
    jsr RIA_SPIN

    bpl tty_conout_done     ; >= 0 = success
    lda #$ff
    sta vcp_fd              ; error: mark VCP disconnected

tty_conout_done:
    clc
    rts
zendproc

; --- BIOS disk functions ---------------------------------------------------

; Select drive. A = drive number (0 = A:, 1 = B:).
zproc bios_SELDSK
    cmp #0
    zif eq
        lda disk_fd
        sta active_fd
        lda #<dph
        ldx #>dph
        clc
        rts
    zendif
    cmp #1
    zif ne
        sec
        rts
    zendif
    ; Drive B: lazy open / hot-plug re-detect.
    lda disk_fd_b
    cmp #$ff
    zif eq
        jsr open_disk_b
        bcs seldsk_b_fail
    zelse
        sta active_fd
    zendif
    lda #<dph_b
    ldx #>dph_b
    clc
    rts
seldsk_b_fail:
    sec
    rts
zendproc

; Set current sector. XA = pointer to 3-byte sector number.
zproc bios_SETSEC
    sta ptr+0
    stx ptr+1
    ldy #2
    zrepeat
        lda (ptr), y
        sta sector_num, y
        dey
    zuntil mi
    clc
    rts
zendproc

; Set DMA (data transfer) address. XA = address.
zproc bios_SETDMA
    sta dma+0
    stx dma+1
    clc
    rts
zendproc

; Compute 4-byte file offset = sector_num * 128, stored in offset[0..3].
; Uses right-shift of sector_num with carry chain for the left-shift-by-7.
zproc compute_offset
    lda sector_num+2
    lsr a
    sta offset+3
    lda sector_num+1
    ror a
    sta offset+2
    lda sector_num+0
    ror a
    sta offset+1
    lda #0
    ror a
    sta offset+0
    rts
zendproc

; Seek to sector_num * 128 in the disk file.
zproc do_lseek
    jsr compute_offset

    lda offset+3
    sta RIA_XSTACK
    lda offset+2
    sta RIA_XSTACK
    lda offset+1
    sta RIA_XSTACK
    lda offset+0
    sta RIA_XSTACK
    lda #0              ; SEEK_SET
    sta RIA_XSTACK

    lda #0
    sta RIA_X
    lda active_fd
    sta RIA_A
    lda #OP_LSEEK_LLVM
    sta RIA_OP
    jsr RIA_SPIN
    rts
zendproc

; Read 128 bytes from disk into DMA buffer.
zproc bios_READ
    jsr do_lseek

    ; Push count = 128 ($0080): MSB first so LSB ends up on top of stack.
    lda #>128
    sta RIA_XSTACK
    lda #<128
    sta RIA_XSTACK

    lda #0
    sta RIA_X
    lda active_fd
    sta RIA_A
    lda #OP_READ_XSTACK
    sta RIA_OP
    jsr RIA_SPIN        ; A = bytes read, or negative on error

    cmp #128
    bne bios_READ_error

    ; Pop 128 bytes from xstack into DMA buffer (byte[0] is at top).
    ldy #0
    zrepeat
        lda RIA_XSTACK
        sta (dma), y
        iny
        cpy #128
    zuntil eq
    clc
    rts

bios_READ_error:
    sec
    rts
zendproc

; Write 128 bytes from DMA buffer to disk.
; A = 0 for normal write, 1 to flush (flush is a no-op; firmware handles it).
zproc bios_WRITE
    jsr do_lseek

    ; Push 128 bytes in reverse order so byte[0] ends up on top.
    ldy #127
    zrepeat
        lda (dma), y
        sta RIA_XSTACK
        dey
    zuntil mi

    lda #0
    sta RIA_X
    lda active_fd
    sta RIA_A
    lda #OP_WRITE_XSTACK
    sta RIA_OP
    jsr RIA_SPIN        ; A = bytes written, or negative on error

    cmp #128
    bne bios_WRITE_error
    clc
    rts

bios_WRITE_error:
    sec
    rts
zendproc

; --- BIOS memory functions -------------------------------------------------

zproc bios_GETTPA
    lda mem_base
    ldx mem_end
    clc
    rts
zendproc

zproc bios_SETTPA
    sta mem_base
    stx mem_end
    clc
    rts
zendproc

zproc bios_GETZP
    lda zp_base
    ldx zp_end
    clc
    rts
zendproc

zproc bios_SETZP
    sta zp_base
    stx zp_end
    clc
    rts
zendproc

zproc bios_SETBANK
    clc
    rts
zendproc

; --- Static data -----------------------------------------------------------

.data

zp_base:    .byte __USERZEROPAGE_START__
zp_end:     .byte __USERZEROPAGE_END__
mem_base:   .byte $02
mem_end:    .byte >MEMBASE

banner_msg:
    .byte 13, 10
    .ascii "CP/M-65 for the RP6502 Picocomputer"
    .byte 13, 10, 0

disk_filename:
    .ascii "CPMFS"
    .byte 0
disk_filename_end:

vcp_filename:
    .ascii "VCP0:"
    .byte 0
vcp_filename_end:

disk_b_filename:
    .ascii "CPMFSB"
    .byte 0
disk_b_filename_end:

disk_err_msg:
    .ascii "Cannot open CPMFS"
    .byte 13, 10, 0

; A: drive: 8MB, 4KB blocks, 1024 dirents. B: drive: 1MB, 4KB blocks, 128 dirents.
; define_dph ends with NOINIT so place these last in the .data section.
define_dpb dpb,   65536, 4096, 1024, 0
define_dpb dpb_b,  8192, 4096,  128, 0
define_dph dph,   dpb
define_dph dph_b, dpb_b

; --- Uninitialised data ----------------------------------------------------
; (define_dph already switched us to .noinit; keep remaining BSS here)

pending_key:    .fill 1
disk_fd:        .fill 1
disk_fd_b:      .fill 1     ; $FF = B: not open
active_fd:      .fill 1     ; fd for currently selected drive
vcp_fd:         .fill 1     ; $FF = no VCP terminal connected
vcp_char:       .fill 1     ; temporary for tty_conout VCP mirror
sector_num:     .fill 3     ; 24-bit sector number from bios_SETSEC
offset:         .fill 4     ; temporary for lseek offset computation

.global directory_buffer
directory_buffer: .fill 128

; vim: sw=4 ts=4 et ft=asm
