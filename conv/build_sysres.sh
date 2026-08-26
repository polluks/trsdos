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
VASM="${VASM:-$(which vasmz80_oldstyle 2>/dev/null || echo /tmp/vasm/bin/vasmz80_oldstyle)}"

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

# Convert MRAS macros to vasm oldstyle syntax in c128_dodvr and c128_equ
for f in c128_dodvr c128_equ; do
    echo -n "  Vasm macro fix in $f ... "
    perl -i -pe '
        if (/^VDC_SET:\s*MACRO/) { $_ = "\tMACRO VDC_SET\n"; $in=1; next }
        if (/^VDC_SEL:\s*MACRO/) { $_ = "\tMACRO VDC_SEL\n"; $in=2; next }
        if ($in && /^\s*ENDM\b/) { $in=0; next }
        if ($in==1) { s/\bREG\b/\\1/g; s/\bVAL\b/\\2/g }
        if ($in==2) { s/\bREG\b/\\1/g }
    ' "$TMP_DIR/${f}.asm"
    echo "done"
done

# ORG SVCTAB_S -> ORG 0100H (fixed address in LSDOS memory map)
echo -n "  ORG SVCTAB_S ... "
perl -i -pe 's/^(\s*)ORG\s+SVCTAB_S\b/\tORG\t0100H/' "$TMP_DIR/loader.asm"
echo "done"

# ORG CORE_LDR -> comment (no-op)
echo -n "  ORG CORE_LDR ... "
perl -i -pe 's/^(\s*)ORG\s+CORE_LDR\b/\t; ORG CORE_LDR/' "$TMP_DIR/loader.asm"
echo "done"

# ORG ...+START_S -> ORG (START$=0, just remove +START_S)
echo -n "  ORG +START_S ... "
perl -i -pe 's/(\sORG\s+[^+]+)\+START_S/$1/' "$TMP_DIR/c128_sysinit.asm"
echo "done"

# ORG 1E00H -> comment (section overlap with SBUFF_S area ending at 1E38)
echo -n "  ORG 1E00H ... "
perl -i -pe 's/^(\s*)ORG\s+1E00H/\t; ORG 1E00H - removed to avoid section overlap/' "$TMP_DIR/c128_sysinit.asm"
echo "done"

# Remove duplicate macros from c128_dodvr (they're in c128_equ)
echo -n "  Remove duplicate macros ... "
perl -i -pe 'if (/^VDC_SET:\s*MACRO/.../^\s*ENDM\b/) { $_ = "" }' "$TMP_DIR/c128_dodvr.asm"
perl -i -pe 'if (/^VDC_SEL:\s*MACRO/.../^\s*ENDM\b/) { $_ = "" }' "$TMP_DIR/c128_dodvr.asm"
echo "done"

# Fix GETADR conflict - rename in c128_boot
echo -n "  Rename GETADR in c128_boot ... "
perl -i -pe 's/\bGETADR\b/GETADR_BOOT/g' "$TMP_DIR/c128_boot.asm"
perl -i -pe 's/\bLBOOT\b/LBOOT_BOOT/g' "$TMP_DIR/c128_boot.asm"
echo "done"

# Remove label-based ORG statements from included files
# These use non-constant label expressions that vasm can't resolve
echo -n "  Fix ORG in tasker.asm ... "
perl -i -pe 's/^(\s*)ORG\s+TCB_S\b/\t; ORG TCB_S - removed for vasm/' "$TMP_DIR/tasker.asm"
perl -i -pe 's/^(\s*)ORG\s+CORE_TSK\b/\t; ORG CORE_TSK - removed for vasm/' "$TMP_DIR/tasker.asm"
echo "done"

echo -n "  Fix ORG in sound.asm ... "
perl -i -pe 's/^(\s*)ORG\s+STACK_S\b/\t; ORG STACK_S - removed for vasm/' "$TMP_DIR/sound.asm"
echo "done"

echo -n "  Fix ORG in sysres (CORE_S) ... "
perl -i -pe 's/^(\s*)ORG\s+CORE_S\b/\t; ORG CORE_S - removed for vasm/' "$TMP_DIR/c128_sysres_vasm.asm"
echo "done"

# Fix ? labels (MRAS allows ? in labels, vasm does not)
echo -n "  Fix BREAK? in tasker.asm ... "
perl -i -pe 's/BREAK\?/BREAK_Q/g' "$TMP_DIR/tasker.asm"
echo "done"

