#!/bin/bash
# Build CPC TRSDOS SYSRES - files are already in vasm syntax
# Only repo files need MRAS->vasm conversion

export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRSDOS_DIR="$(dirname "$SCRIPT_DIR")"
CONV_DIR="$SCRIPT_DIR"
PORT_DIR="$TRSDOS_DIR/port/cpc"
REPO_DIR="$TRSDOS_DIR/repo/LSDOS631L/lsdos631"
OUT_DIR="$TRSDOS_DIR/build/sysres"
TMP_DIR="$TRSDOS_DIR/tmp_conv_cpc"
VASM="/usr/local/bin/vasmz80_oldstyle"

mkdir -p "$OUT_DIR" "$TMP_DIR"

REPO_FILES="dosdefs muldiv filposn loader tasker sound"

echo "=== Converting repo source files ==="

for f in $REPO_FILES; do
    [ -f "$REPO_DIR/${f}.asm" ] || { echo "  SKIP repo/$f (not found)"; continue; }
    echo -n "  repo/$f ... "
    perl "$CONV_DIR/mras2vasm.pl" "$REPO_DIR/${f}.asm" "$TMP_DIR/${f}.asm" 2>/dev/null
    echo "done"
done

echo "=== Converting CPC port files (MRAS->vasm conversion) ==="

PORT_FILES="cpc_equ cpc_boot cpc_iodvr cpc_clocks cpc_kidvr cpc_dodvr cpc_prdvr cpc_fdcdvr cpc_sysinit cpc_sysres cpc_lowcore"

for f in $PORT_FILES; do
    [ -f "$PORT_DIR/${f}.asm" ] || { echo "  SKIP port/$f (not found)"; continue; }
    echo -n "  port/$f ... "
    perl "$CONV_DIR/mras2vasm.pl" "$PORT_DIR/${f}.asm" "$TMP_DIR/${f}.asm" 2>/dev/null
    echo "done"
done

echo ""
echo "=== Post-processing fixes ==="

# ORG SVCTAB_S -> ORG 0100H
echo -n "  ORG SVCTAB_S ... "
sed -i 's/^[[:space:]]*ORG[[:space:]]\+SVCTAB_S\b/	ORG	0100H/' "$TMP_DIR/loader.asm"
echo "done"

# ORG CORE_LDR -> comment
echo -n "  ORG CORE_LDR ... "
sed -i 's/^[[:space:]]*ORG[[:space:]]\+CORE_LDR\b/	; ORG CORE_LDR/' "$TMP_DIR/loader.asm"
echo "done"

# ORG ...+START_S -> ORG (START$=0)
echo -n "  ORG +START_S ... "
sed -i 's/\([[:space:]]ORG[[:space:]]\+[^+]*\)+START_S/\1/' "$TMP_DIR/cpc_sysinit.asm"
echo "done"

# ORG 1E00H -> comment
echo -n "  ORG 1E00H ... "
sed -i 's/^[[:space:]]*ORG[[:space:]]*1E00H/	; ORG 1E00H - removed to avoid section overlap/' "$TMP_DIR/cpc_sysinit.asm"
echo "done"

# Remove label-based ORG statements
echo -n "  Fix ORG in tasker.asm ... "
sed -i 's/^[[:space:]]*ORG[[:space:]]\+TCB_S\b/	; ORG TCB_S - removed for vasm/' "$TMP_DIR/tasker.asm"
sed -i 's/^[[:space:]]*ORG[[:space:]]\+CORE_TSK\b/	; ORG CORE_TSK - removed for vasm/' "$TMP_DIR/tasker.asm"
echo "done"

echo -n "  Fix ORG in sound.asm ... "
sed -i 's/^[[:space:]]*ORG[[:space:]]\+STACK_S\b/	; ORG STACK_S - removed for vasm/' "$TMP_DIR/sound.asm"
echo "done"

echo -n "  Fix ORG in sysres (CORE_S) ... "
sed -i 's/^[[:space:]]*ORG[[:space:]]\+CORE_S\b/	; ORG CORE_S - removed for vasm/' "$TMP_DIR/cpc_sysres.asm"
sed -i '0,/^CORE_S[[:space:]]*DEFL/{s/^CORE_S\([[:space:]]*\)DEFL\([[:space:]]*\)$/CORE_S\1EQU\2$/}' "$TMP_DIR/cpc_sysres.asm"
sed -i '/^CORE_S[[:space:]]*DEFL/{s/^/; /}' "$TMP_DIR/cpc_sysres.asm"
sed -i 's/^[[:space:]]*DC[[:space:]]*1D00H-CORE_S,0/	DS	1D00H+START_S-$,0/' "$TMP_DIR/cpc_sysres.asm"
echo "done"

