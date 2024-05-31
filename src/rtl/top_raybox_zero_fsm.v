`default_nettype none

// --- top_raybox_zero_fsm ---
// This is the top wrapper for raybox-zero, FSM version, when integrated in a
// GFMPW-1 multi-project caravel. See here for more info:
// https://github.com/algofoogle/journal/blob/master/0182-2023-12-03.md#test-6


module top_raybox_zero_fsm(
`ifdef USE_POWER_PINS
    inout vdd,
    inout vss,
`endif

    input   wire            i_clk,            // Clock source signal.
    input   wire            i_reset,
    // input   wire            i_reset_alt,        // Alternate reset.

    //NOTE: zeros and ones are no longer needed because mux takes care of OEBs...
    // // Provides constant sources of '0' and '1' values that can be used for wiring up different
    // // combinations of constants as required inside a user_project_wrapper (where only wires are
    // // allowed, and no cells OR instantiation of contants).
    // // I'm not certain, but I think providing multiple (i.e. vectors) like this is a good idea
    // // so we can conveniently do index ranges, but *also* so we don't get fanout problems from
    // // single constant driver cells...?
    // output  wire    [12:0]  zeros,              // Represents 13 outputs.
    // output  wire    [23:0]  ones,               // Represents 24 inputs.

    // RAW VGA outputs:
    output  wire            o_hsync,          // 
    output  wire            o_vsync,          // 
    output  wire    [5:0]   o_rgb,            // BBGGRR

    // SPI controller for external texture memory:
    output  wire            o_tex_csb,        // /CS
    output  wire            o_tex_sclk,       // SCLK
    // SPI Quad IOs, including ports for different directions.
    //NOTE: We actually only switch io[0] (MOSI in single SPI mode) between OUTPUT and INPUT
    // when doing QSPI. The rest remain as inputs.
    output  wire            o_tex_oeb0,       // IO pad dir select. 0=output 1=input.
    output  wire            o_tex_out0,       // IO pad output path. Maps to SPI io[0] (typically MOSI).
    input   wire    [3:0]   i_tex_in,         // This includes i_tex_in[0] which is the above bi-dir IO pad's input path. Maps to SPI io[2:0]. io[3] as yet unused.

    // SPI peripheral 1: View vectors:
    input   wire            i_vec_csb,        // 
    input   wire            i_vec_sclk,       // 
    input   wire            i_vec_mosi,       // 

    // SPI peripheral 2: General registers:
    input   wire            i_reg_csb,        // 
    input   wire            i_reg_sclk,       // 
    input   wire            i_reg_mosi,       // 

    input   wire            i_debug_vec_overlay,
    input   wire            i_debug_map_overlay,
    input   wire            i_debug_trace_overlay,
    input   wire            i_reg_outs_enb,     // Should our main display outputs be registered (0) or direct (1)?
    // "Mode": Other stuff to control the design generally, e.g. demo mode.
    input   wire    [2:0]   i_mode,

    // Up to 3 "gpout"s, actual source selectable from many, by "i_gpout*_sel"...
    output  wire    [2:0]   o_gpout,
    // gpout selection is expected to be done via LA, if at all:
    input   wire    [3:0]   i_gpout0_sel,
    input   wire    [3:0]   i_gpout1_sel,
    input   wire    [3:0]   i_gpout2_sel
);

    // // These are for caravel to hard-wire OEBs; 37 are fixed dir, 1 is bidir (via o_tex_oeb0):
    // assign zeros    = {13{1'b0}};
    // assign ones     = {24{1'b1}};

    wire [3:0] gpout0_sel, gpout1_sel, gpout2_sel;
    // wire reset_alt;
`ifdef REG_LA_INS
    // These are registered versions of i_gpout*_sel (2 cycle delay):
    stable_sync gpo0sel0R (i_clk, i_gpout0_sel[0], gpout0_sel[0]);
    stable_sync gpo0sel1R (i_clk, i_gpout0_sel[1], gpout0_sel[1]);
    stable_sync gpo0sel2R (i_clk, i_gpout0_sel[2], gpout0_sel[2]);
    stable_sync gpo0sel3R (i_clk, i_gpout0_sel[3], gpout0_sel[3]);
    stable_sync gpo1sel0R (i_clk, i_gpout1_sel[0], gpout1_sel[0]);
    stable_sync gpo1sel1R (i_clk, i_gpout1_sel[1], gpout1_sel[1]);
    stable_sync gpo1sel2R (i_clk, i_gpout1_sel[2], gpout1_sel[2]);
    stable_sync gpo1sel3R (i_clk, i_gpout1_sel[3], gpout1_sel[3]);
    stable_sync gpo2sel0R (i_clk, i_gpout2_sel[0], gpout2_sel[0]);
    stable_sync gpo2sel1R (i_clk, i_gpout2_sel[1], gpout2_sel[1]);
    stable_sync gpo2sel2R (i_clk, i_gpout2_sel[2], gpout2_sel[2]);
    stable_sync gpo2sel3R (i_clk, i_gpout2_sel[3], gpout2_sel[3]);
    // // Registered version of i_reset_alt (2 cycle delay):
    // stable_sync reset_altR (i_clk, i_reset_alt, reset_alt);