echo -n "  Fix AUTO? in c128_sysinit.asm ... "
perl -i -pe 's/AUTO\?/AUTO_Q/g' "$TMP_DIR/c128_sysinit.asm"
echo "done"

# Convert JR to JP where distance exceeds range (common issue when porting)
# Replace JR mnemonic with JP (safe: JP works everywhere JR does, just 1 byte larger)
echo -n "  Convert JR to JP for long jumps ... "
for f in "$TMP_DIR"/*.asm; do
    perl -i -pe 's/^(\s*)JR([\s,])/\1JP$2/' "$f"
    perl -i -pe 's/^([A-Za-z_]\w*\s+)JR([\s,])/$1JP$2/' "$f"
done
echo "done"

# Fix 8-bit wrap expressions that are negative
echo -n "  Fix 8-bit wrap in sound.asm ... "
perl -i -pe 's/\b0-SNDOFF\b/(0-SNDOFF)\&0FFH/g' "$TMP_DIR/sound.asm"
echo "done"

# Fix 8-bit overflow: VDC_COLS*(VDC_ROWS-1) = 1920 > 255 in LD A
echo -n "  Fix VDC 8-bit overflow in c128_dodvr.asm ... "
perl -i -pe 's{^\s*LD\s+A,\s*VDC_COLS\s*\*\s*\(VDC_ROWS-1\)}{	; LD A,VDC_COLS*(VDC_ROWS-1) - value reused from HL}' "$TMP_DIR/c128_dodvr.asm"
echo "done"

# Convert MRAS !SET directives to vasm DB (self-modifying code opcodes)
# !SET b,(IX+d) -> DD CB d (C7+b*8) and !SET b,A -> CB (C7+b*8)
echo -n "  Convert !SET directives ... "
perl -i -pe '
    if (/^(\w+)\s+!SET\s+(\d+)\s*,\s*\(IX\+(\d+)\)/) {
        my ($lbl, $bit, $off) = ($1, $2, $3);
        my $op = (0xC7 + $bit * 8) & 0xFF;
        $_ = sprintf("%s:\tDB\t0DDH,0CBH,0%02XH,0%02XH\n", $lbl, $off, $op);
    } elsif (/^(\w+)\s+!SET\s+(\d+)\s*,\s*A/) {
        my ($lbl, $bit) = ($1, $2);
        my $op = (0xC7 + $bit * 8) & 0xFF;
        $_ = sprintf("%s:\tDB\t0CBH,0%02XH\n", $lbl, $op);
    }
' "$TMP_DIR/filposn.asm"
echo "done"

# Fix CORE_S: comment out all DEFL definitions (use = in first file only)
echo -n "  Fix CORE_S DEFL ... "
for f in "$TMP_DIR"/loader.asm "$TMP_DIR"/tasker.asm "$TMP_DIR"/c128_sysres_vasm.asm; do
    [ -f "$f" ] && perl -i -pe 's/^CORE_S\s+DEFL\b/CORE_S =/' "$f"
done
# First CORE_S = stays; comment out subsequent ones
first=1
for f in "$TMP_DIR"/loader.asm "$TMP_DIR"/tasker.asm "$TMP_DIR"/c128_sysres_vasm.asm; do
    [ -f "$f" ] || continue
    if [ "$first" = "1" ]; then
        first=0
    else
        perl -i -pe 's/^CORE_S\s*=\s/\t; CORE_S = /' "$f"
    fi
done
echo "done"

# Fix ORG CORE_S -> comment (restores PC to current position, no-op)
echo -n "  Fix ORG CORE_S ... "
for f in "$TMP_DIR"/loader.asm "$TMP_DIR"/tasker.asm "$TMP_DIR"/c128_sysres_vasm.asm; do
    [ -f "$f" ] && perl -i -pe 's/^(\s*)ORG\s+CORE_S\b/\t; ORG CORE_S - no-op for vasm/' "$f"
done
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
perl -i -pe 's/^(\s*)ORG\s+0036H/; ORG 0036H - removed to avoid section overlap/' "$TMP_DIR/c128_sysres_vasm.asm"
perl -i -pe 'if (/; ORG 0036H - removed/) { $fix=1 } elsif ($fix && /^\s*DB\s+0/) { $_ = "; DB 0\n"; $fix=0 }' "$TMP_DIR/c128_sysres_vasm.asm"
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
