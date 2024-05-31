`default_nettype none
// `timescale 1ns / 1ps

// `include "fixed_point_params.v"
// `include "helpers.v"


module pov(
  input clk,
  input reset,
  input i_sclk, i_ss_n, i_mosi, // SPI input.
  input i_inc_px, i_inc_py,     // Demo overrides for incrementing playerX/Y. If either is asserted, SPI loads are masked out and 'ready' is cleared.
  input load_if_ready,          // Will go high at the moment that buffered data can go live.
  output `F playerX, playerY, facingX, facingY, vplaneX, vplaneY
);

// ===== GOOD STARTING PARAMETERS FOR RESET =====

`ifdef QUARTUS
  localparam SCALER = 1<<9; // The vectors below use 9 fractional bits.
  localparam real FSCALER = SCALER;
  // An interesting starting position for demo purposes:
  localparam `UQ6_9 playerInitX  = 11.500000 * FSCALER;
  localparam `UQ6_9 playerInitY  = 10.500000 * FSCALER;
  localparam `SQ2_9 facingInitX  =  0.720137 * FSCALER;
  localparam `SQ2_9 facingInitY  = -0.693832 * FSCALER;
  localparam `SQ2_9 vplaneInitX  =  0.346916 * FSCALER;
  localparam `SQ2_9 vplaneInitY  =  0.360069 * FSCALER;
`else
  // An interesting starting position for demo purposes:
  //NOTE: The right-shift below is because realF() assumes `Qn (say, 10 or 12) fractional bits, but we're only using 9:
  localparam SHIFT_Qn9 = `Qn-9;
  localparam `UQ6_9 playerInitX  = 15'($rtoi(`realF(11.500000))>>SHIFT_Qn9);
  localparam `UQ6_9 playerInitY  = 15'($rtoi(`realF(10.500000))>>SHIFT_Qn9);
  localparam `SQ2_9 facingInitX  = 11'($rtoi(`realF( 0.720137))>>SHIFT_Qn9);
  localparam `SQ2_9 facingInitY  = 11'($rtoi(`realF(-0.693832))>>SHIFT_Qn9);
  localparam `SQ2_9 vplaneInitX  = 11'($rtoi(`realF( 0.346916))>>SHIFT_Qn9);
  localparam `SQ2_9 vplaneInitY  = 11'($rtoi(`realF( 0.360069))>>SHIFT_Qn9);
