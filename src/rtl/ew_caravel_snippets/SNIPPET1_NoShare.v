// **** SNIPPET1_NoShare.v: ****
// Snippet to instantiate Anton's top_ew_algofoogle macro IF we end up with NO
// mux/sharing, i.e. just 9 pads dedicated for Anton.

// For more info, see EWSPEC:
// https://github.com/algofoogle/raybox-zero/blob/ew/doc/EWSPEC.md#if-only-9-pads-are-available-to-me-in-total

// ---- ACTUAL SNIPPET STARTS BELOW ----



// Convenience mapping of IO[26:18], allows us to easily renumber Anton's assigned pads:
wire [8:0]  anton_io_in = io_in[26:18];
                  assign io_out[26:18] = anton_io_out; wire [8:0] anton_io_out; // [8:7] not used; they're inputs instead.
                  assign io_oeb[26:18] = anton_io_oeb; wire [8:0] anton_io_oeb = 9'b1100z0000; // io_oeb[22] is 'z' because it's controlled by the design.

// Convenience mapping of LA[114:64] to anton_la_in[50:0], all INPUTS INTO our module:
wire [50:0] anton_la_in   = la_data_in[114:64];
wire [50:0] anton_la_oenb =    la_oenb[114:64]; // SoC should configure these all as its outputs (i.e. inputs to our design).


top_ew_algofoogle top_ew_algofoogle(
`ifdef USE_POWER_PINS
  .vccd1(vccd1),	// User area 1 1.8V power
  .vssd1(vssd1),	// User area 1 digital ground
`endif

  .i_clk                (user_clock2),
  .i_reset_lock_a       (anton_la_in[0]), // Hold design in reset if equal (both 0 or both 1)
  .i_reset_lock_b       (anton_la_in[1]), // Hold design in reset if equal (both 0 or both 1)

  .o_hsync              (anton_io_out[0]),
  .o_vsync              (anton_io_out[1]),
  //.o_rgb([23:0]) not used, except to feed DAC.

  .o_tex_csb            (anton_io_out[2]),
  .o_tex_sclk           (anton_io_out[3]),

  .o_tex_oeb0           (anton_io_oeb[4]), // IO_OEB[22] (dir): IO[22] is my only bidirectional pad.
  .o_tex_out0           (anton_io_out[4]),
  .i_tex_in             ({anton_la_in[50], anton_io_in[8], anton_io_in[7], anton_io_in[4]}),

  .o_gpout              ({4'bzzzz, anton_io_out[6:5]}) // Is assigning Z for UNUSED gpouts the right way to do it?

  .i_vec_csb            (anton_la_in[2]),
  .i_vec_sclk           (anton_la_in[3]),
  .i_vec_mosi           (anton_la_in[4]),

  .i_gpout0_sel         (anton_la_in[10:5]),

  .i_debug_vec_overlay  (anton_la_in[11]),

  .i_reg_csb            (anton_la_in[12]),
  .i_reg_sclk           (anton_la_in[13]),
  .i_reg_mosi           (anton_la_in[14]),

  .i_gpout1_sel         (anton_la_in[20:15]),
  .i_gpout2_sel         (anton_la_in[26:21]),

  .i_debug_trace_overlay(anton_la_in[27]),

  .i_gpout3_sel         (anton_la_in[33:28]),

  .i_debug_map_overlay  (anton_la_in[34]),

  .i_gpout4_sel         (anton_la_in[40:35]),
  .i_gpout5_sel         (anton_la_in[46:41]),

  .i_mode               (anton_la_in[49:47])

);
