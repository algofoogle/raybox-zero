`timescale 1ns / 1ps

module rcp_tb;
    initial begin
        $dumpfile("rcp_tb.vcd");
        $dumpvars(0, rcp_tb);
    end

    reg clk;
    initial clk = 1;
    always #20 clk <= ~clk;

    reg reset;
    initial reset = 0;

    reg `F  rcp_in;
    reg     rcp_start;
    wire `F rcp_out;
    wire    rcp_sat;
    wire    rcp_done;

    initial begin
        rcp_in = 0;
        rcp_start = 0;
    end

    initial begin
        #120 reset = 1;
        #120 reset = 0;
        #120 rcp_in = `Qmnc'h002_000;
        #0 rcp_start = 1;
        #40 rcp_start = 0;
        #5000 $finish;
    end

    reciprocal_fsm #(.M(`Qm),.N(`Qn)) rcp (
        .i_clk      (clk),
        .i_reset    (reset),
        .i_start    (rcp_start),
        .i_data     (rcp_in),
        .i_abs      (1'b1),
        .o_data     (rcp_out),
        .o_sat      (rcp_sat),
        .o_done     (rcp_done)
    );


endmodule