`else
    // Use LA inputs directly:
    assign {gpout0_sel, gpout1_sel, gpout2_sel} =
        {i_gpout0_sel, i_gpout1_sel, i_gpout2_sel};
`endif

    // These are the raw combinatorial signals.
    wire [2:0]  unreg_gpout;
    wire        unreg_hsync;
    wire        unreg_vsync;
    wire [5:0]  unreg_rgb;

    // These are registered versions of the signals above; 1-clock delay.
    reg [1:0]   reg_gpout;  //NOTE: gpout2 is ALWAYS UNregistered.
    reg         reg_hsync;
    reg         reg_vsync;
    reg [5:0]   reg_rgb;
    always @(posedge i_clk) begin
        if (rbzero_reset) begin
            reg_gpout   <= 0;
            reg_hsync   <= 0;
            reg_vsync   <= 0;
            reg_rgb     <= 0;
        end else begin
            reg_gpout   <= unreg_gpout[1:0];    //NOTE: gpout2 is ALWAYS UNregistered.
            reg_hsync   <= unreg_hsync;
            reg_vsync   <= unreg_vsync;
            reg_rgb     <= unreg_rgb;
        end
    end

    // Decide whether we are presenting raw combinatorial signals or registered versions:
    assign {o_gpout, o_hsync, o_vsync, o_rgb} =
        (0==i_reg_outs_enb) ?   {unreg_gpout[2],   reg_gpout,        reg_hsync,   reg_vsync,   reg_rgb}:
                                {unreg_gpout[2], unreg_gpout[1:0], unreg_hsync, unreg_vsync, unreg_rgb};
    //NOTE: gpout2 always provides an UNregsitered output, for these reasons:
    // - Ability to compare with registered equivalents above.
    // - Direct access to clk.
    // - Direct access to rbzero_reset.

    wire rbzero_reset = i_reset; // | reset_alt;

    wire rbzero_clk = i_clk;

    //SMELL: 'generate' these 3 instead, since they're pretty consistent...
    gpout_mux gpout0(
        //  Primary: HBLANK     Alt: hmax
        .sel(gpout0_sel), .gpout(unreg_gpout[0]), .primary(hblank), .alt(hmax),
            .clk(i_clk), .reset(rbzero_reset),
            .vec_csb(i_vec_csb),
            .reg_csb(i_reg_csb),
            .hpos(hpos), .vpos(vpos),
            .tex_oeb0(o_tex_oeb0), .tex_in(i_tex_in),
            .vinf(vinf)
    );
    gpout_mux gpout1(
        //  Primary: VBLANK     Alt: vmax
        .sel(gpout1_sel), .gpout(unreg_gpout[1]), .primary(vblank), .alt(vmax),
            .clk(i_clk), .reset(rbzero_reset),
            .vec_csb(i_vec_csb),
            .reg_csb(i_reg_csb),
            .hpos(hpos), .vpos(vpos),
            .tex_oeb0(o_tex_oeb0), .tex_in(i_tex_in),
            .vinf(vinf)
    );
    //NOTE: gpout2 always provides an UNregsitered output, for these reasons:
    // - Ability to compare with registered equivalents above.
    // - Direct access to clk.
    // - Direct access to rbzero_reset.
    gpout_mux gpout2(
        //  Primary: rbzero_reset    Alt: i_clk
        .sel(gpout2_sel), .gpout(unreg_gpout[2]), .primary(rbzero_reset), .alt(i_clk),
            .clk(i_clk), .reset(rbzero_reset),
            .vec_csb(i_vec_csb),
            .reg_csb(i_reg_csb),
            .hpos(hpos), .vpos(vpos),
            .tex_oeb0(o_tex_oeb0), .tex_in(i_tex_in),
            .vinf(vinf)
    );

    wire [5:0] rbzero_rgb_out;
    assign unreg_rgb = {
        rbzero_rgb_out[5:4],  // Blue
        rbzero_rgb_out[3:2],  // Green
        rbzero_rgb_out[1:0]   // Red
    };

    wire hblank, vblank, hmax, vmax;
    wire [9:0] hpos, vpos;
    wire vinf;

    rbzero rbzero(
        .clk        (rbzero_clk),
        .reset      (rbzero_reset),
        // SPI peripheral interface for updating vectors:
        .i_ss_n     (i_vec_csb),
        .i_sclk     (i_vec_sclk),
        .i_mosi     (i_vec_mosi),
        // SPI peripheral interface for everything else:
        .i_reg_ss_n (i_reg_csb),
        .i_reg_sclk (i_reg_sclk),
        .i_reg_mosi (i_reg_mosi),
        // SPI controller interface for reading SPI flash memory (i.e. textures):
        .o_tex_csb  (o_tex_csb),
        .o_tex_sclk (o_tex_sclk),
        .o_tex_out0 (o_tex_out0),
        .o_tex_oeb0 (o_tex_oeb0),
        .i_tex_in   (i_tex_in), //NOTE: io[3] is unused, currently.
        // Debug/demo signals:
        .i_debug_v  (i_debug_vec_overlay),
        .i_debug_m  (i_debug_map_overlay),
        .i_debug_t  (i_debug_trace_overlay),
        .i_inc_px   (i_mode[0]),
        .i_inc_py   (i_mode[1]),
        .i_gen_tex  (i_mode[2]), // 1=Use bitwise-generated textures instead of SPI texture memory.
        .o_vinf     (vinf),
        .o_hmax     (hmax),
        .o_vmax     (vmax),
        // VGA outputs:
        .hsync_n    (unreg_hsync),
        .vsync_n    (unreg_vsync),
        .rgb        (rbzero_rgb_out),
        .o_hblank   (hblank),
        .o_vblank   (vblank),
        .hpos       (hpos),
        .vpos       (vpos)
    );
    
