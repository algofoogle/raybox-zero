`default_nettype none
`timescale 1ns / 1ps

// Wrapper for raybox_zero module, targeting DE0-Nano board:
module raybox_zero_de0nano(
  input           CLOCK_50, // Onboard 50MHz clock
  output  [7:0]   LED,      // 8 onboard LEDs
  input   [1:0]   KEY,      // 2 onboard pushbuttons
  input   [3:0]   SW,       // 4 onboard DIP switches
  inout   [33:0]  gpio1,    // GPIO1
  input   [1:0]   gpio1_IN  // GPIO1 input-only pins
);

//=======================================================
//  PARAMETER declarations
//=======================================================


//=======================================================
//  REG/WIRE declarations
//=======================================================

  // K4..K1 external buttons board (K4 is top, K1 is bottom):
  wire [4:1] K = {gpio1[23], gpio1[21], gpio1[19], gpio1[17]};

  reg qr, qg, qb; // Register RGB outputs.

  wire r;
  wire g;
  wire b;
  wire hsync;
  wire vsync;
  wire speaker;

  wire rst;
  wire new_game_n;
  wire up_key_n;
  wire pause_n;
  wire down_key_n;

//=======================================================
//  Structural coding
//=======================================================

  assign gpio1[0] = qr;
  assign gpio1[1] = qg;
  assign gpio1[3] = qb;

  assign gpio1[5] = hsync;
  assign gpio1[7] = vsync;
  assign gpio1[9] = speaker;  // Sound the speaker on GPIO_19.
  assign LED[7]   = speaker;  // Also visualise speaker on LED7.

  //SMELL: This is a bad way to do clock dividing.
  // Can we instead use the built-in FPGA clock divider?
  reg clock_25; // VGA pixel clock of 25MHz is good enough. 25.175MHz is ideal (640x480x59.94)
  always @(posedge CLOCK_50) clock_25 <= ~clock_25;

  // Register RGB outputs, to avoid any combo logic propagation quirks
  // (which I don't think we need to worry about for HSYNC, VSYNC, and speaker because skew on those is fine):
  always @(posedge clock_25) begin
    {qr, qg, qb} <= {r, g, b};
  end

  //NOTE: We might not need this metastability avoidance for our simple (and not-time-critical) inputs:
  stable_sync reset   (.clk(clock_25), .d(!KEY[0]), .q(rst       ));
  stable_sync new_game(.clk(clock_25), .d( KEY[1]), .q(new_game_n));
  stable_sync up_key  (.clk(clock_25), .d(   K[4]), .q(up_key_n  ));
  stable_sync pause   (.clk(clock_25), .d(   K[3]), .q(pause_n   ));
  stable_sync down_key(.clk(clock_25), .d(   K[1]), .q(down_key_n));


  raybox_zero game(
    // --- Inputs: ---
    .clk        (clock_25),
    .reset      (rst),

    .new_game_n (new_game_n),
    .pause_n    (pause_n),
    .up_key_n   (up_key_n),
    .down_key_n (down_key_n),
    
    // --- Outputs: ---
    .hsync      (hsync),
    .vsync      (vsync),
    .red        (r),
    .green      (g),
    .blue       (b),
    .speaker    (speaker)
  );

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
