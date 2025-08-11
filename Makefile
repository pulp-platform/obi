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

TBS_VSIM = $(addsuffix _vsim, $(AVAILABLE_TESTBENCHES))
TBS_VCS = $(addsuffix _vcs, $(AVAILABLE_TESTBENCHES))

# QuestaSim Flow
scripts/compile_vsim.tcl: Bender.yml Bender.lock
	mkdir -p scripts
	$(BENDER) script vsim $(BENDER_TARGETS) --vlog-arg="-svinputport=compat" > $@

.PHONY: build_vsim
build_vsim: scripts/compile_vsim.tcl
	$(VSIM) -c -do 'exit -code [source scripts/compile_vsim.tcl]'

.PHONY: $(TBS_VSIM)
$(TBS_VSIM): build_vsim
ifdef gui
	$(VSIM) $(patsubst %_vsim, %, $@) -voptargs="+acc"
else
	$(VSIM) -c $(patsubst %_vsim, %, $@) -voptargs="+acc" -do "run -all; quit -f"
endif

.PHONY: all_vsim
all_vsim: $(TBS_VSIM)

# VCS Flow
VCS_SCRIPT_ARGS += -assert svaext +v2k -override_timescale=10ns/10ps -kdb
VCS_COMPILE_ARGS += -debug_access+all -override_timescale=10ns/10ps
VCS_COMPILE_ARGS += +lint=TFIPC-L +lint=PCWM +warn=noCWUC +warn=noUII-L
VCS_RUNTIME_ARGS =

scripts/compile_vcs.sh: Bender.yml Bender.lock
	mkdir -p scripts
	$(BENDER) script vcs --vlogan-bin="$(VLOGAN)" $(BENDER_TARGETS) --vlog-arg="$(VCS_SCRIPT_ARGS)" > $@

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

.PHONY: $(TBS_VCS)
$(TBS_VCS):
	@echo "Running VCS simulation for $@ as $(patsubst %_vcs,%,$@)"
	$(MAKE) build/$(patsubst %_vcs,%,$@).sim
	build/$(patsubst %_vcs,%,$@).sim $(VCS_RUNTIME_ARGS)

.PHONY: all_vcs
all_vcs: $(TBS_VCS)

.PHONY: clean
clean:
	rm -f scripts/compile_vsim.tcl
	rm -rf work
	rm -f modelsim.ini
	rm -f transcript
	rm -f vsim.wlf
	rm -f scripts/compile_vcs.sh
	rm -rf build
