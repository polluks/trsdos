#!/bin/bash
# Build TRSDOS C128 SYSRES from MRAS source via vasm
# Handles MRAS->vasm conversion for all included files

export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRSDOS_DIR="$(dirname "$SCRIPT_DIR")"
CONV_DIR="$SCRIPT_DIR"
PORT_DIR="$TRSDOS_DIR/port/c128"
REPO_DIR="$TRSDOS_DIR/repo/LSDOS631L/lsdos631"
OUT_DIR="$TRSDOS_DIR/build/sysres"
TMP_DIR="$TRSDOS_DIR/tmp_conv"
VASM="/usr/local/bin/vasmz80_oldstyle"

mkdir -p "$OUT_DIR" "$TMP_DIR"

REPO_FILES="dosdefs muldiv filposn loader tasker sound"
PORT_FILES="c128_equ c128_boot c128_iodvr c128_clocks c128_kidvr c128_dodvr c128_prdvr c128_fdcdvr c128_sysinit c128_lowcore"

echo "=== Converting source files ==="

for f in $REPO_FILES; do
    [ -f "$REPO_DIR/${f}.asm" ] || { echo "  SKIP repo/$f (not found)"; continue; }
    echo -n "  repo/$f ... "
    perl "$CONV_DIR/mras2vasm.pl" "$REPO_DIR/${f}.asm" "$TMP_DIR/${f}.asm" 2>/dev/null
    echo "done"
done

for f in $PORT_FILES; do
    [ -f "$PORT_DIR/${f}.asm" ] || { echo "  SKIP port/$f (not found)"; continue; }
    echo -n "  port/$f ... "
    perl "$CONV_DIR/mras2vasm.pl" "$PORT_DIR/${f}.asm" "$TMP_DIR/${f}.asm" 2>/dev/null
    echo "done"
done

echo -n "  c128_sysres ... "
perl "$CONV_DIR/mras2vasm.pl" "$PORT_DIR/c128_sysres.asm" "$TMP_DIR/c128_sysres_vasm.asm" 2>/dev/null
echo "done"

echo ""
echo "=== Post-processing fixes ==="

# Fix macro params in c128_dodvr and c128_equ
for f in c128_dodvr c128_equ; do
    echo -n "  Macro params in $f ... "
    perl -i -pe '
        if (/^VDC_SET:\s*MACRO/) { $in=1; next }
        if (/^VDC_SEL:\s*MACRO/) { $in=2; next }
        if (/^\s*ENDM\b/) { $in=0 }
        if ($in==1) { s/\bREG\b/\\1/g; s/\bVAL\b/\\2/g }
        if ($in==2) { s/\bREG\b/\\1/g }
    ' "$TMP_DIR/${f}.asm"
    echo "done"
done

# ORG SVCTAB_S -> ORG 0100H (fixed address in LSDOS memory map)
echo -n "  ORG SVCTAB_S ... "
sed -i 's/^[[:space:]]*ORG[[:space:]]\+SVCTAB_S\b/	ORG	0100H/' "$TMP_DIR/loader.asm"
echo "done"

# ORG CORE_LDR -> comment (no-op)
echo -n "  ORG CORE_LDR ... "
sed -i 's/^[[:space:]]*ORG[[:space:]]\+CORE_LDR\b/	; ORG CORE_LDR/' "$TMP_DIR/loader.asm"
echo "done"

# ORG ...+START_S -> ORG (START$=0, just remove +START_S)
echo -n "  ORG +START_S ... "
sed -i 's/\([[:space:]]ORG[[:space:]]\+[^+]*\)+START_S/\1/' "$TMP_DIR/c128_sysinit.asm"
echo "done"

# ORG 1E00H -> comment (section overlap with SBUFF_S area ending at 1E38)
echo -n "  ORG 1E00H ... "
sed -i 's/^[[:space:]]*ORG[[:space:]]*1E00H/	; ORG 1E00H - removed to avoid section overlap/' "$TMP_DIR/c128_sysinit.asm"
echo "done"

