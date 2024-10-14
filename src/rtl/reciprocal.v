// Single-step fixed-point reciprocal approximation for arbitrary SQm.n (SQ12.12 default), modified from:
// https://github.com/algofoogle/raybox/blob/main/src/rtl/reciprocal.v
// ...which is in turn adapted from:
// https://github.com/ameetgohil/reciprocal-sv/blob/master/rtl/reciprocal.sv
// ...which implements: https://observablehq.com/@drom/reciprocal-approximation

`default_nettype none
// `timescale 1ns / 1ps


`define FQMN [M-1:-N]

`ifdef QUARTUS
    `define DEBUG_COEFFS
`elsif __openlane__
    `define DEBUG_COEFFS
`endif


// Sequential reciprocal 'device' that can be loaded, started,
// and will provide a registered result when ready.
module reciprocal_fsm #(
  parameter [4:0] M = 12,         // Integer bits, inc. sign.
  parameter       N = 12          // Fractional bits.
) (
  input   wire        i_clk,
  input   wire        i_reset,
  input   wire        i_start,
  input   wire  `FQMN i_data,
  input   wire        i_abs,  // 1=we want the absolute value only.
  output  reg   `FQMN o_data,
  output  reg         o_sat,  // 1=saturated
  output  reg         o_done
);

  reg `FQMN operand;
  reg abs;
  wire `FQMN result;
  wire sat;
  reg [2:0] state;
  localparam [2:0] IDLE=0, WS1=1, WS2=2, WS3=3, DONE=4;

  reciprocal #(.M(M),.N(N)) rcp (
    .i_data (operand),
    .i_abs  (i_abs),
    .o_data (result),
    .o_sat  (sat)
  );

/* verilator lint_off CASEINCOMPLETE */
  always @(posedge i_clk) begin
    if (i_reset) begin
      operand <= 0;
      abs <= 0;
      o_data <= 0;
      o_sat <= 0;
      o_done <= 0;
      state <= IDLE;
    end else case (state)
      IDLE: if (i_start) begin
        o_done <= 0;
        operand <= i_data;
        abs <= i_abs;
        state <= WS1;
      end
      WS1: state <= WS2;
      WS2: state <= WS3;
      WS3: state <= DONE;
      DONE: begin
        o_data <= result;
        o_sat <= sat;
        o_done <= 1;
        state <= IDLE;
      end
    endcase
  end
/* verilator lint_on CASEINCOMPLETE */

endmodule


module reciprocal #(
  parameter [4:0] M = 12,         // Integer bits, inc. sign.
  parameter       N = 12          // Fractional bits.
)(
  input   wire [M-1:-N]   i_data,
  input   wire            i_abs,  // 1=we want the absolute value only.
  output  wire [M-1:-N]   o_data,
  output  wire            o_sat   // 1=saturated
);
/* verilator lint_off REALCVT */
  // Find raw fixed-point value representing 1.466:
  // localparam integer nb = 1.466*(2.0**N);
  //SMELL: Wackiness to work around Quartus bug: https://community.intel.com/t5/Intel-Quartus-Prime-Software/BUG/td-p/1483047
  localparam SCALER = 1<<N;
  localparam real FSCALER = SCALER;
`ifdef QUARTUS
  `define ROUNDING_FIX -0.5
  localparam [M-1:-N] n1466  = 1.466 *FSCALER+`ROUNDING_FIX;
  localparam [M-1:-N] n10012 = 1.0012*FSCALER+`ROUNDING_FIX;
`else
  localparam [M-1:-N] n1466 = `Qmn'($rtoi(1.466*FSCALER));    // 1.466 in QM.N
  // Find raw fixed-point value representing 1.0012:
  // localparam integer nd = 1.0012*(2.0**N);
  localparam [M-1:-N] n10012 = `Qmn'($rtoi(1.0012*FSCALER));  // 1.0012 in QM.N
`endif
/* verilator lint_on REALCVT */

  localparam [M-1:-N] nSat = ~(1<<(M+N-1));   // Max positive integer (i.e. saturation).

  localparam S = M-1; // Sign bit (top-most bit index too).

