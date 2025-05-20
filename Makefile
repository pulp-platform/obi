# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

BENDER ?= bender
VSIM ?= vsim
VCS ?= vcs
VLOGAN ?= vlogan

BENDER_TARGETS := -t obi_test
BENDER_TARGETS += -t relOBI

AVAILABLE_TESTBENCHES = tb_obi_xbar tb_obi_atop_resolver tb_relobi_xbar

# QuestaSim Flow
scripts/compile.tcl: Bender.yml Bender.lock
	mkdir -p scripts
	$(BENDER) script vsim $(BENDER_TARGETS) --vlog-arg="-svinputport=compat" > $@

.PHONY: build
build: scripts/compile.tcl
	$(VSIM) -c -do 'exit -code [source scripts/compile.tcl]'

.PHONY: $(AVAILABLE_TESTBENCHES)
$(AVAILABLE_TESTBENCHES): build
ifdef gui
	$(VSIM) $@ -voptargs="+acc"
else
	$(VSIM) -c $@ -do "run -all; quit -f"
endif

.PHONY: all
all: $(AVAILABLE_TESTBENCHES)

# VCS Flow
VCS_COMPILE_ARGS += -debug_access+all -override_timescale=10ns/10ps
VCS_RUNTIME_ARGS =

scripts/compile_vcs.sh: Bender.yml Bender.lock
	mkdir -p scripts
	$(BENDER) script vcs --vlogan-bin="$(VLOGAN)" $(BENDER_TARGETS) --vlog-arg="-assert svaext +v2k -override_timescale=10ns10ps -kdb" > $@

.PHONY: build_vcs
build_vcs: scripts/compile_vcs.sh
	mkdir -p build
	chmod +x scripts/compile_vcs.sh
	cd build && ../scripts/compile_vcs.sh

build/%.sim: build_vcs
	@if ! echo "$(AVAILABLE_TESTBENCHES)" | grep -wq "$*"; then \
		echo "Error: $(basename $@) is not an available testbench"; \
		echo "Available testbenches: $(AVAILABLE_TESTBENCHES)"; \
		exit 1; \
	fi
	cd build && \
	$(VCS) $(VCS_COMPILE_ARGS) -o $*.sim $*

.PHONY: clean
clean:
	rm -f scripts/compile.tcl
	rm -rf work
	rm -f modelsim.ini
	rm -f transcript
	rm -f vsim.wlf
	rm -f scripts/compile_vcs.sh
	rm -rf build
