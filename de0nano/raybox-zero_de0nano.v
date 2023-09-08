`default_nettype none
`timescale 1ns / 1ps

`define QUARTUS

// Wrapper for raybox_zero module, targeting DE0-Nano board:
module raybox_zero_de0nano(
  input           CLOCK_50, // Onboard 50MHz clock
  output  [7:0]   LED,      // 8 onboard LEDs
  input   [1:0]   KEY,      // 2 onboard pushbuttons
  input   [3:0]   SW,       // 4 onboard DIP switches

  input  [33:0]   gpio0,    //NOTE: For safety these are currently set as input-only, since Pi Pico connects directly to these.
  input   [1:0]   gpio0_IN,

  inout  [33:0]   gpio1,    // GPIO1
  input   [1:0]   gpio1_IN  // GPIO1 input-only pins
);

//=======================================================
//  PARAMETER declarations
//=======================================================


//=======================================================
//  REG/WIRE declarations
//=======================================================

  // K4..K1 external buttons board (K4 is top, K1 is bottom):
  //NOTE: These buttons are active LOW, so we invert them here to make them active HIGH:
  wire [4:1] K = ~{gpio1[23], gpio1[21], gpio1[19], gpio1[17]};

  reg qr, qg, qb; // Register RGB outputs.

  wire r;
  wire g;
  wire b;
  wire hsync;
  wire vsync;
  // wire speaker;

  wire reset;
  // wire new_game_n;
  // wire up_key_n;
  // wire pause_n;
  // wire down_key_n;

//=======================================================
//  Structural coding
//=======================================================

  assign gpio1[0] = qr;
  assign gpio1[1] = qg;
  assign gpio1[3] = qb;

  assign gpio1[5] = hsync;
  assign gpio1[7] = vsync;
  // assign gpio1[9] = speaker;  // Sound the speaker on GPIO_19.
  // assign LED[7]   = speaker;  // Also visualise speaker on LED7.

  //SMELL: This is a bad way to do clock dividing.
  // Can we instead use the built-in FPGA clock divider?
  reg clock_25; // VGA pixel clock of 25MHz is good enough. 25.175MHz is ideal (640x480x59.94)
  always @(posedge CLOCK_50) clock_25 <= ~clock_25;

  // Register RGB outputs, to avoid any combo logic propagation quirks
  // (which I don't think we need to worry about for HSYNC, VSYNC, and speaker because skew on those is fine):
  always @(posedge clock_25) begin
    {qr, qg, qb} <= {r, g, b};
  end

  // //NOTE: We might not need this metastability avoidance for our simple (and not-time-critical) inputs:
  stable_sync sync_reset   (.clk(clock_25), .d(!KEY[0]), .q(reset     ));
  // stable_sync new_game(.clk(clock_25), .d( KEY[1]), .q(new_game_n));
  // stable_sync up_key  (.clk(clock_25), .d(   K[4]), .q(up_key_n  ));
  // stable_sync pause   (.clk(clock_25), .d(   K[3]), .q(pause_n   ));
  // stable_sync down_key(.clk(clock_25), .d(   K[1]), .q(down_key_n));


  wire [5:0] rgb;
  // Because actual hardware is only using MSB of each colour channel, attenuate that output
  // (i.e. mask it out for some pixels) to create a pattern dither:
  reg alt; //fr0;
  always @(posedge clock_25) if (hpos==0 && vpos==0) alt <= ~alt; // Temporal dithering, i.e. flip patterns on odd frames.
  wire dither_hi = (px0^py0)^alt;
  wire dither_lo = (px0^alt)&(py0^alt);
  wire [1:0] rr = rgb[1:0];
  wire [1:0] gg = rgb[3:2];
  wire [1:0] bb = rgb[5:4];
  assign r = (rr==2'b11) ? 1'b1 : (rr==2'b10) ? dither_hi : (rr==2'b01) ? dither_lo : 1'b0;
  assign g = (gg==2'b11) ? 1'b1 : (gg==2'b10) ? dither_hi : (gg==2'b01) ? dither_lo : 1'b0;
  assign b = (bb==2'b11) ? 1'b1 : (bb==2'b10) ? dither_hi : (bb==2'b01) ? dither_lo : 1'b0;

  // Pico to DE0-Nano GPIO mapping: https://github.com/algofoogle/journal/blob/master/0094-2023-06-12.md#pin-mapping-chart
  wire [29:0] pico_gpio = {
    1'b0,       // 29 - NC
    gpio0[ 9],  // 28
    gpio0[13],  // 27
    gpio0[15],  // 26
    1'b0,       // 25 - NC
    1'b0,       // 24 - NC
    1'b0,       // 23 - NC
    gpio0[19],  // 22
    gpio0[23],  // 21
    gpio0[11],  // 20
    gpio0[25],  // 19
    gpio0[27],  // 18
    gpio0[31],  // 17
    gpio0[33],  // 16
    gpio0[32],  // 15
    gpio0[30],  // 14
    gpio0[26],  // 13
    gpio0[24],  // 12
    gpio0[28],  // 11
    gpio0[22],  // 10
    gpio0[18],  //  9
    gpio0[16],  //  8
    gpio0[14],  //  7
    gpio0[12],  //  6
    gpio0[ 8],  //  5
    gpio0[20],  //  4
    gpio0[ 6],  //  3
    gpio0[ 4],  //  2
    gpio0[10],  //  1
    gpio0[ 2],  //  0
  };

  // These are our unsynchronised inputs (i.e. different clock domain):
  wire i_sclk     = pico_gpio[28];
  wire i_mosi     = pico_gpio[27];
  wire i_ss_n     = pico_gpio[26];
  wire i_debug    = pico_gpio[22] | K[4];
  wire i_inc_px   = K[1];
  wire i_inc_py   = K[2];
  wire any_reset  = pico_gpio[21] | reset; // Reset can come from syncronised KEY[0] or from PicoDeo GPIO 21.

  rbzero game(
    // --- Inputs: ---
    .clk        (clock_25),
    .reset      (any_reset),
    // SPI:
    .i_sclk     (i_sclk),
    .i_mosi     (i_mosi),
    .i_ss_n     (i_ss_n),
    // Debug/Demo:
    .i_debug    (i_debug),
    .i_inc_px   (i_inc_px),
    .i_inc_py   (i_inc_py),

    // --- Outputs: ---
    .hsync_n    (hsync),
    .vsync_n    (vsync),
    .rgb        (rgb),
    // Just used to get low bit for dithering:
    .hpos       (hpos),
    .vpos       (vpos)
  );

  wire [9:0] hpos, vpos;
  wire px0 = hpos[0]; // Bit 0 of VGA pixel X position.
  wire py0 = vpos[0]; // Bit 0 of VGA pixel Y position.


endmodule

// Metastability avoidance; two chained DFFs:
module stable_sync(
  input clk,
  input d,
  output q
);
  reg dff1, dff2;
  assign q = dff2;
  always @(posedge clk) begin
    dff1 <= d;
    dff2 <= dff1;
  end
endmodule
