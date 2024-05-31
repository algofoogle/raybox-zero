# SPDX-FileCopyrightText: 2023 Anton Maurovic <anton@maurovic.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0


# Main Verilog sources for our design:
MAIN_VSOURCES = \
    src/rtl/fixed_point_params.v	\
    src/rtl/helpers.v				\
    src/rtl/debug_overlay.v			\
    src/rtl/map_overlay.v			\
    src/rtl/map_rom.v				\
    src/rtl/pov.v					\
	src/rtl/rbzero.v				\
	src/rtl/vga_sync.v				\
	src/rtl/vga_mux.v				\
	src/rtl/row_render.v			\
	src/rtl/lzc.v					\
	src/rtl/reciprocal.v			\
	src/rtl/wall_tracer.v			\
	src/rtl/spi_registers.v

# Extra source specific to the simualtion target:
SIM_VSOURCES = \
	sim/target_defs.v

# # Verilog sources used for testing:
# TEST_VSOURCES = test/dump_vcd.v

# Top Verilog module representing our design:
TOP = rbzero

# COCOTB_TEST_MODULE = test.test_rbzero

# Stuff for simulation:
#CFLAGS = -CFLAGS -municode
#CFLAGS := -CFLAGS -DINSPECT_INTERNAL
CC = g++
SIM_LDFLAGS = -lSDL2 -lSDL2_ttf
ifeq ($(OS),Windows_NT)
	SIM_EXE = sim/obj_dir/V$(TOP).exe
	VERILATOR = verilator_bin.exe
else
	SIM_EXE = sim/obj_dir/V$(TOP)
	VERILATOR = verilator
endif
XDEFINES := $(DEF:%=+define+%)
# A fixed seed value for sim_seed:
SEED ?= 22860
# SIM_CFLAGS := -DINSPECT_INTERNAL -DWINDOWS
ifeq ($(OS),Windows_NT)
	CFLAGS := -CFLAGS "-DINSPECT_INTERNAL -DWINDOWS"
	RSEED := $(shell ./winrand.bat)
else
	CFLAGS := -CFLAGS "-DINSPECT_INTERNAL"
	RSEED := $(shell bash -c 'echo $$RANDOM')
endif
#NOTE: RSEED is a random seed value for sim_random.

# COCOTB variables:
export COCOTB_REDUCED_LOG_FMT=1
export PYTHONPATH := test:$(PYTHONPATH)
export LIBPYTHON_LOC=$(shell cocotb-config --libpython)

# Common iverilog args we might end up using:
# -Ttyp 			= One of min:typ:max; use typ (typical) time parameters for device characteristics?
# -o whatever.vvp	= Output compiled iverilog file that will run inside the vvp virtual machine
# -sTOPMODULE		= Top module is named TOPMODULE
# -DFUNCTIONAL		= FUNCTIONAL define passes to sky130 models/primitives?
# -DSIM				= SIM define; what uses it?
# -DUSE_POWER_PINS	= USE_POWER_PINS define; used by design and sky130 models/primitives?
# -DUNIT_DELAY=#1	= Define default propagation delay (?) of models to be 1ns...?
# -fLISTFILE		= (can be specified multiple times) LISTFILE contains a newline-separated list of other .v files to compile
# -g2012			= Support Verilog generation IEEE1800-2012.

# Test the design using iverilog and our cocotb tests...
# For this main test, we use two top modules (hence -s twice):
# $(TOP) (the design) and dump_vcd (just to ensure we get a .vcd file).
test:
	rm -rf sim_build
	mkdir sim_build
	rm -rf results
	iverilog \
		-g2012 \
		-o sim_build/sim.vvp \
		-s $(TOP) -s dump_vcd \
		$(MAIN_VSOURCES) $(TEST_VSOURCES)
	PYTHONOPTIMIZE=${NOASSERT} MODULE=$(COCOTB_TEST_MODULE) \
		vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus \
		sim_build/sim.vvp
	mkdir results
	mv results.xml results/
	mv $(TOP).vcd results/
	! grep -i failure results/results.xml
#SMELL: Is there a better way to tell iverilog, vvp, or cocotb to write
# results directly into results?


show_results:
	gtkwave results/$(TOP).vcd $(TOP).gtkw


# Simulate our design visually using Verilator, outputting to an SDL2 window.
#NOTE: All unassigned bits are set to 0:
sim: $(SIM_EXE)
	@$(SIM_EXE)

# Simulate with all unassigned bits set to 1:
sim_ones: $(SIM_EXE)
	@$(SIM_EXE) +verilator+rand+reset+1

# Simulate with unassigned bits fully randomised each time:
sim_random: $(SIM_EXE)
	echo "Random seed: " $(RSEED)
	@$(SIM_EXE) +verilator+rand+reset+2 +verilator+seed+$(RSEED)

# Simulate with unassigned bits randomised based on a known seed each time:
sim_seed: $(SIM_EXE)
	echo "Random seed: " $(SEED)
	@$(SIM_EXE) +verilator+rand+reset+2 +verilator+seed+$(SEED)

# Build main simulation exe:
$(SIM_EXE): $(SIM_VSOURCES) $(MAIN_VSOURCES) sim/sim_main.cpp sim/main_tb.h sim/testbench.h
	echo $(RSEED)
	$(VERILATOR) \
		--Mdir sim/obj_dir \
		-Isrc/rtl \
		-Isim \
		--cc $(SIm_VSOURCES) $(MAIN_VSOURCES) \
		--top-module $(TOP) \
		--exe --build ../sim/sim_main.cpp \
		$(CFLAGS) \
		-LDFLAGS "$(SIM_LDFLAGS)" \
		+define+RESET_AL \
		$(XDEFINES)

clean:
	rm -rf sim_build
	rm -rf results
	rm -rf sim/obj_dir
	rm -rf test/__pycache__
	rm -rf $(TOP).vcd results.xml

clean_build: clean $(SIM_EXE)

clean_sim: clean sim

clean_sim_random: clean sim_random

csr: clean_sim_random

# This tells make that 'test' and 'clean' are themselves not artefacts to make,
# but rather tasks to always run:
.PHONY: test clean sim sim_ones sim_random sim_seed show_results clean_sim clean_sim_random clean_build csr

