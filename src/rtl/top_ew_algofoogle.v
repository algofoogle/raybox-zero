`default_nettype none
// `timescale 1ns / 1ps

// This is the top wrapper for the algofoogle (Anton Maurovic) raybox-zero design
// that is intended to be included as a GDS macro in the EllenWood chipIgnite
// Caravel submission.
//
// It defines the expected digital ports that will ultimately be needed.


module top_ew_algofoogle(
`ifdef USE_POWER_PINS
    inout vccd1,
    inout vssd1,
`endif

    input   wire            i_clk,            // Clock source signal.
    input   wire            i_test_wci,       // Not actually used by our design; provided here just for loopback testing via gpout[1]:alt
    input   wire            i_test_uc2,       // As with i_test_wb_clk_i, this is a means to do loopback testing on user_clock2
    input   wire            i_la_invalid,     // Check a la_oenb bit; if 1, LAs are misconfigured (i.e. they're not being driven by the SoC).
    input   wire            i_reset_lock_a,   // Pair must have opposing values to release reset.
    input   wire            i_reset_lock_b,   // Pair must have opposing values to release reset.
    output  wire            o_reset,          // Actual reset state, internally, for debugging.

    // Provides constant sources of '0' and '1' values that can be used for wiring up different
    // combinations of constants as required inside a user_project_wrapper (where only wires are
    // allowed, and no cells OR instantiation of contants).
    // I'm not certain, but I think providing multiple (i.e. vectors) like this is a good idea
    // so we can conveniently do index ranges, but *also* so we don't get fanout problems from
    // single constant driver cells...?
    output  wire    [15:0]  zeros,
    output  wire    [15:0]  ones,

    // RAW VGA outputs:
    output  wire            o_hsync,          // 
    output  wire            o_vsync,          // 
    output  wire    [23:0]  o_rgb,            // INTERNAL: rgb is BGR888, which go to DACs.
    // Only upper 2 bits of each channel used normally, but full range (if supported) can do depth shading.

    // SPI controller for external texture memory:
    output  wire            o_tex_csb,        // /CS
    output  wire            o_tex_sclk,       // SCLK
    // SPI Quad IOs, including ports for different directions.
    //NOTE: We actually only switch io[0] (MOSI in single SPI mode) between OUTPUT and INPUT
    // when doing QSPI. The rest remain as inputs.
    output  wire            o_tex_oeb0,       // IO pad dir select. 0=output 1=input.
    output  wire            o_tex_out0,       // IO pad output path. Maps to SPI io[0] (typically MOSI).
    input   wire    [3:0]   i_tex_in,         // This includes i_tex_in[0] which is the above bi-dir IO pad's input path. Maps to SPI io[2:0]. io[3] as yet unused.

    // SPI peripheral 1: View vectors, to be controlled by LA:
    input   wire            i_vec_csb,        // 
    input   wire            i_vec_sclk,       // 
    input   wire            i_vec_mosi,       // 

    // SPI peripheral 2: General registers, to be controlled by LA:
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

    input   wire            i_reg_outs_enb,     // Should our main display outputs be registered (0) or direct (1)?
    input   wire            i_spare_0,          // Reserved.
    input   wire            i_spare_1,          // Reserved.

    // "Mode": Other stuff to control the design generally, e.g. demo mode.
    input   wire    [2:0]   i_mode
);

    assign zeros    = {16{1'b0}};
    assign ones     = {16{1'b1}};

    // These are the raw combinatorial signals.
    wire [5:0]  unreg_gpout;
    wire        unreg_hsync;
    wire        unreg_vsync;
    wire [23:0] unreg_rgb;

    // These are registered versions of the signals above; 1-clock delay.
    reg [5:0]   reg_gpout;
    reg         reg_hsync;
    reg         reg_vsync;
    reg [23:0]  reg_rgb;
    always @(posedge i_clk) begin
        if (rbzero_reset) begin
            reg_gpout   <= 0;
            reg_hsync   <= 0;
            reg_vsync   <= 0;
            reg_rgb     <= 0;
        end else begin
            reg_gpout   <= unreg_gpout;
            reg_hsync   <= unreg_hsync;
            reg_vsync   <= unreg_vsync;
            reg_rgb     <= unreg_rgb;
        end
    end

    // Decide whether we are presenting raw combinatorial signals or registered versions:
    assign {o_gpout, o_hsync, o_vsync, o_rgb} =
        (0==i_reg_outs_enb) ?   {reg_gpout, reg_hsync, reg_vsync, reg_rgb}:
                                {unreg_gpout, unreg_hsync, unreg_vsync, unreg_rgb};

    // Our design will be held in reset unless reset_lock_a and reset_lock_b hold
    // opposing values (i.e. one must be high, the other low).
    // If both are 0, or both are 1, the design will remain in reset.
    wire rbzero_reset = ~(i_reset_lock_a ^ i_reset_lock_b);
    assign o_reset = rbzero_reset;

    wire rbzero_clk = i_clk;

    //SMELL: 'generate' these 6 instead, since they're pretty consistent...
    gpout_mux gpout0(
        //  Primary: Green[0]
        .sel(i_gpout0_sel), .gpout(unreg_gpout[0]), .primary(rbzero_rgb_out[2]), .alt(rbzero_reset),
            .clk(i_clk), .reset(rbzero_reset),
            .vec_csb(i_vec_csb), .vec_sclk(i_vec_sclk), .vec_mosi(i_vec_mosi),
            .reg_csb(i_reg_csb), .reg_sclk(i_reg_sclk), .reg_mosi(i_reg_mosi),
            .hblank(hblank), .vblank(vblank),
            .hpos(hpos), .vpos(vpos),
            .tex_oeb0(o_tex_oeb0), .tex_in(i_tex_in),
            .mode(i_mode), .rgb(unreg_rgb)
    );
    gpout_mux gpout1(
        //  Primary: Green[1]
        .sel(i_gpout1_sel), .gpout(unreg_gpout[1]), .primary(rbzero_rgb_out[3]), .alt(i_test_wci),
            .clk(i_clk), .reset(rbzero_reset),
            .vec_csb(i_vec_csb), .vec_sclk(i_vec_sclk), .vec_mosi(i_vec_mosi),
            .reg_csb(i_reg_csb), .reg_sclk(i_reg_sclk), .reg_mosi(i_reg_mosi),
            .hblank(hblank), .vblank(vblank),
            .hpos(hpos), .vpos(vpos),
            .tex_oeb0(o_tex_oeb0), .tex_in(i_tex_in),
            .mode(i_mode), .rgb(unreg_rgb)
    );
    gpout_mux gpout2(
        //  Primary: Red[0]
        .sel(i_gpout2_sel), .gpout(unreg_gpout[2]), .primary(rbzero_rgb_out[0]), .alt(i_test_uc2),
            .clk(i_clk), .reset(rbzero_reset),
            .vec_csb(i_vec_csb), .vec_sclk(i_vec_sclk), .vec_mosi(i_vec_mosi),
            .reg_csb(i_reg_csb), .reg_sclk(i_reg_sclk), .reg_mosi(i_reg_mosi),
            .hblank(hblank), .vblank(vblank),
            .hpos(hpos), .vpos(vpos),
            .tex_oeb0(o_tex_oeb0), .tex_in(i_tex_in),
            .mode(i_mode), .rgb(unreg_rgb)
    );
    gpout_mux gpout3(
        //  Primary: Red[1]
        .sel(i_gpout3_sel), .gpout(unreg_gpout[3]), .primary(rbzero_rgb_out[1]), .alt(i_reset_lock_b),
            .clk(i_clk), .reset(rbzero_reset),
            .vec_csb(i_vec_csb), .vec_sclk(i_vec_sclk), .vec_mosi(i_vec_mosi),
            .reg_csb(i_reg_csb), .reg_sclk(i_reg_sclk), .reg_mosi(i_reg_mosi),
            .hblank(hblank), .vblank(vblank),
            .hpos(hpos), .vpos(vpos),
            .tex_oeb0(o_tex_oeb0), .tex_in(i_tex_in),
            .mode(i_mode), .rgb(unreg_rgb)
    );
    gpout_mux gpout4(
        // Primary: Blue[0]
        .sel(i_gpout4_sel), .gpout(unreg_gpout[4]), .primary(rbzero_rgb_out[4]), .alt(i_debug_vec_overlay),
            .clk(i_clk), .reset(rbzero_reset),
            .vec_csb(i_vec_csb), .vec_sclk(i_vec_sclk), .vec_mosi(i_vec_mosi),
            .reg_csb(i_reg_csb), .reg_sclk(i_reg_sclk), .reg_mosi(i_reg_mosi),
            .hblank(hblank), .vblank(vblank),
            .hpos(hpos), .vpos(vpos),
            .tex_oeb0(o_tex_oeb0), .tex_in(i_tex_in),
            .mode(i_mode), .rgb(unreg_rgb)
    );
    gpout_mux gpout5(
        // Primary: Blue[1]
        .sel(i_gpout5_sel), .gpout(unreg_gpout[5]), .primary(rbzero_rgb_out[5]), .alt(1'b0),
            .clk(i_clk), .reset(rbzero_reset),
            .vec_csb(i_vec_csb), .vec_sclk(i_vec_sclk), .vec_mosi(i_vec_mosi),
            .reg_csb(i_reg_csb), .reg_sclk(i_reg_sclk), .reg_mosi(i_reg_mosi),
            .hblank(hblank), .vblank(vblank),
            .hpos(hpos), .vpos(vpos),
            .tex_oeb0(o_tex_oeb0), .tex_in(i_tex_in),
            .mode(i_mode), .rgb(unreg_rgb)
    );

    wire [5:0] rbzero_rgb_out; //CHECK: What is the final bit depth we're using for EW CI submission?
    assign unreg_rgb = {
        // For each channel, we currently have 2 active bits, and 6 unused bits,
        // with each channel intended to go to a DAC as 8 bits.
        rbzero_rgb_out[5:4], 6'b0,  // Blue
        rbzero_rgb_out[3:2], 6'b0,  // Green
        rbzero_rgb_out[1:0], 6'b0   // Red
    };

    wire hblank, vblank;
    wire [9:0] hpos, vpos;

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
    input   wire    [5:0]   sel,        // Which of 64 inputs is the one we'll output via gpout?
    output  reg             gpout,      // The actual selected output.
    input   wire            primary,    // If sel==0, this is what gets sent to gpout.
    input   wire            alt,        // If sel==1, this is an alternate sent to gpout.
    // All the rest are consistent between instances...
    input   wire            vec_csb,
    input   wire            vec_sclk,
    input   wire            vec_mosi,
    input   wire            reg_csb,
    input   wire            reg_sclk,
    input   wire            reg_mosi,
    input   wire            hblank,
    input   wire            vblank,
    input   wire            tex_oeb0,
    input   wire    [3:0]   tex_in,
    input   wire    [2:0]   mode,
    input   wire    [9:0]   hpos,
    input   wire    [9:0]   vpos,
    input   wire    [23:0]  rgb
);

    reg [1:0] clk_div;
    always @(posedge clk) clk_div <= (reset) ? 0 : clk_div+1'b1;

    // Note that this works because gpout is defined as 'reg', but with
    // no edge sensitivity it synthesises automatically to combo logic (a mux)
    // rather than a true register.
    // See: https://electronics.stackexchange.com/a/240014
    always @*
        case (sel)
            6'd00:  gpout = primary;
            6'd01:  gpout = alt;
            6'd02:  gpout = clk;
            6'd03:  gpout = clk_div[1]; // clk/4
            6'd04:  gpout = tex_in[3];
            6'd05:  gpout = vec_csb;
            6'd06:  gpout = vec_sclk;
            6'd07:  gpout = vec_mosi;
            6'd08, 6'd09, 6'd10, 6'd11, 6'd12, 6'd13, 6'd14, 6'd15,
            6'd16, 6'd17, 6'd18, 6'd19, 6'd20, 6'd21, 6'd22, 6'd23,
            6'd24, 6'd25, 6'd26, 6'd27, 6'd28, 6'd29, 6'd30, 6'd31:
                    gpout = rgb[sel-8];
            6'd32:  gpout = reg_csb;
            6'd33:  gpout = reg_sclk;
            6'd34:  gpout = reg_mosi;
            6'd35:  gpout = hblank;
            6'd36:  gpout = vblank;
            6'd37:  gpout = tex_oeb0;
            6'd38:  gpout = tex_in[0];
            6'd39:  gpout = tex_in[1];
            6'd40:  gpout = tex_in[2];
            6'd41:  gpout = mode[0];
            6'd42:  gpout = mode[1];
            6'd43:  gpout = mode[2];
            6'd44, 6'd45, 6'd46, 6'd47, 6'd48,
            6'd49, 6'd50, 6'd51, 6'd52, 6'd53:
                    gpout = hpos[sel-44];
            6'd54, 6'd55, 6'd56, 6'd57, 6'd58,
            6'd59, 6'd60, 6'd61, 6'd62, 6'd63:
                    gpout = vpos[sel-54];
        endcase
endmodule
