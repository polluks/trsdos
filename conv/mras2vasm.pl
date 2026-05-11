#!/usr/bin/perl -w
# MRAS->vasm oldstyle Z80 converter
# Usage: mras2vasm.pl <input.asm> <output.asm>
# Processes all MRAS->vasm conversions including @-labels, $? labels,
# MRAS directives, < shift operator, DC/DM directives, macros.

use strict;

my ($src, $dst) = @ARGV;
die "Usage: $0 <input.asm> <output.asm>\n" unless $src and $dst;

# Z80 instruction mnemonics - NOT label candidates
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
    rrca rla rra rlca
);

my $data;
{ open(my $f, "<", $src) or die "Can't open $src: $!"; local $/; $data = <$f>; close($f); }
$data =~ s/\r\n/\n/g;
$data =~ s/\r/\n/g;

# MRAS directives that do NOT create scope boundaries
# (EQU, DEFL, SET are constant definitions; DS/DB/DW/DC/DM are data)
my %nodirective = map {$_=>1} qw(
    equ defl set ds db dw dc dm endm macro if ifeq ifne ifgt iflt else endif
    end page title subttl mod list nolist
);

my @lines = split(/\n/, $data);

# PASS 1: find scopes for $? label resolution
my @scope_of_line;
my $cur_scope = 0;
for my $i (0..$#lines) {
    my $line = $lines[$i];
    my $label = "";
    if ($line =~ /^\@?([A-Za-z_][A-Za-z0-9_]*):/) {
        $label = $1;
    } elsif ($line =~ /^\@?([A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z][A-Za-z0-9_]*)/) {
        my $w = lc($1);
        my $d = lc($2);
        $label = $1 if !exists $insn{$w} && !exists $nodirective{$d};
    } elsif ($line =~ /^\@?([A-Za-z_][A-Za-z0-9_]*)\s*$/) {
        my $w = lc($1);
        $label = $1 if !exists $insn{$w};
    }
    $cur_scope++ if $label ne "";
    $scope_of_line[$i] = $cur_scope;
}

# PASS 1b: find $? definitions per scope
# MRAS: $?0 and $?0_GET are the SAME label (numeric prefix defines identity,
# _text suffix is descriptive). Register both variants.
my %def_in_scope;
for my $i (0..$#lines) {
    if ($lines[$i] =~ /^\s*\$\??([A-Za-z0-9_]+)(?:\s|$)/) {
        my $name = $1;
        push @{$def_in_scope{$scope_of_line[$i]}->{$name}}, $i;
        # If numeric prefix with _suffix, also register base numeric label
        if ($name =~ /^(\d+)_/) {
            push @{$def_in_scope{$scope_of_line[$i]}->{$1}}, $i;
        }
    }
}

# PASS 2: convert content
for my $i (0..$#lines) {
    my $line = $lines[$i];
    my $s = $scope_of_line[$i];

    # $?NN or $NN labels -> _L_NN_linenum
    # MRAS $? labels are flat nearest-match across entire file,
    # not scoped by regular labels.
    $line =~ s/\$\??([A-Za-z0-9_]+)/
        my $nn = $1;
        my $best = -1;
        # Collect ALL definitions of this $? label across all scopes
        my @all;
        for my $ss (keys %def_in_scope) {
            my $ll = $def_in_scope{$ss}->{$nn};
            push @all, @$ll if $ll;
        }
        # Find nearest match: prefer backward, then forward
        for (@all) { $best = $_ if $_ <= $i && $_ > $best; }
        if ($best < 0) {
            for (@all) { $best = $_ if $best < 0 || ($_ < $best && $_ > $i); }
        }
        $best = 0 if $best < 0;
        "_L_${nn}_${best}"
    /ge;

    # @$label -> _label
    $line =~ s/\@\$([A-Za-z_][A-Za-z0-9_]*)/_$1/g;
    # @label -> _label (also after _ or other non-alpha prefix)
    $line =~ s/(^|[^A-Za-z0-9_])\@([A-Za-z_][A-Za-z0-9_]*)/${1}_$2/g;
    # label@ -> label_
    $line =~ s/([A-Za-z_][A-Za-z0-9_]*)@(?=\W|$)/${1}_/g;
    # Also catch @ in middle of identifier (like PUT_@ROWCOL -> PUT_ROWCOL)
    $line =~ s/([A-Za-z0-9_])@([A-Za-z_])/${1}_${2}/g;
    # label$ -> label_S (trailing $ suffix)
    $line =~ s/([A-Za-z_][A-Za-z0-9_]*)\$/$1_S/g;

    # For $?<number>_<text> definitions, also emit the base numeric label
    if ($line =~ /^(_L_(\d+)_[A-Za-z]+_\d+)(?:\s|$)/) {
        my $alias = "_L_${2}_$i";
        $line = "${alias}:\n" . $line;
    }

    # Store line for further processing
    $lines[$i] = $line;
}

