`default_nettype none
`timescale 1ns / 1ps

module vga_sync(
    // Inputs:
    input wire          clk,
    input wire          reset,
    // Outputs:
    output reg          hsync,
    output reg          vsync,
    output reg [9:0]    hpos,
    output reg [9:0]    vpos,
    output wire         visible
);

    // 800 clocks wide:
    localparam H_VIEW       = 640;   // Visible area comes first...
    localparam H_FRONT      =  16;   // ...then HBLANK starts with H_FRONT (RHS border)...
    localparam H_SYNC       =  96;   // ...then sync pulse starts...
    localparam H_BACK       =  48;   // ...then remainder of HBLANK (LHS border).
    localparam H_MAX        = H_VIEW + H_FRONT + H_SYNC + H_BACK - 1;
    localparam H_SYNC_START = H_VIEW + H_FRONT;
    localparam H_SYNC_END   = H_SYNC_START + H_SYNC;
    // 525 lines tall:
    localparam V_VIEW       = 480;
    localparam V_FRONT      =  10;
    localparam V_SYNC       =   2;
    localparam V_BACK       =  33;
    localparam V_MAX        = V_VIEW + V_FRONT + V_SYNC + V_BACK - 1;
    localparam V_SYNC_START = V_VIEW + V_FRONT;
    localparam V_SYNC_END   = V_SYNC_START + V_SYNC;
    // Overall timing for true VGA 25.175MHz clock: 25,175,000 / 800 / 525 = 59.94Hz
    // or for 25.0MHz clock: 59.52Hz
    // Try pushing these timings around and see what happens.

    wire hmax = (hpos == H_MAX);
    wire vmax = (vpos == V_MAX);
    assign visible = (hpos<H_VIEW && vpos<V_VIEW);

    // Horizontal tracing:
    always @(posedge clk) begin
        if (reset)                          hpos <= 0;
        else if (hmax)                      hpos <= 0;
        else                                hpos <= hpos + 1;
    end

    // Vertical tracing:
    always @(posedge clk) begin
        if (reset)                          vpos <= 0;
        else if (hmax)                      vpos <= (vmax) ? 0 : vpos + 1;
    end

    // HSYNC:
    always @(posedge clk) begin
             if (hpos==H_SYNC_END || reset) hsync <= 0;
        else if (hpos==H_SYNC_START)        hsync <= 1;
    end

    // VSYNC:
    always @(posedge clk) begin
             if (vpos==V_SYNC_END || reset) vsync <= 0;
        else if (vpos==V_SYNC_START)        vsync <= 1;
    end
endmodule
