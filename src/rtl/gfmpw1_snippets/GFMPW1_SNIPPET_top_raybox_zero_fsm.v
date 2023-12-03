// **** GFMPW1_SNIPPET_top_raybox_zero_fsm.v: ****
// Snippet to instantiate Anton's top_raybox_zero_fsm macro in a GFMPW-1
// multi-project submission (i.e. in user_project_wrapper).
// 
// For IO pad mapping, see:
// https://github.com/algofoogle/journal/blob/master/0182-2023-12-03.md#test-6


// ---- ACTUAL SNIPPET STARTS BELOW THIS LINE ----


    //// BEGIN: INSTANTIATION OF ANTON'S DESIGN (top_raybox_zero_fsm) (GFMPW1_SNIPPET_top_raybox_zero_fsm) ---------------------

    // This snippet comes from here:
    // https://github.com/algofoogle/raybox-zero/blob/gf180/src/rtl/gfmpw1_snippets/GFMPW1_SNIPPET_top_raybox_zero_fsm.v

    wire rbz_fsm_clock_in = wb_clk_i;
    wire rbz_fsm_reset = wb_rst_i;
    wire rbz_fsm_reset_alt = rbz_fsm_la_in[0]; // Reset by SoC reset OR LA.
    wire [12:0] rbz_fsm_la_in = la_data_in[12:0]; // Can be reassigned, if desired.
    wire [15:0] a0s, a1s;                   // Low and high signals from our design that we can use to mix constants.
    assign io_out[34:19] = a0s[15:0]; // Irrelevant.
    assign io_out[7:0] = a0s[15:8];  // Irrelevant.

    wire rbz_fsm_tex_oeb0;
    assign io_oeb = {
        a0s[15:13],         // 37:35 are OUT
        a1s[15:0],          // 34:19 are IN
        rbz_fsm_tex_oeb0,   // 18 is bidir (tex_io0)
        a0s[12:3],          // 17:8 are OUT
        a1s[15:8],          // 7:0 are IN or not otherwise used (i.e. under SoC control).
    }; // 0001111111111111111*000000000011111111 where *=tex_io0 dir.

    top_raybox_zero_fsm top_raybox_zero_fsm(
    `ifdef USE_POWER_PINS
        .vdd(vdd),        // User area 1 1.8V power
        .vss(vss),        // User area 1 digital ground
    `endif

        .i_clk                  (rbz_fsm_clock_in),
        .i_reset                (rbz_fsm_reset),
        .i_reset_alt            (rbz_fsm_reset_alt),

        .zeros                  (a0s),  // A source of 16 constant '0' signals.
        .ones                   (a1s),  // A source of 16 constant '1' signals.

        .o_hsync                (io_out[8]),
        .o_vsync                (io_out[9]),
        .o_rgb                  (io_out[15:10]),

        .o_tex_csb              (io_out[16]),
        .o_tex_sclk             (io_out[17]),
        .o_tex_oeb0             (rbz_fsm_tex_oeb0), // My only bidirectional pad.
        .o_tex_out0             (io_out[18]),
        .i_tex_in               (io_in[21:18]),

        .i_vec_csb              (io_in[22]),
        .i_vec_sclk             (io_in[23]),
        .i_vec_mosi             (io_in[24]),

        .i_reg_csb              (io_in[25]),
        .i_reg_sclk             (io_in[26]),
        .i_reg_mosi             (io_in[27]),

        .i_debug_vec_overlay    (io_in[28]),
        .i_debug_map_overlay    (io_in[29]),
        .i_debug_trace_overlay  (io_in[30]),
        .i_reg_outs_enb         (io_in[31]),
        .i_mode                 (io_in[34:32]),

        .o_gpout                (io_out[37:35]),
        .i_gpout0_sel           (rbz_fsm_la_in[4:1]),
        .i_gpout1_sel           (rbz_fsm_la_in[8:5]),
        .i_gpout2_sel           (rbz_fsm_la_in[12:9])
    );

    //// END: INSTANTIATION OF ANTON'S DESIGN (top_raybox_zero_fsm) (GFMPW1_SNIPPET_top_raybox_zero_fsm) ---------------------