`endif


// ===== TRUNCATED-TO-FULL-RANGE VECTOR EXTENSION =====

  // Registered versions of the truncated vectors, before they get padded up to `F (SQ10.10) format on output ports.
  reg `UQ6_9 playerRX, playerRY;
  reg `SQ2_9 facingRX, facingRY, vplaneRX, vplaneRY;

  // The below extends our more-truncated vectors (at various Qm.n precisions) to conventional `F ports...

  // playerX/Y are received initially as truncated to UQ6.9...
  // This is enough for the player moving within a 64x64 map to a granularity of 1/512 units.
  // This granularity is ~0.002 of a block. Given a block 'feels' like about 1.8m wide this granularity is about ~3.5mm.
  //NOTE: Sign bit not needed (hence 0) because player position should never be negative anyway? i.e. it's in the range [0,64)
  localparam PadUQ6_9Hi = `Qm-6;
  localparam PadUQ6_9Lo = `Qn-9;
  assign playerX = { {PadUQ6_9Hi{1'b0}}, playerRX, {PadUQ6_9Lo{1'b0}} };
  assign playerY = { {PadUQ6_9Hi{1'b0}}, playerRY, {PadUQ6_9Lo{1'b0}} };

  // facing/vplaneX/Y are received as truncated to SQ2.9 before being sign-extended to conventional `F ports...
  // These have much smaller magnitude because normally each vector won't exceed 1.0...
  // we allow a range of [-2.0,+2.0) because that's more than enough for some effects, FOV control (?) etc.
  localparam PadSQ2_9Hi = `Qm-1; // Because of sign bit repetition, this is NOT '-2'
  localparam PadSQ2_9Lo = `Qn-9;
  assign facingX = { {PadSQ2_9Hi{facingRX[1]}}, facingRX[0:-9], {PadSQ2_9Lo{1'b0}} };
  assign facingY = { {PadSQ2_9Hi{facingRY[1]}}, facingRY[0:-9], {PadSQ2_9Lo{1'b0}} };
  assign vplaneX = { {PadSQ2_9Hi{vplaneRX[1]}}, vplaneRX[0:-9], {PadSQ2_9Lo{1'b0}} };
  assign vplaneY = { {PadSQ2_9Hi{vplaneRY[1]}}, vplaneRY[0:-9], {PadSQ2_9Lo{1'b0}} };


// ===== SPI INPUT SYNCHRONISATION =====

  // The following synchronises the 3 SPI inputs using the typical DFF pair approach
  // for metastability avoidance at the 2nd stage, but note that for SCLK this
  // rolls into a 3rd stage so that stages 2 and 3 can detect a rising edge...

  // Sync SCLK using 3-bit shift reg (to catch rising/falling edges):
  reg [2:0] sclk_buffer;
  always @(posedge clk) sclk_buffer <= (reset ? 3'd0 : {sclk_buffer[1:0], i_sclk});
  wire sclk_rise = (sclk_buffer[2:1]==2'b01);

  // Sync /SS; only needs 2 bits because we don't care about edges:
  reg [1:0] ss_buffer;
  always @(posedge clk) ss_buffer <= (reset ? 2'd0 : {ss_buffer[0], i_ss_n});
  wire ss_active = ~ss_buffer[1];

  // Sync MOSI:
  reg [1:0] mosi_buffer;
  always @(posedge clk) mosi_buffer <= (reset ? 2'd0 : {mosi_buffer[0], i_mosi});
  wire mosi = mosi_buffer[1];
  //SMELL: Do we actually need to sync MOSI? It should be stable when we check it at the SCLK rising edge.


// ===== MAIN SPI CONTROL/PAYLOAD REGISTERS =====

  // Expect each complete SPI frame to be 74 bits, made up of (in order, MSB first):
  // playerX, playerY, // 15b x 2 = 30b
  // facingX, facingY, // 11b x 2 = 22b
  // vplaneX, vplaneY. // 11b x 2 = 22b
  localparam totalBits = (15*2)+(11*2)+(11*2); // 74.
  localparam finalBit = totalBits-1;
  reg [6:0]         spi_counter;  // Counts SPI bits. Should be sized to totalBits. Here, it's enough to do 74 counts (0..73)
  reg [finalBit:0]  spi_buffer;   // Receives the SPI bit stream; temporary buffer.
  reg               spi_done;     // Flags when temporary buffer is full (i.e. valid, and ready to be double-buffered into ready_buffer).
  reg               ready;        // Is ready_buffer valid, and ready for push into our live vectors?
  reg [finalBit:0]  ready_buffer; // Last buffered (complete) SPI bit stream that is ready for next loading as vector data.


// ===== MAIN SPI CLOCKED LOGIC =====

  wire spi_frame_end      = (spi_counter == finalBit);  // Have we reached the SPI frame end?
  wire manual_inc_needed  = i_inc_px | i_inc_py;        // Manual playerX/Y increment in effect (i.e. demo mode)?

  always @(posedge clk) begin

    //SMELL: Just roll up all reset states into a single condition; it is in effect for (and overrides) ALL flags/regs anyway.

    // --- spi_counter: ---
    // Keep track of which SPI bit we're clocking in.
    if (reset)
      spi_counter <= 0;
      // Full system reset.

    else if (!ss_active)
      spi_counter <= 0;
      // /CS not asserted; terminate SPI transaction.

    else if (sclk_rise)
      spi_counter <= (spi_frame_end ? 7'd0 : (spi_counter + 1'd1));
      // /CS *is* asserted and we're not in reset: Increment, or wrap around, as bits are clocked in.


    // --- spi_buffer: ---
    // Load new bits into the temporary SPI input buffer.
    if (reset)
      spi_buffer <= 0;
      // Full system reset.

    else if (ss_active && sclk_rise)
      spi_buffer <= {spi_buffer[finalBit-1:0], mosi};
      // Not in reset, and /CS is asserted while SCLK is rising: Shift in next SPI bit.


    // --- ready flag: ---
    // Signal when a complete SPI payload is waiting in the ready_buffer
    // (while another might be starting in the temporary spi_buffer)
    // and must next be used to update the POV registers.
    if (reset)
      ready <= 0;
      // Full system reset.

    else if (load_if_ready && manual_inc_needed)
      ready <= 0;
      // Cancel any existing SPI load if a manual playerX/Y increment is taking effect.

    // else if (load_if_ready && ready)
    //   ready <= 0;                    //DELETED: Don't actually need to reset it; it can keep being used.
    //   // Ready data has been used.

    else if (spi_done)
      ready <= 1'b1;
      // Signal that now ready_buffer holds a complete/valid payload.


    // --- ready_buffer: ---
    // Double-buffer the SPI payload when it completes an SPI frame.
    if (reset)
      ready_buffer <= 0;
      // Full system reset.

    else if (spi_done)
      ready_buffer <= spi_buffer;
      // SPI frame just completed, so push temporary spi_buffer into ready_buffer.


    // --- spi_done: ---
    // Signal when the temporary spi_buffer holds one complete SPI frame
    // (and can be shifted into the ready_buffer).
    if (reset)
      spi_done <= 0;
      // Full system reset.

    else if (spi_done)
      spi_done <= 0;
      // Last bit already clocked in; last frame was just used or discarded.

    else if (ss_active && sclk_rise && spi_frame_end)
      spi_done <= 1'b1;
      // Last bit is being clocked in now.


    // --- Register loading: ---
    if (reset) begin

      // Full system reset...
      {playerRX, playerRY} <= {playerInitX, playerInitY}; // 15b x 2 = 30b
      {facingRX, facingRY} <= {facingInitX, facingInitY}; // 11b x 2 = 22b
      {vplaneRX, vplaneRY} <= {vplaneInitX, vplaneInitY}; // 11b x 2 = 22b

    end else if (load_if_ready && manual_inc_needed) begin

      // Override increment in effect:
      if (i_inc_px) playerRX <= playerRX - 15'b1;
      if (i_inc_py) playerRY <= playerRY - 15'b1;

    end else if (load_if_ready && ready) begin

      // Load buffered vector payload into live vector registers:
      { playerRX,playerRY, facingRX,facingRY, vplaneRX,vplaneRY } <= ready_buffer;

    end
    
  end


endmodule
