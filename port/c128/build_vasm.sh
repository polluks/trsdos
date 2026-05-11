#!/bin/bash
# Build LSDOS C128 port with vasm
# Converts MRAS syntax + @-labels to vasm oldstyle

VASM="/tmp/vasm/vasmz80_oldstyle"
OUTDIR="/tmp/trsdos-port/build"
SRCDIR="/tmp/trsdos-port/repo/LSDOS631L/lsdos631"
PORTDIR="/tmp/trsdos-port/port/c128"
TMPDIR="/tmp/trsdos-port/tmp"

mkdir -p "$OUTDIR" "$TMPDIR"

# @IDENTIFIER -> _IDENTIFIER rename
# Converts MRAS local labels $?XXX to unique labels per function scope
fix_at_labels() {
    perl -e '
        # Z80 instruction mnemonics (lowercase) - NOT label candidates
        my %insn = map {$_=>1} qw(
            ld ldd ldi lddr ldir push pop ex exx
            add adc sub sbc and xor or cp
            inc dec
            jr jp call ret retn reti
            djnz
            rlc rl rrc rr sla sra srl rld rrd
            bit set res
            in out
            neg daa cpl scf ccf nop halt di ei im
            ini ind inir indr outi outd otir otdr
            cpi cpir cpd cpdr
            rrca rla rra rlca equ defl macro endm set
            dc ds org end if ifeq ifne ifgt iflt else endif
        );
        my @lines;
        open(F,chr(60),shift) or die $!;
        my $data = do { local $/; <F> };
        close(F);
        # Normalize line endings
        $data =~ s/\r\n/\n/g;
        $data =~ s/\r/\n/g;
        @lines = split(/\n/, $data);
        # PASS 1: find scopes (labels at line start, not instructions)
        my @scope_of_line;  # scope index for each line
        my $cur_scope = 0;
        my @scope_names;     # scope name at each scope index
        $scope_names[$cur_scope] = "GLOBAL";
        for my $i (0..$#lines) {
            my $line = $lines[$i];
            my $label = "";
            if ($line =~ /^\@([A-Za-z_][A-Za-z0-9_]*)\s/) {
                $label = $1;
            } elsif ($line =~ /^([A-Za-z_][A-Za-z0-9_]*):/) {
                $label = $1;
            } elsif ($line =~ /^([A-Za-z_][A-Za-z0-9_]*)\s+[A-Z]/) {
                # Only if first word is NOT an instruction (lowercase compare)
                my $w = lc($1);
                if (!exists $insn{$w}) {
                    $label = $1;
                }
            }
            if ($label ne "") {
                $cur_scope++;
                $scope_names[$cur_scope] = $label;
            }
            $scope_of_line[$i] = $cur_scope;
        }
        # PASS 1b: find $?NN or $NN definitions per scope
        my %def_in_scope;  # scope => {NN => [line numbers]}
        for my $i (0..$#lines) {
            if ($lines[$i] =~ /^\s*\$\??([A-Za-z0-9_]+)(?:\s|$)/) {
                my $s = $scope_of_line[$i];
                push @{$def_in_scope{$s}->{$1}}, $i;
            }
        }
        # PASS 2: convert
        for my $i (0..$#lines) {
            my $line = $lines[$i];
            my $s = $scope_of_line[$i];
            $line =~ s/\$\??([A-Za-z0-9_]+)/
                my $nn = $1;
                my $best = -1;
                my $list = $def_in_scope{$s}->{$nn};
                if ($list) {
                    for (@$list) {
                        $best = $_ if $_ <= $i && $_ > $best;
                    }
                    if ($best < 0) {
                        $best = $list->[0];  # forward reference
                    }
                }
                if ($best < 0) {
                    # Fallback: search all scopes backwards
                    for (my $ss = $s; $ss >= 0; $ss--) {
                        my $ll = $def_in_scope{$ss}->{$nn};
                        if ($ll) {
                            for (@$ll) {
                                $best = $_ if $_ <= $i && $_ > $best;
                            }
                            last if $best >= 0;
                        }
                    }
                }
                if ($best < 0) { $best = 0; }
                "_L_${nn}_${best}"
            /ge;
            # @$ at start of identifier -> drop $, replace @ with _
            $line =~ s/\@\$([A-Za-z_][A-Za-z0-9_]*)/_$1/g;
            # @ at start of identifier -> replace with _
            $line =~ s/(?<!\w)\@([A-Za-z_][A-Za-z0-9_]*)/_\1/g;
            # @ at end of identifier -> replace with _
            $line =~ s/([A-Za-z_][A-Za-z0-9_]*)@(?=\W|$)/${1}_/g;
            # @ in middle of identifier -> replace with _
            $line =~ s/([A-Za-z0-9_])@([A-Za-z_])/${1}_${2}/g;
            # Trailing $ in identifiers -> _S (vasm: $ is PC, not valid in IDs)
            $line =~ s/([A-Za-z_][A-Za-z0-9_]*)\$/${1}_S/g;
            $lines[$i] = $line;
        }
        print join("\n", @lines), "\n";
    ' "$1" > "$2"
}

