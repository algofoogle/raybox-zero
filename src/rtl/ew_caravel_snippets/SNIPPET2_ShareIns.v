// **** SNIPPET2_ShareIns.v: ****
// Snippet to instantiate Anton's top_ew_algofoogle macro IF we can share
// up to 4 digital inputs, e.g. Anton has 9 dedicated IO pads, and can
// piggy-back off up to 4 other digital INPUT-ONLY pads.
// 
// I've assumed the other 4 shared INPUT IO pads are DIGITAL 35,34, 32,31. NOT 33.
//
// For more info, see EWSPEC:
// https://github.com/algofoogle/raybox-zero/blob/ew/doc/EWSPEC.md#if-9-pads-available-plus-extra-sharedmuxed-inputs
//
// Here's what I'd prefer to have added to user_defines.v for my assigned IO pads:
// `define USER_CONFIG_GPIO_11_INIT `GPIO_MODE_USER_STD_INPUT_NOPULL // Reassigned from Ellen to Anton, to use as main clock.
// `define USER_CONFIG_GPIO_18_INIT `GPIO_MODE_USER_STD_OUTPUT
// `define USER_CONFIG_GPIO_19_INIT `GPIO_MODE_USER_STD_OUTPUT
// `define USER_CONFIG_GPIO_20_INIT `GPIO_MODE_USER_STD_OUTPUT
// `define USER_CONFIG_GPIO_21_INIT `GPIO_MODE_USER_STD_OUTPUT
// `define USER_CONFIG_GPIO_22_INIT `GPIO_MODE_USER_STD_BIDIRECTIONAL
// `define USER_CONFIG_GPIO_23_INIT `GPIO_MODE_USER_STD_OUTPUT
// `define USER_CONFIG_GPIO_24_INIT `GPIO_MODE_USER_STD_OUTPUT
// `define USER_CONFIG_GPIO_25_INIT `GPIO_MODE_USER_STD_OUTPUT
// `define USER_CONFIG_GPIO_26_INIT `GPIO_MODE_USER_STD_OUTPUT
//
// I assume this is how the other 4 shared digital inputs are configured:
// `define USER_CONFIG_GPIO_31_INIT `GPIO_MODE_USER_STD_INPUT_NOPULL
// `define USER_CONFIG_GPIO_32_INIT `GPIO_MODE_USER_STD_INPUT_NOPULL
// (33 is not an input?)
// `define USER_CONFIG_GPIO_34_INIT `GPIO_MODE_USER_STD_INPUT_NOPULL
// `define USER_CONFIG_GPIO_35_INIT `GPIO_MODE_USER_STD_INPUT_NOPULL


