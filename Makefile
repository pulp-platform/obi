# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

BENDER ?= bender
VSIM ?= vsim
QUESTA ?= questa-2023.4

AVAILABLE_TESTBENCHES = tb_obi_xbar tb_obi_atop_resolver tb_relobi_dec

scripts/compile.tcl:
	mkdir -p scripts
	$(BENDER) script vsim -t relOBI -t test --vlog-arg="-svinputport=compat" > $@

.PHONY: build
build: scripts/compile.tcl
	$(QUESTA) $(VSIM) -c -do 'exit -code [source scripts/compile.tcl]'

.PHONY: $(AVAILABLE_TESTBENCHES)
$(AVAILABLE_TESTBENCHES): build
ifdef gui
	$(QUESTA) $(VSIM) $@ -voptargs="+acc" -do ./scripts/run.tcl
else
	$(QUESTA) $(VSIM) -c $@ -do "run -all; quit -f"
endif

.PHONY: all
all: $(AVAILABLE_TESTBENCHES)

.PHONY: clean
clean:
	rm -f scripts/compile.tcl
	rm -rf work
	rm -f modelsim.ini
	rm -f transcript
	rm -f vsim.wlf
