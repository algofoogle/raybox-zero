`default_nettype none
// `timescale 1ns / 1ps

module vga_sync #(
  // 800 clocks wide:
  parameter H_VIEW        = 640,   // Visible area comes first...
  parameter H_FRONT       =  16,   // ...then HBLANK starts with H_FRONT (RHS border)...
  parameter H_SYNC        =  96,   // ...then sync pulse starts...
  parameter H_BACK        =  48,   // ...then remainder of HBLANK (LHS border).
  parameter H_MAX         = H_VIEW + H_FRONT + H_SYNC + H_BACK - 1,
  parameter H_SYNC_START  = H_VIEW + H_FRONT,
  parameter H_SYNC_END    = H_SYNC_START + H_SYNC,
  // 525 lines tall:
  parameter V_VIEW        = 480,
  parameter V_FRONT       =  10,
  parameter V_SYNC        =   2,
  parameter V_BACK        =  33,
  parameter V_MAX         = V_VIEW + V_FRONT + V_SYNC + V_BACK - 1,
  parameter V_SYNC_START  = V_VIEW + V_FRONT,
  parameter V_SYNC_END    = V_SYNC_START + V_SYNC
  // Overall timing for true VGA 25.175MHz clock: 25,175,000 / 800 / 525 = 59.94Hz
  // or for 25.0MHz clock: 59.52Hz
  // Try pushing these timings around and see what happens.
) (
  // Inputs:
  input wire          clk,
  input wire          reset,
  // Outputs:
  output reg          hsync,
  output reg          vsync,
  output reg [9:0]    hpos,
  output reg [9:0]    vpos,
  output wire         hmax,
  output wire         vmax,
  output wire         visible
);


  //TODO: Reduce equality checks to just test the bits that matter,
  // because we don't care about values ABOVE these.
  // Might also be able to do similar with comparisons.
  //TODO: Consider making 'visible' a reg insted of combo.

  assign hmax = (hpos == H_MAX);
  assign vmax = (vpos == V_MAX);
  assign visible = (hpos<H_VIEW && vpos<V_VIEW);

  // Horizontal tracing:
  always @(posedge clk) begin
          if (reset)                      hpos <= 0;
    else  if (hmax)                       hpos <= 0;
    else                                  hpos <= hpos + 1'b1;
  end

  // Vertical tracing:
  always @(posedge clk) begin
          if (reset)                      vpos <= 0;
    else  if (hmax)                       vpos <= (vmax) ? 10'd0 : vpos + 1'b1;
  end

  // HSYNC:
  always @(posedge clk) begin
          if (hpos==H_SYNC_END || reset)  hsync <= 0;
    else  if (hpos==H_SYNC_START)         hsync <= 1;
  end

  // VSYNC:
  always @(posedge clk) begin
          if (vpos==V_SYNC_END || reset)  vsync <= 0;
    else  if (vpos==V_SYNC_START)         vsync <= 1;
  end
endmodule