// ---- ACTUAL SNIPPET STARTS BELOW THIS LINE ----


    //// BEGIN: INSTANTIATION OF ANTON'S DESIGN (top_ew_algofoogle) (SNIPPET2_ShareIns) ---------------------

    // This snippet comes from here:
    // https://github.com/algofoogle/raybox-zero/blob/ew/src/rtl/ew_caravel_snippets/SNIPPET2_ShareIns.v

    // Shared INPUT pads: IO[35,34, 32,31]
    wire [3:0] shared_io_in = {io_in[35], io_in[34], /* skip 33 per EW */ io_in[32], io_in[31]};

    // Anton's assigned pads are IO[26:18]...
    // Ellen has also permitted Anton to use IO[11] as another pad, and it will be used as Anton's clock source.
    wire anton_clock_in = io_in[11]; //!!!NOTE!!!: If this becomes unavailable for some reason, put user_clock2 here instead.
    assign io_oeb[11] = a1s[0]; // 1: Input.
    assign io_out[11] = a0s[8]; // Irrelevant.
    // These allow easy renumbering of those pads, if necessary.
    assign anton_io_in = {io_in[26:18]};      // Map the 'in' side of our 10 pads.
    assign io_out[26:18] = anton_io_out;    // Map the 'out' side of our 10 pads.
    assign io_oeb[26:18] = anton_io_oeb;    // Map the IO OEBs for our pads.
    // Convenience mapping of LA[115:64] to anton_la_in[51:0]. All are INPUTS INTO our module:
    wire [51:0] anton_la_in   = la_data_in[115:64];
    wire [51:0] anton_la_oenb =    la_oenb[115:64]; // SoC should configure these all as its outputs (i.e. inputs to our design).

    // Abtractions between Anton's top design and the above pads.
    wire [8:0]  anton_io_in;                // 'In' side of abtracted pads. Only 1 ([4]) is used (bidirectional config).
    wire [8:0]  anton_io_out;               // Design-driven: 'Out' side of abstracted pads. Not all OUTs are used.
    wire [8:0]  anton_io_oeb;               // Design-driven: Direction control for each abstracted pad.
    // Splicing the various signals together into their respective abstracted pads:
    wire        anton_tex_oeb0;             // Design-driven: Controls dir of one specific IO pad (Texture QSPI io[0]).
    wire [5:0]  anton_gpout;                // Design-driven: We splice 4 LSB into anton_io_out, discard upper 2.
    wire [15:0] a0s, a1s;                   // Low and high signals from our design that we can use to mix constants.
    assign      anton_io_oeb = {a0s[3:0], anton_tex_oeb0, a0s[7:4]}; // 0000t0000 where 't' is anton_tex_oeb0.
    assign      anton_io_out[8:5] = anton_gpout[3:0]; // Only use lower 4 (of 6) 'gpout's, plug them into the top of Anton's OUTPUT pads.
    wire [3:0]  anton_tex_in = {shared_io_in[2:0], anton_io_in[4]}; // Top 3 are shared inputs, bottom 1 is Anton's bidir pin.
    wire        anton_o_reset;              // For now this is just used during cocotb tests.


    top_ew_algofoogle top_ew_algofoogle(
    `ifdef USE_POWER_PINS
        .vccd1(vccd1),        // User area 1 1.8V power
        .vssd1(vssd1),        // User area 1 digital ground
    `endif

        .i_clk                  (anton_clock_in),   //!!!NOTE!!!: If this becomes unavailable for some reason, put user_clock2 here instead.
        .i_test_wci             (wb_clk_i),         // Not actually used as a clock source; just used for testing.
        .i_test_uc2             (user_clock2),      // Not actually used as a clock source; just used for testing.
        .i_la_invalid           (anton_la_oenb[0]), // Check any one of our LA's OENBs. Should be 0 (i.e. driven by SoC) if valid.
        .i_reset_lock_a         (anton_la_in[0]),   // Hold design in reset if equal (both 0 or both 1)
        .i_reset_lock_b         (anton_la_in[1]),   // Hold design in reset if equal (both 0 or both 1)
        .o_reset                (anton_o_reset),    // OUTPUT from the design to allow simulation testing to see its actual reset state.

        .zeros                  (a0s),  // A source of 16 constant '0' signals.
        .ones                   (a1s),  // A source of 16 constant '1' signals.

        .o_hsync                (anton_io_out[0]),
        .o_vsync                (anton_io_out[1]),
        //.o_rgb([23:0]) not used, except to feed DAC.

        .o_tex_csb              (anton_io_out[2]),
        .o_tex_sclk             (anton_io_out[3]),

        .o_tex_oeb0             (anton_tex_oeb0), // My only bidirectional pad.
        .o_tex_out0             (anton_io_out[4]),
        .i_tex_in               (anton_tex_in),

        .o_gpout                (anton_gpout), //NOTE: Lower 4 bits are used, upper 2 are not.

        .i_vec_csb              (anton_la_in[2]),
        .i_vec_sclk             (anton_la_in[3]),
        .i_vec_mosi             (anton_la_in[4]),

        .i_gpout0_sel           (anton_la_in[10:5]),

        .i_debug_vec_overlay    (anton_la_in[11]),

        .i_reg_csb              (anton_la_in[12]),
        .i_reg_sclk             (anton_la_in[13]),
        .i_reg_mosi             (anton_la_in[14]),

        .i_gpout1_sel           (anton_la_in[20:15]),
        .i_gpout2_sel           (anton_la_in[26:21]),

        .i_debug_trace_overlay  (anton_la_in[27]),

        .i_gpout3_sel           (anton_la_in[33:28]),

        .i_debug_map_overlay    (anton_la_in[34]),

        .i_gpout4_sel           (anton_la_in[40:35]),
        .i_gpout5_sel           (anton_la_in[46:41]),

        .i_mode                 (anton_la_in[49:47]),

        .i_reg_outs_enb         (anton_la_in[50]),
        .i_spare_0              (anton_la_in[51]),
        .i_spare_1              (shared_io_in[3])
    );

    //// END: INSTANTIATION OF ANTON'S DESIGN (top_ew_algofoogle) (SNIPPET2_ShareIns) ---------------------
