`default_nettype none
`timescale 1ns / 1ps

//NOTE: ONE of the following two DAC options should be defined:
//`define RGB1_DAC  // Target Anton's original RGB111 VGA DAC adapter with dithering.
`define RGB3_DAC  // Target Anton's RGB333 VGA DAC adapter.

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

  // Quartus-generated PLL module, generating 24MHz clock from system 50MHz source.
  // This is used as our pixel clock and system clock for the main DUT:
  // For more info see:
  // https://github.com/algofoogle/journal/blob/master/0165-2023-10-24.md#quartus-pll
  wire pixel_clock;
  pll pll_inst (
    .inclk0 (CLOCK_50),
    .c0     (pixel_clock)
  );

  // K4..K1 external buttons board (K4 is top, K1 is bottom):
  //NOTE: These buttons are active LOW, so we invert them here to make them active HIGH:
  wire [4:1] K = ~{gpio1[22], gpio1[21], gpio1[19], gpio1[17]};

  // LEDs just show that we're alive:
  assign LED[0] = ~hsync;
  assign LED[1] = ~vsync;
  assign LED[3:2] = 0;
  assign LED[7:4] = 4'b1111;

  // RGB222 outputs directly from the rbzero design:
  wire [5:0] rgb;
  // HSYNC and VSYNC out of rbzero design:
  wire hsync, vsync;  //NOTE: Inverted polarity; LOW during sync.
  // Pixel X/Y coming from rbzero, really only used if we're doing RGB1_DAC with dithering:
  wire [9:0] hpos, vpos;

  // Standard RESET coming from DE0-Nano's KEY0
  // (but note also 'any_reset' and its relationship to PicoDeo):
  wire reset;
  //NOTE: We might not need this metastability avoidance for our simple (and not-time-critical) inputs:
  stable_sync sync_reset (.clk(pixel_clock), .d(!KEY[0]), .q(reset));

`ifdef RGB1_DAC
  `ifdef RGB3_DAC
    //SMELL: $error not supported by Quartus unless we use SystemVerilog,
    // but at least this has the same effect of breaking the build:
    $error("Don't define RGB1_DAC and RGB3_DAC at the same time!");
  `endif