# Remove duplicate macros from c128_dodvr (they're in c128_equ)
echo -n "  Remove duplicate macros ... "
perl -i -pe 'if (/^VDC_SET:\s*MACRO/.../^\s*ENDM\b/) { $_ = "" }' "$TMP_DIR/c128_dodvr.asm"
perl -i -pe 'if (/^VDC_SEL:\s*MACRO/.../^\s*ENDM\b/) { $_ = "" }' "$TMP_DIR/c128_dodvr.asm"
echo "done"

# Fix GETADR conflict - rename in c128_boot
echo -n "  Rename GETADR in c128_boot ... "
sed -i 's/\bGETADR\b/GETADR_BOOT/g' "$TMP_DIR/c128_boot.asm"
sed -i 's/\bLBOOT\b/LBOOT_BOOT/g' "$TMP_DIR/c128_boot.asm"
echo "done"

# Remove label-based ORG statements from included files
# These use non-constant label expressions that vasm can't resolve
echo -n "  Fix ORG in tasker.asm ... "
sed -i 's/^[[:space:]]*ORG[[:space:]]\+TCB_S\b/	; ORG TCB_S - removed for vasm/' "$TMP_DIR/tasker.asm"
sed -i 's/^[[:space:]]*ORG[[:space:]]\+CORE_TSK\b/	; ORG CORE_TSK - removed for vasm/' "$TMP_DIR/tasker.asm"
echo "done"

echo -n "  Fix ORG in sound.asm ... "
sed -i 's/^[[:space:]]*ORG[[:space:]]\+STACK_S\b/	; ORG STACK_S - removed for vasm/' "$TMP_DIR/sound.asm"
echo "done"

echo -n "  Fix ORG in sysres (CORE_S) ... "
sed -i 's/^[[:space:]]*ORG[[:space:]]\+CORE_S\b/	; ORG CORE_S - removed for vasm/' "$TMP_DIR/c128_sysres_vasm.asm"
# Fix CORE_S redefinition (DEFL used twice; vasm doesn't allow redef)
# Two CORE_S DEFL lines: keep first (change to EQU), comment out second
# Match the CORE_S DEFL that precedes "DC.*1D00H-CORE" (the redefinition)
echo -n "  Fix CORE_S redefinition ... "
sed -i '0,/^CORE_S[[:space:]]*DEFL/{s/^CORE_S\([[:space:]]*\)DEFL\([[:space:]]*\)$/CORE_S\1EQU\2$/}' "$TMP_DIR/c128_sysres_vasm.asm"
# Now there's only one remaining CORE_S DEFL (the redef) - match it
sed -i '/^CORE_S[[:space:]]*DEFL/{s/^/; /}' "$TMP_DIR/c128_sysres_vasm.asm"
# Fix the DC line to use $ instead of CORE_S
sed -i 's/^[[:space:]]*DC[[:space:]]*1D00H-CORE_S,0/	DS	1D00H+START_S-$,0/' "$TMP_DIR/c128_sysres_vasm.asm"
echo "done"

# Fix ? labels (MRAS allows ? in labels, vasm does not)
# Note: \b after ? doesn't match between ? (non-word) and tab (non-word)
# Note: use plain ? not \? in basic sed (\? = preceding char optional in GNU sed)
echo -n "  Fix BREAK? in tasker.asm ... "
sed -i 's/BREAK?/BREAK_Q/g' "$TMP_DIR/tasker.asm"
echo "done"

echo -n "  Fix AUTO? in c128_sysinit.asm ... "
sed -i 's/AUTO?/AUTO_Q/g' "$TMP_DIR/c128_sysinit.asm"
echo "done"