# Fix ? labels
echo -n "  Fix BREAK? in tasker.asm ... "
sed -i 's/BREAK?/BREAK_Q/g' "$TMP_DIR/tasker.asm"
echo "done"

echo -n "  Fix AUTO? in cpc_sysinit.asm ... "
sed -i 's/AUTO?/AUTO_Q/g' "$TMP_DIR/cpc_sysinit.asm"
echo "done"

# Convert JR to JP (safe: same cycle count, +1 byte)
echo -n "  Convert JR to JP for safety ... "
for f in "$TMP_DIR"/*.asm; do
    sed -i 's/^\([[:space:]]*\)JR\([[:space:],]\)/\1JP\2/' "$f"
    sed -i 's/^\([A-Za-z_][A-Za-z0-9_]*[[:space:]]\+\)JR\([[:space:],]\)/\1JP\2/' "$f"
done
echo "done"

# Fix 8-bit wrap in sound.asm
echo -n "  Fix 8-bit wrap in sound.asm ... "
sed -i 's/\b0-SNDOFF\b/(0-SNDOFF)\&0FFH/g' "$TMP_DIR/sound.asm"
echo "done"

# Add FDCRET stub (referenced by DCT entries)
echo -n "  Add FDCRET stub ... "
grep -q 'FDCRET:' "$TMP_DIR/cpc_fdcdvr.asm" || \
    echo -e "\n; FDCRET - return stub for non-present drives\nFDCRET:\n\tRET" >> "$TMP_DIR/cpc_fdcdvr.asm"
echo "done"

# Add _RSTNMI stub (referenced by sysinit). The source references @RSTNMI,
# which mras2vasm.pl converts to _RSTNMI, so the appended stub must use the
# converted name (a leading @ is not a valid vasm label).
echo -n "  Add _RSTNMI stub ... "
grep -q '_RSTNMI:' "$TMP_DIR/cpc_sysinit.asm" || \
    printf '\n; _RSTNMI - NMI return stub\n_RSTNMI:\n\tRET\n' >> "$TMP_DIR/cpc_sysinit.asm"
echo "done"

# Add DISKEI label (referenced by boot code)
echo -n "  Add DISKEI label ... "
grep -q 'DISKEI:' "$TMP_DIR/cpc_fdcdvr.asm" || \
    echo -e "\nDISKEI:\n\tNOP" >> "$TMP_DIR/cpc_fdcdvr.asm"
echo "done"

# Add missing CPC port-specific EQU definitions (referenced by shared repo files)
echo -n "  Add missing EQU definitions ... "
cat >> "$TMP_DIR/cpc_equ.asm" << 'CPCEQUEOF'

; CPC port-specific System equates (Model 4 compat values)
_OPREG	EQU	0E4H		;Memory management / video control port
BOOTST_S	EQU	43H		;Boot step rate (byte read at this address)
CPCEQUEOF
echo "done"

# ORG 0036H overlap
echo -n "  Fix ORG 0036H overlap ... "
sed -i 's/^[[:space:]]*ORG[[:space:]]*0036H/; ORG 0036H - removed to avoid section overlap/' "$TMP_DIR/cpc_sysres.asm"
sed -i '/; ORG 0036H - removed/{n;s/^[[:space:]]*DB[[:space:]]*0/; DB 0/;}' "$TMP_DIR/cpc_sysres.asm"
echo "done"

echo ""
echo "=== Assembling CPC SYSRES ==="

$VASM -Fbin -L "$OUT_DIR/sysres_cpc.lst" -o "$OUT_DIR/sysres_cpc.bin" \
    -I"$TMP_DIR" -I"$PORT_DIR" -I"$REPO_DIR" \
    "$TMP_DIR/cpc_sysres.asm" 2>&1 | tee "$OUT_DIR/vasm_errors_cpc.txt"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo "=== CPC SYSRES BUILD SUCCESS ==="
    ls -la "$OUT_DIR/sysres_cpc.bin"
    exit 0
else
    echo ""
    echo "=== CPC SYSRES BUILD FAILED ==="
    echo "=== First 50 lines of errors ==="
    head -50 "$OUT_DIR/vasm_errors_cpc.txt"
    exit 1
fi