# Fix MRAS directives
fix_mras() {
    perl -e '
        my @lines;
        open(F,chr(60),shift) or die $!;
        my $data = do { local $/; <F> };
        close(F);
        # Normalize line endings
        $data =~ s/\r\n/\n/g;
        $data =~ s/\r/\n/g;
        @lines = split(/\n/, $data);
        for my $i (0..$#lines) {
            my $line = $lines[$i];
            # *GET file -> include "file.asm" (strip MRAS /options, lowercase)
            $line =~ s{^\s*\*GET\s+(\S+)}{
                my $file = lc($1);
                $file =~ s{/.*}{};  # strip MRAS options after /
                "\tinclude \"${file}.asm\""
            }ie;
            # *LIST OFF -> nolist
            $line =~ s{^(\s*)\*LIST\s+OFF\s*$}{$1\tnolist}i;
            # *LIST ON -> list
            $line =~ s{^(\s*)\*LIST\s+ON\s*$}{$1\tlist}i;
            # *MOD -> delete
            $line =~ s{^\s*\*MOD\s*$}{};
            # SUBTTL, TITLE, PAGE -> comment
            $line =~ s{^(\s*)(SUBTTL|TITLE|PAGE)\b.*$}{$1; $2 (converted)}i;
            # DEFL -> set
            $line =~ s{^(\s*)DEFL\b}{$1set};
            # ERR -> comment with error marker
            $line =~ s{^(\s*)ERR\b\s*(.*)$}{$1; *** ASSEMBLY ERROR: $2};
            # IF[EQ|NE|GT|LT] -> if[eq|ne|gt|lt] (lowercase, preserve variant)
            $line =~ s{^(\s*)(IF)(EQ|NE|GT|LT)?\b}{$1 . lc($2 . ($3||""))}ie;
            # Handle 2-arg IF variants: if[eq|ne|gt|lt] a,b -> if[eq|ne|gt|lt] a-b
            if ($line =~ /^(\s*)(if(?:eq|ne|gt|lt)?)\s+([^,;]+),\s*([^;]+)/i) {
                $line = "$1$2 $3-$4\n";
            }
            # Z80 SET instruction after a label: force instruction with !SET prefix
            $line =~ s/^(\s*[A-Za-z_][A-Za-z0-9_]*\s+)\bSET\b(\s+[0-7]\s*,)/$1!SET$2/;
            # MRAS .AND. and .OR. -> vasm && and ||
            $line =~ s/\.AND\./&&/gi;
            $line =~ s/\.OR\./||/gi;
            # ENDIF -> endif, ELSE -> else, END -> end
            $line =~ s{^(\s*)ENDIF\b}{$1endif}i;
            $line =~ s{^(\s*)ELSE\b}{$1else}i;
            $line =~ s{^(\s*)END\b}{$1end}i;
            $line =~ s{^(\s*)END\b}{$1end}i;
            $lines[$i] = $line;
        }
        print join("\n", @lines), "\n";
    ' "$1" > "$2"
}

