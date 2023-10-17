`default_nettype none
`timescale 1ns / 1ps

// This is the top wrapper for the algofoogle (Anton Maurovic) raybox-zero design
// that is intended to be included as a GDS macro in the EllenWood chipIgnite
// Caravel submission.
//
// It defines the expected digital ports that will ultimately be needed.
// Some will be wired up to external IOs (or muxed), some to LA, some to a DAC circuit,
// and others like CLK and RESET might be common. There might also be a power gate,
// but probably not part of this level of the design.

module top_ew_algofoogle(
    input   wire            clk,        // IO[0]?? External or internal/shared?
    input   wire            reset,      // LA[0]?
    input   wire            ena,        // Maybe gate clock internally and force reset?
    output  wire            debug,      // IO[9]: Muxable between different functions, select via LA?

    // RAW VGA outputs:
    output  wire            hsync_n,    // IO[1]
    output  wire            vsync_n,    // IO[2]
    output  wire    [23:0]  rgb,        // INTERNAL: rgb is BGR888, which go to DACs.
    // Only upper 2 bits of each channel used normally, but full range (if supported) can do depth shading.

    // SPI master for external texture memory:
    output  wire            tex_csb,    // IO[3]
    output  wire            tex_sclk,   // IO[4]
    // SPI Quad IOs, including ports for different directions:
    output  wire    [3:0]   tex_oeb,    // IO[8:5] dir select.  0=output 1=input. Startup: 1110.
    output  wire    [3:0]   tex_out,    // IO[8:5] output path. Maps to SPI io[3:0]. io[0] is typically MOSI.
    input   wire    [3:0]   tex_in,     // IO[8:5] input path.  Maps to SPI io[3:0]. io[1] is typically MISO.

    // SPI slave 1: View vectors, to be controlled by LA:
    input   wire            vec_csb,    // LA[1]
    input   wire            vec_sclk,   // LA[2]
    input   wire            vec_mosi,   // LA[3]

    // SPI slave 2: General registers, to be controlled by LA:
    input   wire            reg_csb,    // LA[4]
    input   wire            reg_sclk,   // LA[5]
    input   wire            reg_mosi,   // LA[6]

    // Debug select stuff: Select one of 64 signals to output via 'debug' pin.
    input   wire    [5:0]   debug_sel,  // LA[12:7]

    // "Mode": Other stuff to control the design generally, e.g. demo mode.
    input   wire    [2:0]   mode        // LA[15:13]
);

    // ena high: Normal clk and reset inputs.
    // ena low:  Force inactive state.
    wire rbzero_clk     = ena ? clk     : 0;
    wire rbzero_reset   = ena ? reset   : 1;

    /*
    // assign debug = ? // Muxed debug output.
    Possible debug options:
    - 0: hsync_n (in case we have to share)
    - 1: vsync_n (in case we have to share)
    - 2: clk
    - 3: clk/2
    - 4: clk/4
    - 5: mode[0]
    - 6: mode[1]
    - 7: mode[2]
    - 8..31: each of 24 RGB output bits, pre DAC
    - 32: vec_csb
    - 33: vec_sclk
    - 34: vec_mosi
    - 35: reg_csb
    - 36: reg_sclk
    - 37: reg_mosi
    - 38..47: hpos[0:9]
    - 48..57: vpos[0:9]
    - 58: tex_oeb[0]??
    - 59: tex_oeb[1]??
    - 60..63: RESERVED (see debug/map overlay options below).
    //SMELL: What do we output for 60..63? Some vector bits, maybe? Parity of vector integer parts?
    */

    // debug_sel is usually 1 of 64 values, but the upper 4 (60..63) are:
    // 1111-- 
    // ----o- o = Show debug overlay
    // -----m m = Show map overlay
    // These disable any other specific debug output, preferring instead to show something visually on screen.
    wire rbzero_show_debug_overlays = (debug_sel[5:1] == 5'b11111);
    //SMELL: Why not just use 2 more LA pins for this?
    //SMELL: 60 doesn't really make sense because it's neither overlay, nor any other debug selection.

    wire [5:0] rbzero_rgb_out; //CHECK: What is the final bit depth we're using for EW CI submission?
    assign rgb = {
        // For each channel, we currently have 2 active bits, and 6 unused bits:
        rbzero_rgb_out[5:4], 6'b0,  // Blue
        rbzero_rgb_out[3:2], 6'b0,  // Green
        rbzero_rgb_out[1:0], 6'b0   // Red
    };

    // For now, just use single SPI instead of Quad SPI:
    assign tex_oeb = 4'b1110;   // Just io0 (MOSI) is output for now.

    rbzero rbzero(
        .clk        (rbzero_clk),
        .reset      (rbzero_reset),
        // SPI slave interface for updating vectors:
        .i_ss_n     (vec_csb),
        .i_sclk     (vec_sclk),
        .i_mosi     (vec_mosi),
        // SPI slave interface for everything else:
        .i_reg_sclk (reg_csb),
        .i_reg_mosi (reg_sclk),
        .i_reg_ss_n (reg_mosi),
        // SPI slave interface for reading SPI flash memory (i.e. textures):
        .o_tex_csb  (tex_csb),
        .o_tex_sclk (tex_sclk),
        .o_tex_mosi (tex_out[0]),   // Might change when we implement QSPI.
        .i_tex_miso (tex_in[1]),    // Might change when we implement QSPI.
        // Debug/demo signals:
        .i_debug    (rbzero_show_debug_overlays),
        .i_inc_px   (mode[0]),
        .i_inc_py   (mode[1]),
        // VGA outputs:
        .hsync_n    (hsync_n),
        .vsync_n    (vsync_n),
        .rgb        (rbzero_rgb_out)
    );
    
endmodule
