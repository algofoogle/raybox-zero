`default_nettype none
// `timescale 1ns / 1ps

module vga_mux(
  input         visible,

`ifdef TRACE_STATE_DEBUG
  input         show_trace_debug,
  input [3:0]   trace_state_debug,
`endif//TRACE_STATE_DEBUG

  input         debug_en,
  input [5:0]   debug_rgb,

  input         map_en,
  input [5:0]   map_rgb,

  input         wall_en,
  input [5:0]   wall_rgb,

  input [5:0]   bg_rgb, // Default background colour.
  output reg [5:0]  out
);

  always @(*) begin
    if (!visible)                     out = 6'b0;
    else if (debug_en)                out = debug_rgb;
`ifdef TRACE_STATE_DEBUG
    else if (show_trace_debug && trace_state_debug < 15)  out = {2'b00, trace_state_debug};
`endif//TRACE_STATE_DEBUG
    else if (map_en)                  out = map_rgb;
    else if (wall_en)                 out = wall_rgb;
    else                              out = bg_rgb;
  end
  
endmodule
