VASMDIR := /tmp/vasm
VASM6502 := $(or $(shell which vasm6502_oldstyle 2>/dev/null),$(VASMDIR)/vasm6502_oldstyle)
VASMZ80 := $(or $(shell which vasmz80_oldstyle 2>/dev/null),$(VASMDIR)/vasmz80_oldstyle)
EXOMIZER := /tmp/opencode/exomizer/src/exomizer
BUILD := build
D64 := trsdos_c128.d64
DSK := trsdos_cpc.dsk

# C128 sources
SRC_6502 := boot_sector.s
SRC_Z80 := z80_boot.asm
SRC_HELLO := hello.asm
BIN_6502 := $(BUILD)/boot_sector.bin
BIN_Z80 := $(BUILD)/z80_boot.bin
BIN_HELLO := $(BUILD)/hello.cmd

# CPC sources
SRC_CPC := boot_cpc.asm
SRC_DECR := decrun_cpc.asm
BIN_CPC := $(BUILD)/boot_cpc.bin
BIN_DECR := $(BUILD)/decrun_cpc.bin

# Shared SYSRES
BIN_SYSRES := $(BUILD)/sysres/sysres.bin
BIN_FLAT := $(BUILD)/sysres/boot_sysres.bin
BIN_COMP := $(BUILD)/sysres/sysres_compressed.bin
BIN_PACK := $(BUILD)/sysres/sysres_packed.bin

DECR_SIZE := 148

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

$(BIN_HELLO): $(SRC_HELLO) | vasm_build $(BUILD)
	$(VASMZ80) -Fbin -o $@ $(SRC_HELLO)

$(BIN_DECR): $(SRC_DECR) | vasm_build $(BUILD)
	$(VASMZ80) -Fbin -o $@ $(SRC_DECR)

# CPC boot code: assemble with BLOB_SECS computed from packed blob size
$(BIN_CPC): $(SRC_CPC) $(BIN_PACK) | vasm_build $(BUILD)
	BLOB_SIZE=$$(stat -c %s $(BIN_PACK)); \
	BLOB_SECS=$$(( (BLOB_SIZE + 511) / 512 )); \
	$(VASMZ80) -Fbin -D BLOB_SECS=$$BLOB_SECS -D DECR_SIZE=$(DECR_SIZE) -o $@ $(SRC_CPC)

$(BIN_SYSRES) $(BIN_FLAT): conv/build_sysres.sh $(wildcard port/**/*.asm) $(wildcard conv/*.pl)
	bash conv/build_sysres.sh
	python3 conv/flatten_sysres.py

# Compress flat SYSRES with Exomizer
$(BIN_COMP): $(BIN_FLAT) | $(BUILD)/sysres
	$(EXOMIZER) raw -c $(BIN_FLAT) -o $@

# Pack: prepend decruncher to compressed data
$(BIN_PACK): $(BIN_DECR) $(BIN_COMP)
	cat $(BIN_DECR) $(BIN_COMP) > $@

$(D64): $(BIN_6502) $(BIN_Z80) $(BIN_HELLO) $(BIN_SYSRES) make_d64.py
	python3 make_d64.py

$(DSK): $(BIN_CPC) $(BIN_PACK) make_dsk.py
	python3 make_dsk.py

$(BUILD) $(BUILD)/sysres:
	mkdir -p $@

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
	cp -r port/c128 $(DIST_DIR)/$(DIST_C128)/trsdos/port/
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
	cp -r port/cpc $(DIST_DIR)/$(DIST_CPC)/trsdos/port/
	cd $(DIST_DIR)/$(DIST_CPC) && zip -r ../../$(DIST_ZIP_CPC) trsdos
	rm -rf $(DIST_DIR)/$(DIST_CPC)
	@echo "=== Created $(DIST_ZIP_CPC) ==="

clean:
	rm -rf $(BUILD) $(D64) $(DSK)

distclean: clean
	rm -f $(DIST_ZIP_C128) $(DIST_ZIP_CPC)