# PASS 3: MRAS directive conversions
for my $i (0..$#lines) {
    my $line = $lines[$i];

    # *GET file -> include "file.asm"
    $line =~ s{^\s*\*GET\s+(\S+)}{
        my $file = lc($1);
        $file =~ s{/.*}{};
        "\tinclude \"${file}.asm\""
    }ie;

    # *MOD -> delete
    $line =~ s{^\s*\*MOD\s*$}{};
    # *LIST OFF/ON -> nolist/list
    $line =~ s{^(\s*)\*LIST\s+OFF\s*$}{$1\tnolist}i;
    $line =~ s{^(\s*)\*LIST\s+ON\s*$}{$1\tlist}i;

    # SUBTTL, TITLE, PAGE -> comment
    $line =~ s{^(\s*)(SUBTTL|TITLE|PAGE)\b.*$}{$1; $2 (converted)}i;

    # 0FFH-IEC_xxx -> pre-computed constant
    $line =~ s/0FFH\s*-\s*IEC_DATA\b/0FEH/g;
    $line =~ s/0FFH\s*-\s*IEC_CLK\b/0FDH/g;
    $line =~ s/0FFH\s*-\s*IEC_ATN\b/0FBH/g;
    $line =~ s/0FFH\s*-\s*IEC_DATA_IN\b/0F7H/g;
    $line =~ s/0FFH\s*-\s*IEC_CLK_IN\b/0EFH/g;

    # DEFL -> set
    $line =~ s{^(\s*)DEFL\b}{$1set};

    # ERR -> comment with error marker
    $line =~ s{^(\s*)ERR\b\s*(.*)$}{$1; *** ASSEMBLY ERROR: $2};

    # ENDIF -> endif, ELSE -> else, END -> end
    $line =~ s{^(\s*)ENDIF\b}{$1endif}i;
    $line =~ s{^(\s*)ELSE\b}{$1else}i;

    # IF[EQ|NE|GT|LT] -> if[eq|ne|gt|lt]
    $line =~ s{^(\s*)(IF)(EQ|NE|GT|LT)?\b}{$1 . lc($2 . ($3||""))}ie;
    # 2-arg IF: ifeq a,b -> ifeq a-b
    if ($line =~ /^(\s*)(if(?:eq|ne|gt|lt)?)\s+([^,;\s]+),\s*([^;\s]+)/i) {
        $line = "$1$2 $3-$4\n";
    }

    # SET instruction after label -> !SET
    $line =~ s/^(\s*[A-Za-z_][A-Za-z0-9_]*\s+)\bSET\b(\s+[0-7]\s*,)/$1!SET$2/;

    # .AND. / .OR. -> && / ||
    $line =~ s/\.AND\./&&/gi;
    $line =~ s/\.OR\./||/gi;

    # END on its own line -> strip (for includes)
    $line =~ s{^\s*end\b.*$}{}i;

    $lines[$i] = $line;
}