`ifdef DEBUG_COEFFS
  initial begin
    //NOTE: In Quartus, at compile-time, this should hopefully spit out the params from above
    // in the compilation log, and in OpenLane it should be in logs/synthesis/1-synthesis.log:
    $display("reciprocal params for SQ%0d.%0d:  n1466=%X, n10012=%X, nSat=%X", M, N, n1466, n10012, nSat);
  end
`endif

  /*
  Reciprocal approximation algorithm for numbers in the range [0.5,1)
  a = input
  b = 1.466 - a
  c = a * b;
  d = 1.0012 - c
  e = d * b;
  output = e * 4;
  */

  wire [4:0]          lzc_cnt, rescale_lzc; //SMELL: These should be sized per M+N; extra bit is for sign?? Is that necessary? See `rescale_data`.
  wire [S:-N]         a, b, d, f, reci, sat_data, scale_data;
  wire [M*2-1:-N*2]   rescale_data; // Double the size of [S:-N], i.e. size of 2 full fixed-point numbers, i.e. their product.
  wire                sign;
  wire [S:-N]         unsigned_data;

  /* verilator lint_off UNUSED */
  wire [M*2-1:-N*2]   c, e;
  /* verilator lint_on UNUSED */

  assign sign = i_data[S];

  assign unsigned_data = sign ? (~i_data + 1'b1) : i_data;

  lzc lzc(.i_data(unsigned_data), .o_lzc(lzc_cnt));

  assign rescale_lzc = $signed(M) - $signed(lzc_cnt); //SMELL: rescale_lzc and lzc_cnt are both 7 bits; could there be a sign problem??

  // Scale input data to be between .5 and 1 for accurate reciprocal result
  assign scale_data =
      M >= lzc_cnt ?  // Is our leading digit within the integer part?
                      unsigned_data >>> (M-lzc_cnt) : // Yes: Scale magnitude down to [0.5,1) range.
                      unsigned_data <<< (lzc_cnt-M);  // No: Scale magnitude up to [0.5,1) range.

  //SMELL: Is there a way to either restrict the multiplier size, or have a 2-step shared multiplier,
  // so as to make this synth to less logic? Could we even just get away with reduced reciprocal precision?

  //NOTE: The following multipliers cannot be treated as constants, which means I think they basically
  // always need to synthesise as FULL multipliers... is there any way around that?

  assign a = scale_data;

  assign b = n1466 - a;

  assign c = $signed(a) * $signed(b);

  assign d = n10012 - $signed(c[S:-N]);

  assign e = $signed(d) * $signed(b);

  assign f = e[S:-N];

  // [M-1:M-2] are the bits that would overflow if multiplied by 4 (i.e. SHL-2):
  assign reci = |f[M-1:M-2] ? nSat : f << 2; //saturation detection and (e*4)
  //SMELL: I think we could keep 2 extra bits of precision if we didn't simply do f<<2,
  // but rather extracted a shifted bit range from `e`.

  // Rescale reciprocal by the lzc factor.
  //NOTE: rescale_lzc[4] is sign bit to determine whether we're scaling up or down to be
  // back in our original range.
  assign rescale_data =
    rescale_lzc[4] ?  { {(M+N){1'b0}}, reci} << (~rescale_lzc + 1'b1) :
                      { {(M+N){1'b0}}, reci} >> rescale_lzc;

  //Saturation logic
  //SMELL: Double-check our bit range here. In the Q16.16 original, the check was against [31:15], which is 17 bits,
  // but I feel like it was meant to be 16 bits (i.e. [31:16]).
  //SMELL: Maybe it was 17 bits because of the sign bit in index 15?
  // i.e. bit 15 must not be set, because if it is, then it would look like a negative result
  // (which might suggested overflow because it actually represents an absolute, and hence positive value)...?
  assign o_sat = |rescale_data[M*2-1:M-N]; // We've overflowed if any upper bits of the full-range product are set, so saturate.
  assign sat_data = o_sat ? nSat : rescale_data[M-N-1:-N*2];

  assign o_data = (sign && !i_abs) ? (~sat_data + 1'b1) : sat_data;

endmodule
