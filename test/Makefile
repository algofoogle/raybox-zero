test:
	iverilog -g2009 -s rbz_tb -I../src/rtl/ \
		../src/rtl/fixed_point_params.v \
		../src/rtl/lzc.v 				\
		../src/rtl/reciprocal.v 		\
		../src/rtl/helpers.v			\
		../src/rtl/debug_overlay.v		\
		../src/rtl/map_overlay.v		\
		../src/rtl/map_rom.v			\
		../src/rtl/pov.v				\
		../src/rtl/rbzero.v				\
		../src/rtl/row_render.v			\
		../src/rtl/spi_registers.v		\
		../src/rtl/top_ew_algofoogle.v	\
		../src/rtl/vga_mux.v			\
		../src/rtl/vga_sync.v			\
		../src/rtl/wall_tracer.v		\
		rbz_tb.v
	./a.out
	gtkwave rbz_tb.vcd tests.gtkw
