C128 LSDOS 6.3.1L Port - File Map & Build Guide
=================================================

SOURCE FILE MAP
---------------

Original TRS-80 File           C128 Port Replacement
---------------------          ---------------------
dosdefs.asm                    dosdefs.asm (unchanged)
values.asm                     values.asm (unchanged)
svcmac.asm                     svcmac.asm (unchanged)
copycom.asm                    copycom.asm (unchanged)

lowcore.asm                    c128_lowcore.asm + c128_equ.asm
sysres.asm                     c128_sysres.asm
boot4.asm                      c128_boot.asm
iodvr.asm                      c128_iodvr.asm
kidvr.asm                      c128_kidvr.asm
dodvr.asm                      c128_dodvr.asm
prdvr.asm                      c128_prdvr.asm
fdcdvr.asm                     c128_fdcdvr.asm
clocks.asm                     c128_clocks.asm
sysinit4.asm                   c128_sysinit.asm

-                              c128_equ.asm (C128 hardware definitions)

sound.asm                      sound.asm (mostly usable, needs SID remap)
muldiv.asm                     muldiv.asm (unchanged - generic Z80)
filposn.asm                    filposn.asm (unchanged - OS logic)
loader.asm                     loader.asm (unchanged - OS logic)
tasker.asm                     tasker.asm (unchanged - OS logic)
param.asm                      param.asm (unchanged - OS logic)
sys1.asm - sys13.asm           sys1.asm - sys13.asm (unchanged)
cmdfiles/                      cmdfiles/ (unchanged)
libcmds/                       libcmds/ (unchanged)
utils/                         utils/ (unchanged)

HARDWARE ABSTRACTION LAYER
--------------------------

C128 Hardware      C128 Address    LSDOS Driver   Function
-----------        -------------   -------------  --------
CIA #1             $DC00-$DC0F     c128_kidvr.asm Keyboard matrix scan
                                    c128_clocks.asm TOD clock, NMI

CIA #2             $DD00-$DD0F     c128_fdcdvr.asm IEC serial bus
                                    c128_prdvr.asm  Printer via IEC

VDC 8563           $D600/$D601     c128_dodvr.asm 80x25 text display

SID 6581           $D400-$D41E     sound.asm     Sound (via SID)

MMU                $FF00-$FF05     c128_clocks.asm Bank switching

MEMORY MAP
----------

$0000-$00FF:  Page 0 - RST vectors, system globals
$0100-$01FF:  Page 1 - SVC table
$0200-$02FF:  Page 2 - Device Control Blocks (DCBs)
$0300-$12FF:  I/O Drivers (C128 replacements)
$1300-$1CFF:  SYSRES (BDOS kernel)
$1D00-$1DFF:  Disk sector buffer
$1E00-$3FFF:  SYS1 (command interpreter)
$4000-$7FFF:  User program / TPA
$8000-$BFFF:  Overlay / library area
$C000-$FFFF:  MMU I/O + reserved

BOOT PROCESS
------------

1. C128 powers on in 8502 mode, loads boot sector from disk
2. Boot sector switches to Z80 mode (CP/M-compatible entry)
3. Z80 boot code initializes CIA#2, VDC, MMU
4. Reads LSDOS boot blocks (first 16 sectors) via IEC serial bus
5. Loads LOWCORE + drivers to $0200-$12FF
6. Loads SYSRES to $1300+
7. Jumps to SYSRES initialization
8. SYSRES inits CIA#1 (TOD), VDC (80x25), SID, MMU
9. Prompts for date/time, loads CONFIG/SYS
10. Launches command interpreter (@CMNDR)

ASSEMBLY INSTRUCTIONS
---------------------

Required assembler: MRAS (MISOSYS) or compatible Z80 macro assembler

Main build file: c128_sysres.asm

  MRAS C128_SYSRES -GC -WE -CI

This produces SYS0/SYS (or SYS0.CIM) for the C128.

For the individual subsystem files:

  MRAS C128_DODVR -GC -WE -CI
  MRAS C128_KIDVR -GC -WE -CI
  MRAS C128_FDCDVR -GC -WE -CI
  MRAS C128_CLOCKS -GC -WE -CI
  MRAS C128_PRDVR -GC -WE -CI
  MRAS C128_SYSINIT -GC -WE -CI
  MRAS C128_BOOT -GC -WE -CI

C128-SPECIFIC NOTES
--------------------

1. VDC Video:
   - The VDC is register-based, NOT memory-mapped like TRS-80
   - All screen access goes through ports $D600/$D601
   - The VDC has separate character and attribute memory
   - 80x25 text mode with hardware cursor

2. Keyboard:
   - Scanned via CIA #1 matrix (row select on PA, column read on PB)
   - Key repeat handled in software
   - STOP key maps to BREAK
   - C= key for graphics, SHIFT-LOCK for caps

3. IEC Floppy:
   - Uses bit-banged serial protocol via CIA #2
   - Supports 1571 and 1581 drives (device 8-11)
   - All track/sector access via serial commands (U1/U2)
   - Slower than TRS-80 FDC but supports larger capacity

4. MMU Banking:
   - C128 MMU at $FF00 controls 16K block mapping
   - Bank 0 = all RAM from block 0 (64K)
   - Bank 1 = upper 32K from block 1 (128K systems)
   - Bank 2 = upper 32K from block 1 with I/O visible

5. Timer:
   - CIA #1 TOD clock provides time-of-day
   - CIA #1 NMI provides 50/60 Hz system tick
   - Used for cursor blink, clock display, task scheduling

6. Sound:
   - Original SOUND.ASM uses port 90h
   - For C128, should be remapped to SID ($D400)
   - SID has 3 voices vs TRS-80's single-bit output

TODO / KNOWN ISSUES
--------------------

1. Keyboard scancode table needs exact C128 matrix verification
2. IEC floppy driver needs protocol timing calibration for 2MHz Z80
3. VDC attribute handling needs testing (reverse, blink, underline)
4. 1571 burst mode not yet implemented (only serial mode)
5. MMU banking needs testing with >64K RAM
6. Boot process needs 8502-side bootstrap to enter Z80 mode
7. Sound.asm SNDPORT needs remapping to SID for C128
8. CP/M compatibility layer not yet implemented
9. Some SVC calls reference TRS-80 specific port numbers
