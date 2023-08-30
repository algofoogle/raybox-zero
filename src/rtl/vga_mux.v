`default_nettype none
`timescale 1ns / 1ps

module vga_mux(
  input         visible,

`ifdef TRACE_STATE_DEBUG
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

`ifdef TRACE_STATE_DEBUG
  function [5:0] f_trace_state_color(input [3:0] state);
    casez (state)
      // stepDistX (rayDirX reciprocal) states:
      4'd0:   f_trace_state_color = 6'b00_01_00;  // Dark...
      4'd1:   f_trace_state_color = 6'b00_10_00;  // Medium...
      4'd2:   f_trace_state_color = 6'b00_11_00;  // Bright GREEN

      4'd3:   f_trace_state_color = 6'b01_00_00;  // Dark...
      4'd4:   f_trace_state_color = 6'b10_00_00;  // Medium...
      4'd5:   f_trace_state_color = 6'b11_00_00;  // Bright BLUE

      4'd6:   f_trace_state_color = 6'b11_00_11;  // Magenta
      4'd7:   f_trace_state_color = 6'b00_11_11;  // Yellow
      4'd8:   f_trace_state_color = 6'b00_01_01;  // Dark yellow
      4'd9:   f_trace_state_color = 6'b11_11_00;  // Cyan.

      4'd10:  f_trace_state_color = 6'b00_00_01;  // Dark...
      4'd11:  f_trace_state_color = 6'b00_00_10;  // Medium...
      default:f_trace_state_color = 6'b00_00_11;  // Bright RED
    endcase
  endfunction
`endif//TRACE_STATE_DEBUG

  always @(*) begin
    if (!visible)                     out = 6'b0;
`ifdef TRACE_STATE_DEBUG
    else if (trace_state_debug < 13)  out = f_trace_state_color(trace_state_debug);
`endif//TRACE_STATE_DEBUG
    else if (debug_en)                out = debug_rgb;
    else if (map_en)                  out = map_rgb;
    else if (wall_en)                 out = wall_rgb;
    else                              out = bg_rgb;
  end
  
endmodule