# PASS 4: MRAS < shift operator -> vasm shift
# MRAS: a<b = shift right, a>b = shift left
# Context: mostly used as <-N or <N for packing/extracting
#
# Pattern 1: LABEL<-N or (EXPR)<-N -> EXPR >> N
# Pattern 2: NUM<NUM in expressions -> NUM << NUM (SHR in MRAS = SHL in vasm? or SHR?)
#   Actually verified: expr<-8 extracts high byte -> SHR. So < = SHR.
#
# In vasm: shift-right = >>, shift-left = <<

for my $i (0..$#lines) {
    my $line = $lines[$i];
    # Skip if in a comment
    next if $line =~ /^\s*;/;

    # Replace MRAS shift-right: expr<-N -> expr >> N
    $line =~ s/(\w+|<[\dA-F]+H>)\s*<-\s*(\d+)/$1 >> $2/g;
    # Also handle parenthesized: (expr)<-N
    $line =~ s/(\))\s*<-\s*(\d+)/$1 >> $2/g;

    # Replace MRAS shift-left: expr>N -> expr << N  
    $line =~ s/(\w+|<[\dA-F]+H>)\s*>\s*(\d+)/$1 << $2/g;
    $line =~ s/(\))\s*>\s*(\d+)/$1 << $2/g;

    $lines[$i] = $line;
}

# PASS 5: DC count,value -> DEFS count or explicit DB fill
# MRAS DC = define constant (fill memory with repeated value)
# vasm: DEFS count,value (if supported) or use DS+fill
for my $i (0..$#lines) {
    my $line = $lines[$i];
    # DC count,value -> DEFS count,value
    # (DEFS is supported in vasm for defining storage with fill)
    # But DC uses commas, not tabs between count and value
    $line =~ s{^(\s*)DC\s+(\d+)\s*,\s*(\S.*)$}{$1;\t; MRAS DC $2,$3 -> zero fill\n${1}\tDS\t$2};
    $lines[$i] = $line;
}

# PASS 6: DM 'string' -> DB with proper format
# MRAS DM = Define Message: stores length byte prefix + string + ETX (03h)
# vasm: need explicit DB
for my $i (0..$#lines) {
    my $line = $lines[$i];
    # DM 'text' -> DB len,'text',3
    # DM "text" -> DB len,"text",3
    if ($line =~ /^(\s*)((?:[A-Za-z_]\S*)\s+)?DM\s+('[^']*'|"[^"]*")/i) {
        my $indent = $1;
        my $label = $2 || '';
        my $str = $3;
        my $content = $str;
        $content =~ s/^['"]//; $content =~ s/['"]$//;
        my $len = length($content);
        $line = "${indent}${label}DB\t${len},${str},3";
    }
    $lines[$i] = $line;
}

# PASS 7: MACRO/ENDM parameter conversion
# MRAS: name MACRO arg1,arg2  (named params)
# vasm: name: MACRO           (unnamed, uses \1, \2, ...)
# This conversion removes the parameter names from the MACRO line
# Macro invocations stay the same (name arg1,arg2)
# NOTE: parameter NAME REPLACEMENT in macro BODY is NOT done here
# because it requires understanding the macro body scope.
# The output will need manual param->\N substitution.
for my $i (0..$#lines) {
    my $line = $lines[$i];
    # MACRO definition: remove parameter list, keep "MACRO"
    if ($line =~ /^(\s*)([A-Za-z_][A-Za-z0-9_]*)\s+MACRO\s+\S/i) {
        $line = "$1$2: MACRO";
    } elsif ($line =~ /^(\s*)MACRO\s+\S/i) {
        $line = "$1MACRO";
    }
    $lines[$i] = $line;
}

# Write output
open(my $o, ">", $dst) or die "Can't write $dst: $!";
print $o join("\n", @lines), "\n";
close($o);
print "Converted: $src -> $dst\n";
