VASMDIR := /tmp/vasm
VASM6502 := $(or $(shell which vasm6502_oldstyle 2>/dev/null),$(VASMDIR)/vasm6502_oldstyle)
VASMZ80 := $(or $(shell which vasmz80_oldstyle 2>/dev/null),$(VASMDIR)/vasmz80_oldstyle)
BUILD := build
D64 := trsdos_c128.d64
DSK := trsdos_cpc.dsk

SRC_6502 := boot_sector.s
SRC_Z80 := z80_boot.asm
BIN_6502 := $(BUILD)/boot_sector.bin
BIN_Z80 := $(BUILD)/z80_boot.bin

SRC_CPC := boot_cpc.asm
BIN_CPC := $(BUILD)/boot_cpc.bin

BIN_SYSRES := $(BUILD)/sysres/sysres.bin

DIST_NAME := trsdos-c128-boot
DIST_VER := $(shell date +%Y%m%d)
DIST_DIR := $(DIST_NAME)-$(DIST_VER)
DIST_ZIP := $(DIST_DIR).zip

.PHONY: all c128 cpc clean distclean dist vasm_build check

all: $(D64) $(DSK)

c128: $(D64)

cpc: $(DSK)

vasm_build:
	@if ! test -x $(VASM6502); then \
		echo "Building vasm6502_oldstyle..."; \
		$(MAKE) -C $(VASMDIR) SYNTAX=oldstyle CPU=6502; \
	fi
	@if ! test -x $(VASMZ80); then \
		echo "Building vasmz80_oldstyle..."; \
		$(MAKE) -C $(VASMDIR) SYNTAX=oldstyle CPU=z80; \
	fi

$(BIN_6502): $(SRC_6502) | vasm_build $(BUILD)
	$(VASM6502) -Fbin -o $@ $(SRC_6502)

$(BIN_Z80): $(SRC_Z80) | vasm_build $(BUILD)
	$(VASMZ80) -Fbin -o $@ $(SRC_Z80)

$(BIN_CPC): $(SRC_CPC) | vasm_build $(BUILD)
	$(VASMZ80) -Fbin -o $@ $(SRC_CPC)

$(BIN_SYSRES): conv/build_sysres.sh $(wildcard port/c128/*.asm) $(wildcard conv/*.pl)
	bash conv/build_sysres.sh
	python3 conv/flatten_sysres.py

$(BUILD)/hello.cmd: hello.asm | vasm_build $(BUILD)
	$(VASMZ80) -Fbin -o $@ hello.asm 2>/dev/null || true

$(BUILD)/trsmark.raw: trsmark.asm | vasm_build $(BUILD)
	$(VASMZ80) -Fbin -o $@ trsmark.asm

$(BUILD)/trsmark.cmd: $(BUILD)/trsmark.raw make_cmd.py
	python3 make_cmd.py $(BUILD)/trsmark.raw 3000 $(BUILD)/trsmark.cmd

$(D64): $(BIN_6502) $(BIN_Z80) $(BIN_SYSRES) make_d64.py trsdos_lsdir.py
	$(MAKE) $(BUILD)/hello.cmd 2>/dev/null; true
	$(MAKE) $(BUILD)/trsmark.cmd
	python3 make_d64.py

$(DSK): $(BIN_CPC) $(BIN_SYSRES) make_dsk.py trsdos_lsdir.py
	$(MAKE) $(BUILD)/hello.cmd 2>/dev/null; true
	$(MAKE) $(BUILD)/trsmark.cmd
	python3 make_dsk.py

$(BUILD):
	mkdir -p $(BUILD)

dist: $(D64)
	rm -rf $(DIST_DIR) $(DIST_ZIP)
	mkdir -p $(DIST_DIR)/trsdos
	cp $(D64) $(DIST_DIR)/trsdos/
	cp $(SRC_6502) $(DIST_DIR)/trsdos/
	cp $(SRC_Z80) $(DIST_DIR)/trsdos/
	cp make_d64.py $(DIST_DIR)/trsdos/
	cp make_dsk.py $(DIST_DIR)/trsdos/
	cp trsdos_lsdir.py $(DIST_DIR)/trsdos/
	cp Makefile $(DIST_DIR)/trsdos/
	cp .gitignore $(DIST_DIR)/trsdos/ 2>/dev/null || true
	cp README.md $(DIST_DIR)/trsdos/ 2>/dev/null || true
	cp AGENTS.md $(DIST_DIR)/trsdos/ 2>/dev/null || true
	cp -r port $(DIST_DIR)/trsdos/
	cd $(DIST_DIR) && zip -r ../$(DIST_ZIP) trsdos
	rm -rf $(DIST_DIR)
	@echo "=== Created $(DIST_ZIP) ==="

clean:
	rm -rf $(BUILD) $(D64) $(DSK)

distclean: clean
	rm -f $(DIST_ZIP)

check: $(D64) $(DSK)
	python3 check_d64.py $(D64)
	python3 check_dsk.py $(DSK)