# Combined conversion
convert_file() {
    local src="$1"
    local dst="$2"
    fix_at_labels "$src" "${dst}.atfix"
    fix_mras "${dst}.atfix" "$dst"
    rm -f "${dst}.atfix"
}

echo "Building C128 LSDOS port with vasm..."
echo "Output: $OUTDIR"

# Pre-convert source files that are included by port files
echo "Pre-converting source files..."
for f in dosdefs.asm filposn.asm loader.asm tasker.asm sound.asm copycom.asm \
         sys1.asm sys2.asm sys3.asm sys4.asm sys5.asm sys9.asm sys10.asm \
         sys11.asm sys12.asm sys13.asm boot4.asm clocks.asm dodvr.asm \
         fdcdvr.asm iodvr.asm kidvr.asm lowcore.asm prdvr.asm sysinit4.asm \
         svcmac.asm values.asm muldiv.asm cervlogo.asm logo.asm; do
    if [ -f "$SRCDIR/$f" ] && [ ! -f "$TMPDIR/$f" ]; then
        convert_file "$SRCDIR/$f" "$TMPDIR/$f"
        # Strip END from includes (it terminates vasm assembly prematurely)
        perl -i -pe 's/^\s*end\b.*$//i' "$TMPDIR/$f"
    fi
done

# Also pre-convert all port files to TMPDIR (except the master build)
for f in "$PORTDIR"/*.asm; do
    base=$(basename "$f")
    if [ ! -f "$TMPDIR/$base" ]; then
        convert_file "$f" "$TMPDIR/$base"
        # Strip END from all port files (they are includes)
        perl -i -pe 's/^\s*end\b.*$//i' "$TMPDIR/$base"
    fi
done

echo ""
echo "=== Assembling files ==="

# c128_sysres is the master build - everything included
# Individual drivers are NOT standalone (they are included by sysres)
for f in c128_sysres; do
    echo -n "  $f ... "
    src="$PORTDIR/${f}.asm"
    dst="$TMPDIR/${f}_vasm.asm"
    if [ -f "$src" ]; then
        convert_file "$src" "$dst"
        $VASM -Fbin -o "$OUTDIR/${f}.bin" \
            -I"$TMPDIR" -I"$PORTDIR" -I"$SRCDIR" \
            "$dst" 2>&1 | head -20
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            echo "  -> OK ($OUTDIR/${f}.bin)"
        else
            echo "  -> FAILED (see errors above)"
        fi
    else
        echo "  NOT FOUND: $src"
    fi
done

# Also assemble individual drivers standalone for verification
echo ""
echo "=== Verifying individual driver assembly ==="
for f in c128_equ c128_boot c128_dodvr c128_kidvr c128_fdcdvr \
         c128_clocks c128_prdvr c128_sysinit; do
    echo -n "  $f ... "
    src="$PORTDIR/${f}.asm"
    dst="$TMPDIR/${f}_vasm.asm"
    if [ -f "$src" ]; then
        convert_file "$src" "$dst"
        $VASM -Fbin -o "$OUTDIR/${f}.bin" \
            -I"$TMPDIR" -I"$PORTDIR" -I"$SRCDIR" \
            "$dst" 2>&1 | head -10
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            echo "  -> OK ($OUTDIR/${f}.bin)"
        else
            echo "  -> FAILED (see errors above)"
        fi
    else
        echo "  NOT FOUND: $src"
    fi
done

echo ""
echo "=== Build outputs ==="
ls -la "$OUTDIR"/*.bin 2>/dev/null