`endif

`ifdef RGB1_DAC

  // Implementation for Anton's older RGB111 VGA DAC adapter with dithering.
  /*
  Here's the pinout of the RGB111 DAC board as it applies to the DE0-Nano GPIO1 header:
    SIL header socket uses only LHS pins:
              |
              v
           |     |     | 
           +-----+-----+ 
      GND  | GND |VCCS |  (NC)
           +-----+-----+ 
    VSYNC  | io7 | io6 |  (NC)
           +-----+-----+ 
    HSYNC  | io5 | io4 |  (NC)
           +-----+-----+ 
        B  | io3 | io2 |  (NC)
           +-----+-----+ 
        G  | io1 | IN1 |  (NC)
           +-----+-----+ 
        R  | io0 | IN0 |  (NC)
           +-----+-----+ * PIN 1 of DE0-Nano GPIO1 header.
  */
  reg qr, qg, qb; // Register RGB outputs.
  wire r, g, b;

  assign gpio1[0] = qr;
  assign gpio1[1] = qg;
  assign gpio1[3] = qb;

  assign gpio1[5] = hsync;
  assign gpio1[7] = vsync;

  // Register RGB outputs, to avoid any combo logic propagation quirks
  // (which I don't think we need to worry about for HSYNC, VSYNC, and speaker because skew on those is fine):
  always @(posedge pixel_clock) {qr,qg,qb} <= {r,g,b};

  // Because actual RGB1_DAC hardware is only using MSB of each colour channel, attenuate that output
  // (i.e. mask it out for some pixels) to create a pattern dither:
  reg alt;
  always @(posedge pixel_clock) if (hpos==0 && vpos==0) alt <= ~alt; // Temporal dithering, i.e. flip patterns on odd frames.
  wire dither_hi = (px0^py0)^alt;
  wire dither_lo = (px0^alt)&(py0^alt);
  wire [1:0] rr = rgb[1:0];
  wire [1:0] gg = rgb[3:2];
  wire [1:0] bb = rgb[5:4];
  assign r = (rr==2'b11) ? 1'b1 : (rr==2'b10) ? dither_hi : (rr==2'b01) ? dither_lo : 1'b0;
  assign g = (gg==2'b11) ? 1'b1 : (gg==2'b10) ? dither_hi : (gg==2'b01) ? dither_lo : 1'b0;
  assign b = (bb==2'b11) ? 1'b1 : (bb==2'b10) ? dither_hi : (bb==2'b01) ? dither_lo : 1'b0;

`elsif RGB3_DAC

  // Implementation for Anton's newer RGB333 VGA DAC adapter,
  // though we only need to use the upper 2 bits of each channel since that's all rbzero gives us.
  /*
  Here's the pinout of the RGB333 DAC board as it applies to the DE0-Nano GPIO1 header:
           |     |     | 
           +-----+-----+ 
       G0  |io13 |io12 |  B0
           +-----+-----+ 
       G1  |io11 |io10 |  B1
           +-----+-----+ 
       G2  | io9 | io8 |  B2
           +-----+-----+ 
      GND  | GND |VCCS |  VCC_SYS
           +-----+-----+ 
    HSYNC  | io7 | io6 |  (NC)
           +-----+-----+ 
    VSYNC  | io5 | io4 |  (NC)
           +-----+-----+ 
       R0  | io3 | io2 |  (NC)
           +-----+-----+ 
       R1  | io1 | IN1 |  (NC)
           +-----+-----+ 
       R2  | io0 | IN0 |  (NC)
           +-----+-----+ * PIN 1 of DE0-Nano GPIO1 header.
  NOTE: Compared to RGB1_DAC, HSYNC and VSYNC are swapped.
  NOTE: NC pins are populated in the header as long pass-through pins so they can be used for other purposes.
  */

  reg [5:0] qrgb;
  // Register RGB outputs, to avoid any combo logic propagation quirks
  // (which I don't think we need to worry about for HSYNC, VSYNC, and speaker because skew on those is fine):
  always @(posedge pixel_clock) qrgb <= rgb;

  // Red:
  assign gpio1[  3] = 1'b0;   // Unused by rbzero; set to 0.
  assign gpio1[  1] = qrgb[0];
  assign gpio1[  0] = qrgb[1];
  // Green:
  assign gpio1[ 13] = 1'b0;   // Unused by rbzero; set to 0.
  assign gpio1[ 11] = qrgb[2];
  assign gpio1[  9] = qrgb[3];
  // Blue:
  assign gpio1[ 12] = 1'b0;   // Unused by rbzero; set to 0.
  assign gpio1[ 10] = qrgb[4];
  assign gpio1[  8] = qrgb[5];
  // HSYNC/VSYNC:
  assign gpio1[  7] = hsync;
  assign gpio1[  5] = vsync;

  // Just for safety; these are the bidir pins attached to (but not used by) the DAC board:
  assign gpio1[  2] = 1'bz;
  assign gpio1[  4] = 1'bz;
  assign gpio1[  6] = 1'bz;

`else

  //SMELL: $error not supported by Quartus unless we use SystemVerilog,
  // but at least this has the same effect of breaking the build:
  $error("Neither RGB1_DAC nor RGB3_DAC have been defined!");

`endif

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
  wire any_reset  = pico_gpio[21] | reset; // Reset can come from synchronised KEY[0] or from PicoDeo GPIO 21.

  // My Texture SPI flash ROM is wired up to my DE0-Nano as follows:
  /*

                           +-----+-----+
      (ROM pin 6) SCLK  40 |io33 |io32 | 39  N/C
                           +-----+-----+
                   N/C  38 |io31 |io30 | 37  io3 (ROM pin 7)
                           +-----+-----+
      (ROM pin 3)  io2  36 |io29 |io28 | 35  io0 (ROM pin 5) (MOSI)
                           +-----+-----+
                   N/C  34 |io27 |io26 | 33  io1 (ROM pin 2) (MISO)
                           +-----+-----+
      (ROM pin 1)  /CS  32 |io25 |io24 | 31  N/C
                           +-----+-----+
      (ROM pin 4)  GND  30 | GND |3.3V | 29  VCC (ROM pin 8)
                           +-----+-----+
                           |     |     |

  Thus, gpio1 mapping to SPI flash ROM is as follows:

  | gpio1 pin | gpio1[x]  | ROM pin | Function   |
  |----------:|----------:|--------:|------------|
  |     29    |    VCC3P3 |       8 | VCC3P3     |
  |     30    |       GND |       4 | GND        |
  |     31    | gpio1[24] |   (n/c) |            |
  |     32    | gpio1[25] |       1 | /CS        |
  |     33    | gpio1[26] |       2 | io1 (MISO) |
  |     34    | gpio1[27] |   (n/c) |            |
  |     35    | gpio1[28] |       5 | io0 (MOSI) |
  |     36    | gpio1[29] |       3 | io2        |
  |     37    | gpio1[30] |       7 | io3        |
  |     38    | gpio1[31] |   (n/c) |            |
  |     39    | gpio1[32] |   (n/c) |            |
  |     40    | gpio1[33] |       6 | SCLK       |

  */

  // Inputs from texture SPI ROM (per quad mode):
  wire [3:0] tex_in = {gpio1[30], gpio1[29], gpio1[26], gpio1[28]};
  // Outputs to texture SPI ROM:
  wire tex_csb, tex_sclk, tex_out0, tex_oeb0;
  assign gpio1[25] = tex_csb;
  assign gpio1[33] = tex_sclk;
  assign gpio1[28] = (tex_oeb0==0) ? tex_out0 : 1'bz; // When oeb0==1, gpio1[28] becomes an input, feeding tex_in[0].
  // assign tex_oeb0 = 0; // FORCED OUTPUT.

  rbzero game(
    // --- Inputs: ---
    .clk        (pixel_clock),
    .reset      (any_reset),
    // SPI:
    .i_sclk     (i_sclk),
    .i_mosi     (i_mosi),
    .i_ss_n     (i_ss_n),
    //SMELL: i_reg_* SPI is not connected!!!

    // Texture SPI flash ROM:
    .o_tex_csb  (tex_csb),
    .o_tex_sclk (tex_sclk),
    .o_tex_out0 (tex_out0),
    .o_tex_oeb0 (tex_oeb0),
    .i_tex_in   (tex_in),

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
