VASMDIR := /tmp/vasm
VASM6502 := $(or $(shell which vasm6502_oldstyle 2>/dev/null),$(VASMDIR)/vasm6502_oldstyle)
VASMZ80 := $(or $(shell which vasmz80_oldstyle 2>/dev/null),$(VASMDIR)/vasmz80_oldstyle)
BUILD := build
D64 := trsdos_c128.d64
DSK := trsdos_cpc.dsk

# C128 sources
SRC_6502 := boot_sector.s
SRC_Z80 := z80_boot.asm
BIN_6502 := $(BUILD)/boot_sector.bin
BIN_Z80 := $(BUILD)/z80_boot.bin

# CPC sources
SRC_CPC := boot_cpc.asm
BIN_CPC := $(BUILD)/boot_cpc.bin

# Shared SYSRES
BIN_SYSRES := $(BUILD)/sysres/sysres.bin

DIST_NAME := trsdos-c128-boot
DIST_VER := $(shell date +%Y%m%d)
DIST_C128 := $(DIST_NAME)-$(DIST_VER)
DIST_CPC := trsdos-cpc-boot-$(DIST_VER)
DIST_DIR := dist
DIST_ZIP_C128 := $(DIST_C128).zip
DIST_ZIP_CPC := $(DIST_CPC).zip

.PHONY: all c128 cpc clean distclean dist vasm_build

all: c128 cpc

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

$(D64): $(BIN_6502) $(BIN_Z80) $(BIN_SYSRES) make_d64.py
	python3 make_d64.py

$(DSK): $(BIN_CPC) $(BIN_SYSRES) make_dsk.py
	python3 make_dsk.py

$(BUILD):
	mkdir -p $(BUILD)

dist: c128
	rm -rf $(DIST_DIR) $(DIST_ZIP_C128)
	mkdir -p $(DIST_DIR)/$(DIST_C128)/trsdos
	cp $(D64) $(DIST_DIR)/$(DIST_C128)/trsdos/
	cp $(SRC_6502) $(DIST_DIR)/$(DIST_C128)/trsdos/
	cp $(SRC_Z80) $(DIST_DIR)/$(DIST_C128)/trsdos/
	cp make_d64.py $(DIST_DIR)/$(DIST_C128)/trsdos/
	cp Makefile $(DIST_DIR)/$(DIST_C128)/trsdos/
	cp .gitignore $(DIST_DIR)/$(DIST_C128)/trsdos/ 2>/dev/null || true
	cp README.md $(DIST_DIR)/$(DIST_C128)/trsdos/ 2>/dev/null || true
	cp AGENTS.md $(DIST_DIR)/$(DIST_C128)/trsdos/ 2>/dev/null || true
	cp -r port $(DIST_DIR)/$(DIST_C128)/trsdos/
	cd $(DIST_DIR)/$(DIST_C128) && zip -r ../../$(DIST_ZIP_C128) trsdos
	rm -rf $(DIST_DIR)/$(DIST_C128)
	@echo "=== Created $(DIST_ZIP_C128) ==="

dist-cpc: cpc
	rm -rf $(DIST_DIR) $(DIST_ZIP_CPC)
	mkdir -p $(DIST_DIR)/$(DIST_CPC)/trsdos
	cp $(DSK) $(DIST_DIR)/$(DIST_CPC)/trsdos/
	cp $(SRC_CPC) $(DIST_DIR)/$(DIST_CPC)/trsdos/
	cp make_dsk.py $(DIST_DIR)/$(DIST_CPC)/trsdos/
	cp Makefile $(DIST_DIR)/$(DIST_CPC)/trsdos/
	cp .gitignore $(DIST_DIR)/$(DIST_CPC)/trsdos/ 2>/dev/null || true
	cp README.md $(DIST_DIR)/$(DIST_CPC)/trsdos/ 2>/dev/null || true
	cp AGENTS.md $(DIST_DIR)/$(DIST_CPC)/trsdos/ 2>/dev/null || true
	cp -r port $(DIST_DIR)/$(DIST_CPC)/trsdos/
	cd $(DIST_DIR)/$(DIST_CPC) && zip -r ../../$(DIST_ZIP_CPC) trsdos
	rm -rf $(DIST_DIR)/$(DIST_CPC)
	@echo "=== Created $(DIST_ZIP_CPC) ==="

clean:
	rm -rf $(BUILD) $(D64) $(DSK)

distclean: clean
	rm -f $(DIST_ZIP_C128) $(DIST_ZIP_CPC)
