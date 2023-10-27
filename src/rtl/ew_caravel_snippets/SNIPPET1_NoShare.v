// Anton has provided 3 alternate snippets (this file is one of them) for
// instantiating his design's macro (top_ew_algofoogle) in the user_project_wrapper.

// This one (SNIPPET1_NoShare.v) is the version to use if we don't end up using
// any mux for shared IO pads, i.e. if Anton has access to exactly 9 pads, only.
// This corresponds to EWSPEC heading 'If only 9 pads are available to me, in total':
// https://github.com/algofoogle/raybox-zero/blob/ew/doc/EWSPEC.md#if-only-9-pads-are-available-to-me-in-total

// This snippet uses:
// -  9 IO pads as assigned by Ellen (IO[26:18])
// -  user_clock2 as clock source
// -  51 inputs coming in from LA[114:64] (but can be moved), inc. two for reset.

// Convenience signal names/numbering for Anton's 51 LA inputs, so that we can
// easily move them around to different LA numbers by just changing this one
// line...
//@@@SMELL: Is this OK to do?
wire [50:0] anton_la_in = la_data_in[114:64];
// Hard-wire the OEBs for Anton's LA pins...
//@@@SMELL: Make sure these match the mapping used by anton_la_in, above.
assign la_oenb[114:64] = 51'h7_FFFF_FFFF_FFFF; // All 51 are set to '1' (i.e. INPUT)

// Hard-wire the OEBs for Anton's dedicated input and output pads...
assign io_oeb[26:18] = 9'b1100z0000; // io_oeb[22] is 'z' because it's controlled by the design.


top_ew_algofoogle top_ew_algofoogle(
`ifdef USE_POWER_PINS
  .vccd1(vccd1),	// User area 1 1.8V power
  .vssd1(vssd1),	// User area 1 digital ground
`endif

  .i_clk                (user_clock2),
  .i_reset_lock_a       (anton_la_in[0]), // Hold design in reset if equal (both 0 or both 1)
  .i_reset_lock_b       (anton_la_in[1]), // Hold design in reset if equal (both 0 or both 1)

  .o_hsync              (io_out[18]),
  .o_vsync              (io_out[19]),
  //.o_rgb([23:0]) not used, except to feed DAC.

  .o_tex_csb            (io_out[20]),
  .o_tex_sclk           (io_out[21]),

  .o_tex_oeb0           (io_oeb[22]), // IO_OEB[22] (dir): IO[22] is my only bidirectional pad.
  .o_tex_out0           (io_out[22]),
  .i_tex_in             ({anton_la_in[50], io_in[26], io_in[25], io_in[22]}),

  .o_gpout              ({4'bzzzz, io_out[24:23]}) // Is assigning Z for unused gpouts the right way to do it?

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

// Mapping of pad numbers to external signal names:
// 18   Out   o_hsync
// 19   Out   o_vsync
// 20   Out   o_tex_csb
// 21   Out   o_tex_sclk
// 22   I/O   io_tex_io0
// 23   Out   o_gpout0
// 24   Out   o_gpout1
// 25   In    i_tex_io1
// 26   In    i_tex_io2

// Mapping of LA numbers to my design's internal pin names...
// NOTE: 
// (See: https://github.com/algofoogle/raybox-zero/blob/ew/doc/EWSPEC.md#logic-analyser-pins)
//////////////////////////////////////////////////////////////////
// 'Nice' name      Real name         Signal/function
//////////////////////////////////////////////////////////////////
// anton_la_in[0]   la_data_in[64]    i_reset_lock_a
// anton_la_in[1]   la_data_in[65]    i_reset_lock_b
// anton_la_in[2]   la_data_in[66]    i_vec_csb
// anton_la_in[3]   la_data_in[67]    i_vec_sclk
// anton_la_in[4]   la_data_in[68]    i_vec_mosi
// anton_la_in[5]   la_data_in[69]    i_gpout0_sel[0]
// anton_la_in[6]   la_data_in[70]    i_gpout0_sel[1]
// anton_la_in[7]   la_data_in[71]    i_gpout0_sel[2]
// anton_la_in[8]   la_data_in[72]    i_gpout0_sel[3]
// anton_la_in[9]   la_data_in[73]    i_gpout0_sel[4]
// anton_la_in[10]  la_data_in[74]    i_gpout0_sel[5]
// anton_la_in[11]  la_data_in[75]    i_debug_vec_overlay
// anton_la_in[12]  la_data_in[76]    i_reg_csb
// anton_la_in[13]  la_data_in[77]    i_reg_sclk
// anton_la_in[14]  la_data_in[78]    i_reg_mosi
// anton_la_in[15]  la_data_in[79]    i_gpout1_sel[0]
// anton_la_in[16]  la_data_in[80]    i_gpout1_sel[1]
// anton_la_in[17]  la_data_in[81]    i_gpout1_sel[2]
// anton_la_in[18]  la_data_in[82]    i_gpout1_sel[3]
// anton_la_in[19]  la_data_in[83]    i_gpout1_sel[4]
// anton_la_in[20]  la_data_in[84]    i_gpout1_sel[5]
// anton_la_in[21]  la_data_in[85]    i_gpout2_sel[0]
// anton_la_in[22]  la_data_in[86]    i_gpout2_sel[1]
// anton_la_in[23]  la_data_in[87]    i_gpout2_sel[2]
// anton_la_in[24]  la_data_in[88]    i_gpout2_sel[3]
// anton_la_in[25]  la_data_in[89]    i_gpout2_sel[4]
// anton_la_in[26]  la_data_in[90]    i_gpout2_sel[5]
// anton_la_in[27]  la_data_in[91]    i_debug_trace_overlay
// anton_la_in[28]  la_data_in[92]    i_gpout3_sel[0]
// anton_la_in[29]  la_data_in[93]    i_gpout3_sel[1]
// anton_la_in[30]  la_data_in[94]    i_gpout3_sel[2]
// anton_la_in[31]  la_data_in[95]    i_gpout3_sel[3]
// anton_la_in[32]  la_data_in[96]    i_gpout3_sel[4]
// anton_la_in[33]  la_data_in[97]    i_gpout3_sel[5]
// anton_la_in[34]  la_data_in[98]    i_debug_map_overlay
// anton_la_in[35]  la_data_in[99]    i_gpout4_sel[0]
// anton_la_in[36]  la_data_in[100]   i_gpout4_sel[1]
// anton_la_in[37]  la_data_in[101]   i_gpout4_sel[2]
// anton_la_in[38]  la_data_in[102]   i_gpout4_sel[3]
// anton_la_in[39]  la_data_in[103]   i_gpout4_sel[4]
// anton_la_in[40]  la_data_in[104]   i_gpout4_sel[5]
// anton_la_in[41]  la_data_in[105]   i_gpout5_sel[0]
// anton_la_in[42]  la_data_in[106]   i_gpout5_sel[1]
// anton_la_in[43]  la_data_in[107]   i_gpout5_sel[2]
// anton_la_in[44]  la_data_in[108]   i_gpout5_sel[3]
// anton_la_in[45]  la_data_in[109]   i_gpout5_sel[4]
// anton_la_in[46]  la_data_in[110]   i_gpout5_sel[5]
// anton_la_in[47]  la_data_in[111]   i_mode[0]
// anton_la_in[48]  la_data_in[112]   i_mode[1]
// anton_la_in[49]  la_data_in[113]   i_mode[2]
// anton_la_in[50]  la_data_in[114]   i_tex_in[3]
//////////////////////////////////////////////////////////////////
