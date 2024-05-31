# User config
#set script_dir [file dirname [file normalize [info script]]]

set ::env(DESIGN_NAME) top_ew_algofoogle

# save some time
set ::env(RUN_KLAYOUT_XOR) 0
set ::env(RUN_KLAYOUT_DRC) 0

# # don't put clock buffers on the outputs, need tristates to be the final cells
# set ::env(PL_RESIZER_BUFFER_OUTPUT_PORTS) 0

#SMELL: Just change this to a glob:
#set ::env(VERILOG_FILES) [glob $::env(DESIGN_DIR)/src/rtl/*.v]
set ::env(VERILOG_FILES) "\
    $::env(DESIGN_DIR)/src/rtl/top_ew_algofoogle.v
    $::env(DESIGN_DIR)/src/rtl/debug_overlay.v
    $::env(DESIGN_DIR)/src/rtl/fixed_point_params.v
    $::env(DESIGN_DIR)/src/rtl/helpers.v
    $::env(DESIGN_DIR)/src/rtl/lzc.v
    $::env(DESIGN_DIR)/src/rtl/map_overlay.v
    $::env(DESIGN_DIR)/src/rtl/map_rom.v
    $::env(DESIGN_DIR)/src/rtl/pov.v
    $::env(DESIGN_DIR)/src/rtl/rbzero.v
    $::env(DESIGN_DIR)/src/rtl/reciprocal.v
    $::env(DESIGN_DIR)/src/rtl/row_render.v
    $::env(DESIGN_DIR)/src/rtl/spi_registers.v
    $::env(DESIGN_DIR)/src/rtl/vga_mux.v
    $::env(DESIGN_DIR)/src/rtl/vga_sync.v
    $::env(DESIGN_DIR)/src/rtl/wall_tracer.v
    "

set ::env(FP_SIZING) absolute
set ::env(DIE_AREA) "0 0 700 700"
set ::env(PL_TARGET_DENSITY) 0.6

# set ::env(SYNTH_DEFINES) "MPRJ_IO_PADS=38"

set ::env(CLOCK_PERIOD) "40"
set ::env(CLOCK_PORT) "clk"

set ::env(DESIGN_IS_CORE) 0
set ::env(RT_MAX_LAYER) {met4}

set ::env(VDD_NETS) [list {vccd1}]
set ::env(GND_NETS) [list {vssd1}]

#set ::env(FP_PIN_ORDER_CFG) $script_dir/pin_order.cfg

set ::env(FP_IO_VTHICKNESS_MULT) 4
set ::env(FP_IO_HTHICKNESS_MULT) 4

set ::env(ROUTING_CORES) 4
set ::env(KLAYOUT_XOR_THREADS) 4
