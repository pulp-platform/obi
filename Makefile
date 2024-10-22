# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

BENDER ?= bender
VSIM   ?= vsim
VCS    ?= vcs
ZOIX   ?= zoix

dpi_library ?= work-dpi
ROOT := $(shell pwd)

ZOIX_VLOGAN = "\$$ZOIX vlogan"
VLOGAN = "\$$VCS vlogan"

AVAILABLE_TESTBENCHES = tb_obi_xbar tb_obi_atop_resolver tb_relobi_dec
VCS_TOPLEVEL ?= tb_obi_xbar

# VCS options
vlogan_args += -assert svaext +v2k  \"+incdir+\$$ROOT/includes\" -override_timescale=10ns/10ps -kdb

# Zoix Verilog/SystemVerilog optimizations
ZOIX_COMPILE_ARGS += -propagate -svnetport -mem2pac
# VCS options
ZOIX_COMPILE_ARGS += -lca
# Zoix simulation options
ZOIX_COMPILE_ARGS += +notimingchecks +nospecify +sv
# Zoix useful debug options
ZOIX_COMPILE_ARGS += +noprune

dpi_vcs := $(patsubst src/dpi/%.cpp,build/$(dpi_library)/%_vcs.o,$(wildcard src/dpi/*.cpp))

VCS_COMPILE_ARGS += -debug_access+all

VCS_COMPILE_ARGS += -o vcs.sim

VCS_RUNTIME_ARGS =

# QuestaSim Flow
scripts/compile.tcl:
	mkdir -p scripts
	$(BENDER) script vsim -t relOBI -t obi_test --vlog-arg="-svinputport=compat" > $@

.PHONY: build
build: scripts/compile.tcl
	cd build && \
	$(VSIM) -c -do 'exit -code [source ../scripts/compile.tcl]'

.PHONY: $(AVAILABLE_TESTBENCHES)
$(AVAILABLE_TESTBENCHES): build
ifdef gui
	cd build && \
	$(VSIM) $@ -voptargs="+acc" -do ../scripts/run.tcl
else
	cd build && \
	$(VSIM) -c $@ -do "run -all; quit -f"
endif

.PHONY: all
all: $(AVAILABLE_TESTBENCHES)


# VCS Flow
scripts/compile-vcs.sh:
	mkdir -p scripts
	$(BENDER) script vcs --vlogan-bin=$(VLOGAN) --vlog-arg="$(vlogan_args)" -t obi_test > $@

.PHONY: elabvcs
elabvcs: scripts/compile-vcs.sh
	cd build && \
	chmod +x ../scripts/compile-vcs.sh && \
	../scripts/compile-vcs.sh

vcs.sim: elabvcs
	cd build && \
	$(VCS) vcs $(VCS_COMPILE_ARGS) $(DPI_LIBS) $(VCS_TOPLEVEL)

simcvcs: vcs.sim
	cd build && \
	./$< $(VCS_RUNTIME_ARGS)


# ZOIX Flow
scripts/compile-zoix.sh:
	mkdir -p scripts
	$(BENDER) script vcs --vlogan-bin=$(ZOIX_VLOGAN) --vlog-arg="$(vlogan_args)" -t obi_test > $@

.PHONY: elabzoix
elabzoix: scripts/compile-zoix.sh
	chmod +x ./scripts/compile-zoix.sh && \
	cd build && \
	../scripts/compile-zoix.sh

zoix.sim: elabzoix
	cd build && \
	$(ZOIX) zoix $(ZOIX_COMPILE_ARGS) $(DPI_LIBS) $(VCS_TOPLEVEL)

simczoix: zoix.sim
	cd build && \
	./$< $(ZOIX_RUNTIME_ARGS)


.PHONY: clean
clean:
	rm -f scripts/compile*
	rm -rf work
	rm -f modelsim.ini
	rm -f transcript
	rm -f vsim.wlf
	rm -rf build/*
