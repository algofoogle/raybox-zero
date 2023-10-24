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
    input   wire            i_clk,            // Internal clock source signal.
    input   wire            i_reset_lock_a,   // Pair must have opposing values to release reset.
    input   wire            i_reset_lock_b,   // Pair must have opposing values to release reset.

    // RAW VGA outputs:
    output  wire            o_hsync,          // 
    output  wire            o_vsync,          // 
    output  wire    [23:0]  o_rgb,            // INTERNAL: rgb is BGR888, which go to DACs.
    // Only upper 2 bits of each channel used normally, but full range (if supported) can do depth shading.

    // SPI master for external texture memory:
    output  wire            o_tex_csb,        // /CS
    output  wire            o_tex_sclk,       // SCLK
    // SPI Quad IOs, including ports for different directions.
    //NOTE: We actually only switch io[0] (MOSI in single SPI mode) between OUTPUT and INPUT
    // when doing QSPI. The rest remain as inputs.
    output  wire            o_tex_oeb0,       // IO pad dir select. 0=output 1=input.
    output  wire            o_tex_out0,       // IO pad output path. Maps to SPI io[0] (typically MOSI).
    input   wire    [3:0]   i_tex_in,         // This includes i_tex_in[0] which is the above bi-dir IO pad's input path. Maps to SPI io[2:0]. io[3] as yet unused.

    // SPI slave 1: View vectors, to be controlled by LA:
    input   wire            i_vec_csb,        // 
    input   wire            i_vec_sclk,       // 
    input   wire            i_vec_mosi,       // 

    // SPI slave 2: General registers, to be controlled by LA:
    input   wire            i_reg_csb,        // 
    input   wire            i_reg_sclk,       // 
    input   wire            i_reg_mosi,       // 

    input   wire            i_debug_vec_overlay,
    input   wire            i_debug_map_overlay,
    input   wire            i_debug_trace_overlay,

    // Up to 6 'gpout's, actual source selectable from many, by 'i_gpout*_sel's...
    output  wire    [5:0]   o_gpout,
    input   wire    [5:0]   i_gpout0_sel,
    input   wire    [5:0]   i_gpout1_sel,
    input   wire    [5:0]   i_gpout2_sel,
    input   wire    [5:0]   i_gpout3_sel,
    input   wire    [5:0]   i_gpout4_sel,
    input   wire    [5:0]   i_gpout5_sel,

    // "Mode": Other stuff to control the design generally, e.g. demo mode.
    input   wire    [2:0]   i_mode
);

    // Our design will be held in reset unless reset_lock_a and reset_lock_b hold
    // opposing values (i.e. one must be high, the other low).
    // If both are 0, or both are 1, the design will remain in reset.
    wire rbzero_reset = ~(reset_lock_a ^ reset_lock_b);

    assign rbzero_clk = clk;

    wire [5:0] rbzero_rgb_out; //CHECK: What is the final bit depth we're using for EW CI submission?
    assign rgb = {
        // For each channel, we currently have 2 active bits, and 6 unused bits,
        // with each channel intended to go to a DAC as 8 bits.
        rbzero_rgb_out[5:4], 6'b0,  // Blue
        rbzero_rgb_out[3:2], 6'b0,  // Green
        rbzero_rgb_out[1:0], 6'b0   // Red
    };

    rbzero rbzero(
        .clk        (rbzero_clk),
        .reset      (rbzero_reset),
        // SPI slave interface for updating vectors:
        .i_ss_n     (i_vec_csb),
        .i_sclk     (i_vec_sclk),
        .i_mosi     (i_vec_mosi),
        // SPI slave interface for everything else:
        .i_reg_ss_n (i_reg_csb),
        .i_reg_sclk (i_reg_sclk),
        .i_reg_mosi (i_reg_mosi),
        // SPI slave interface for reading SPI flash memory (i.e. textures):
        .o_tex_csb  (o_tex_csb),
        .o_tex_sclk (o_tex_sclk),
        .o_tex_out0 (o_tex_out0),
        .o_tex_oeb0 (o_tex_oeb0),
        .i_tex_in   ({1'b0, i_tex_in}), //SMELL: io[3] 
        // Debug/demo signals:
        .i_debug    (i_debug_vec_overlay),
        .i_inc_px   (i_mode[0]),
        .i_inc_py   (i_mode[1]),
        // VGA outputs:
        .hsync_n    (o_hsync_n),
        .vsync_n    (o_vsync_n),
        .rgb        (rbzero_rgb_out)
        // UNUSED, but could be handy if attached to LA:
        //o_hblank, o_vblank, hpos, vpos.
    );
    
endmodule
