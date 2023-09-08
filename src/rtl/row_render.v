`default_nettype none
`timescale 1ns / 1ps

module row_render #(
  localparam H_VIEW = 640
) (
  input wire side,
  input wire [10:0] size, // Supports 0..2047; remember this is mirrored, too.
  input wire  [9:0] hpos, // Current horizontal trace position.
  input wire  [5:0] texu, // Texture 'u' coordinate, 0..63
  input wire  [5:0] texv, // Texture 'v' coordinate, 0..63
  output wire [5:0] rgb,  //NOTE: BBGGRR bit order.
  output wire hit         // Are we in this row or not?    
);
  localparam HALF_SIZE = H_VIEW/2;
  //SMELL: Instead of combo logic, could use a register and check for enter/leave:

  reg [5:0] wall_texture [0:4095];

  initial $readmemb("src/rtl/blue-wall-bgr222.hex", wall_texture, 0, 1000);

  assign hit =
  (
    // Wall always hit if size exceeds screen:
    (size > HALF_SIZE) ||
    // Otherwise, wall is hit if we're within the range of the wall size, mirrored either side of screen middle:
    ((HALF_SIZE-size <= {1'b0,hpos}) && ({1'b0,hpos} <= HALF_SIZE+size))
  );
  
  // // Texture with light/dark sides:
  // wire [5:0] texel = wall_texture[{side,texu,~texv}];

  // Single texture, darkened for shaded side:
  wire [5:0] texel = wall_texture[{texu,~texv}];
  assign rgb = side ? texel : ((texel & 6'b10_10_10)>>1);
  
  //SMELL: For now, just calculate wall texture colour from texture coords, taking light/dark sides into account:
  //{texu[0],side,texu[2],side,texu[4],side} ^ {texv[0],1'b0,texv[2],1'b0,texv[4],1'b0};
  
endmodule