endmodule


module gpout_mux(
    input   wire            clk,        // Used for the clk OUTPUT options.
    input   wire            reset,      // Used to clear the clk divider register.
    input   wire    [3:0]   sel,        // Which of 16 inputs is the one we'll output via gpout?
    output  reg             gpout,      // The actual selected output.
    input   wire            primary,    // If sel==0, this is what gets sent to gpout.
    input   wire            alt,        // If sel==1, this is an alternate sent to gpout.
    // All the rest are consistent between instances...
    input   wire            vec_csb,
    input   wire            reg_csb,
    input   wire            tex_oeb0,
    input   wire    [3:0]   tex_in,
    input   wire    [9:0]   hpos,
    input   wire    [9:0]   vpos,
    input   wire            vinf
);

    reg [1:0] clk_div;
    always @(posedge clk) clk_div <= (reset) ? 0 : clk_div+1'b1;

    // Note that this works because gpout is defined as 'reg', but with
    // no edge sensitivity it synthesises automatically to combo logic (a mux)
    // rather than a true register.
    // See: https://electronics.stackexchange.com/a/240014
    always @*
        case (sel)
            4'd00:  gpout = primary;
            4'd01:  gpout = alt;
            4'd02:  gpout = vinf;
            4'd03:  gpout = clk_div[1]; // clk/4
            4'd04:  gpout = hpos[0];
            4'd05:  gpout = hpos[1];
            4'd06:  gpout = hpos[8];
            4'd07:  gpout = hpos[9];
            4'd08:  gpout = vpos[0];
            4'd09:  gpout = vpos[1];
            4'd10:  gpout = vpos[8];
            4'd11:  gpout = vpos[9];
            4'd12:  gpout = tex_oeb0;
            4'd13:  gpout = tex_in[0];
            4'd14:  gpout = vec_csb;
            4'd15:  gpout = reg_csb;
        endcase
endmodule

// Metastability avoidance; chained DFFs:
module stable_sync #(
  parameter DEPTH=2
) (
  input clk,
  input d,
  output q
);
  reg [DEPTH-1:0] chain;
  assign q = chain[DEPTH-1];
  always @(posedge clk) chain[DEPTH-1:0] <= {chain[DEPTH-2:0],d};
endmodule
