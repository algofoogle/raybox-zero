`timescale 1ns / 1ps

module rbz_tb;
    initial begin
        $dumpfile("rbz_tb.vcd");
        $dumpvars(0, rbz_tb);
    end

    reg clk;
    initial clk = 1;
    always #20 clk <= ~clk;

    reg reset;
    initial reset = 0;

    initial begin
        #120 reset = 1;
        #120 reset = 0;

        #80000 $finish;
    end

    rbzero uut(
        .clk        (clk),
        .reset      (reset),
        .i_ss_n     (1),
        .i_sclk     (1),
        .i_mosi     (1),
        .i_reg_ss_n (1),
        .i_reg_sclk (1),
        .i_reg_mosi (1),
        // .o_tex_csb  (),
        // .o_tex_sclk (),
        // .o_tex_out0 (),
        // .o_tex_oeb0 (),
        .i_tex_in   (0),
        .i_debug_v  (0),
        .i_debug_m  (0),
        .i_debug_t  (0),
        .i_inc_px   (0),
        .i_inc_py   (0),
        .i_gen_tex  (0)
        // .hsync_n    (),
        // .vsync_n    (),
        // .rgb        (),
        // .o_hblank   (),
        // .o_vblank   (),
        // .hpos       (),
        // .vpos       ()
    );

endmodule
