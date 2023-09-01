`default_nettype none
`timescale 1ns / 1ps

module vga_mux(
  input         visible,

`ifdef TRACE_STATE_DEBUG
  input [2:0]   trace_state_debug,
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

`ifdef TRACE_STATE_DEBUG
  function [5:0] f_trace_state_color(input [2:0] state);
    casez (state)
      // stepDistX (rayDirX reciprocal) states:
      3'd0:   f_trace_state_color = 6'b00_01_00;  // Dark...
      3'd1:   f_trace_state_color = 6'b00_10_00;  // Medium...
      3'd2:   f_trace_state_color = 6'b00_11_00;  // Bright GREEN

      // stepDistY (rayDirY reciprocal) states:
      3'd3:   f_trace_state_color = 6'b00_01_00;  // Dark...
      3'd4:   f_trace_state_color = 6'b00_11_00;  // Bright BLUE

      // TracePrep and TraceStep:
      3'd5:   f_trace_state_color = 6'b11_00_11;  // Magenta
      3'd6:   f_trace_state_color = 6'b00_11_11;  // Yellow

      // TraceDone:
      3'd7:   f_trace_state_color = 6'b00_00_11;  // Bright RED

    endcase
  endfunction
`endif//TRACE_STATE_DEBUG

  always @(*) begin
    if (!visible)                     out = 6'b0;
`ifdef TRACE_STATE_DEBUG
    else if (trace_state_debug != 7)  out = f_trace_state_color(trace_state_debug);
`endif//TRACE_STATE_DEBUG
    else if (debug_en)                out = debug_rgb;
    else if (map_en)                  out = map_rgb;
    else if (wall_en)                 out = wall_rgb;
    else                              out = bg_rgb;
  end
  
endmodule