# Convert JR to JP where distance exceeds range (common issue when porting)
# Replace JR mnemonic with JP (safe: JP works everywhere JR does, just 1 byte larger)
echo -n "  Convert JR to JP for long jumps ... "
for f in "$TMP_DIR"/*.asm; do
    # Replace JR (whole word) at mnemonic position: after whitespace or label+whitespace
    # Pattern: optional label at line start, then whitespace, then JR, then whitespace/comma
    sed -i 's/^\([[:space:]]*\)JR\([[:space:],]\)/\1JP\2/' "$f"
    sed -i 's/^\([A-Za-z_][A-Za-z0-9_]*[[:space:]]\+\)JR\([[:space:],]\)/\1JP\2/' "$f"
done
echo "done"

# Fix 8-bit wrap expressions that are negative
echo -n "  Fix 8-bit wrap in sound.asm ... "
sed -i 's/\b0-SNDOFF\b/(0-SNDOFF)\&0FFH/g' "$TMP_DIR/sound.asm"
echo "done"

# Fix 8-bit overflow: VDC_COLS*(VDC_ROWS-1) = 1920 > 255 in LD A
echo -n "  Fix VDC 8-bit overflow in c128_dodvr.asm ... "
perl -i -pe 's{^\s*LD\s+A,\s*VDC_COLS\s*\*\s*\(VDC_ROWS-1\)}{	; LD A,VDC_COLS*(VDC_ROWS-1) - value reused from HL}' "$TMP_DIR/c128_dodvr.asm"
echo "done"

# Add missing C128 port-specific EQU definitions
echo -n "  Add missing EQU definitions ... "
cat >> "$TMP_DIR/c128_equ.asm" << 'C128EQUEOF'

; C128 port-specific hardware equates
TRKREG	EQU	0F1H		;FDC track register (Model 4 compat)
BOOTST_S	EQU	43H		;Boot step rate (Model 4 compat)
_OPREG	EQU	0E4H		;Memory management port (Model 4 compat)
C128EQUEOF
echo "done"

# Add _RSTNMI stub to fdcdvr if not present
echo -n "  Add _RSTNMI stub ... "
grep -q '_RSTNMI:' "$TMP_DIR/c128_fdcdvr.asm" || \
    echo -e "\n; C128 NMI stub (was @RSTNMI in Model 4 FDC driver)\n_RSTNMI:\n\tRET" >> "$TMP_DIR/c128_fdcdvr.asm"
echo "done"

# Add FDCRET stub to fdcdvr (referenced by DCT entries for non-present drives)
echo -n "  Add FDCRET stub ... "
grep -q 'FDCRET:' "$TMP_DIR/c128_fdcdvr.asm" || \
    echo -e "\n; FDCRET - return stub for non-present drives\nFDCRET:\n\tRET" >> "$TMP_DIR/c128_fdcdvr.asm"
echo "done"

# Add NMIRET stub to c128_boot (referenced by boot code, defined in boot4.asm)
echo -n "  Add NMIRET stub ... "
grep -q 'NMIRET:' "$TMP_DIR/c128_boot.asm" || \
    echo -e "\n; NMIRET - NMI return stub for boot code\nNMIRET:\n\tPOP\tDE\n\tPOP\tDE\n\tXOR\tA\n\tOUT\t(0E4H),A\n\tRET" >> "$TMP_DIR/c128_boot.asm"
echo "done"

# Add DISKEI label to c128_fdcdvr (referenced by boot code)
echo -n "  Add DISKEI label ... "
grep -q 'DISKEI:' "$TMP_DIR/c128_fdcdvr.asm" || \
    echo -e "\nDISKEI:\n\tNOP" >> "$TMP_DIR/c128_fdcdvr.asm"
echo "done"

# Fix section overlap: ORG 0036H at end conflicts with ORG 0 section
echo -n "  Fix ORG 0036H overlap ... "
sed -i 's/^[[:space:]]*ORG[[:space:]]*0036H/; ORG 0036H - removed to avoid section overlap/' "$TMP_DIR/c128_sysres_vasm.asm"
sed -i '/; ORG 0036H - removed/{n;s/^[[:space:]]*DB[[:space:]]*0/; DB 0/;}' "$TMP_DIR/c128_sysres_vasm.asm"
echo "done"

echo ""
echo "=== Assembling c128_sysres ==="

$VASM -Fbin -L "$OUT_DIR/sysres.lst" -o "$OUT_DIR/sysres.bin" \
    -I"$TMP_DIR" -I"$PORT_DIR" -I"$REPO_DIR" \
    "$TMP_DIR/c128_sysres_vasm.asm" 2>&1 | tee "$OUT_DIR/vasm_errors.txt"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo "=== SUCCESS ==="
    ls -la "$OUT_DIR/sysres.bin"
    exit 0
else
    echo ""
    echo "=== FAILED (see $OUT_DIR/vasm_errors.txt for details) ==="
    echo "=== Showing first 30 lines of errors ==="
    head -30 "$OUT_DIR/vasm_errors.txt"
    exit 1
fi
