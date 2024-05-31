`default_nettype none
// `timescale 1ns / 1ps

module row_render #(
  parameter H_VIEW = 640
) (
  input wire  [1:0] wall, // Wall texture ID.
  input wire        side, // Light or dark side? side==1 is light.
  input wire [10:0] size, // Supports 0..2047; remember this is mirrored, too.
  input wire  [9:0] hpos, // Current horizontal trace position.
  input wire  [5:0] texu, // Texture 'u' coordinate, 0..63
  input wire  [5:0] texv, // Texture 'v' coordinate, 0..63
  input wire        vinf, // Infinite V mode?
  input wire  [5:0] leak, // How far up the wall does the 'floor leak'? 0 is normal (no leak).
  output wire [5:0] gen_tex_rgb,  // Bitwise-generated texture, if desired. //NOTE: BBGGRR bit order.
  output wire hit         // Are we in this row or not?
);
  localparam HALF_SIZE = H_VIEW/2;
  //SMELL: Instead of combo logic, could use a register and check for enter/leave:
  assign hit =
    (texv >= leak) &                      // 'Leaking' means background is visible instead of texture, up to 'leak' point. Can fake 'wading'.
    (vinf | (
      (hpos < HALF_SIZE || texv != 6'd0 ) & // Fix texture overflow; i.e. texv can't wrap around to 0 beyond the half-size point.
      (
        (size > HALF_SIZE) ||               // If texture is taller than the screen itself, it's always visible.
        // 1'b1 || // Infinite wall height.
        ((HALF_SIZE-size <= {1'b0,hpos}) && ({1'b0,hpos} <= HALF_SIZE+size))
      )
    ));

  // The following is just some bitwise maths to generate textures IF we don't have an external
  // texture memory via SPI, and just want something to show off/test:
  assign gen_tex_rgb =
    // Fancy colourful XOR pattern:
    wall == 1 ? ({texu[0],side,texu[2],side,texu[4],side} ^ {texv[0],1'b0,texv[2],1'b0,texv[4],1'b0}): // Fancy.
    // Blue bricks:
    wall == 2 ? (side ?
                  ( // Light side.
                    ((texu[4:0]==6&&texv[3]==0) || (texu[4:0]==24&&texv[3]==1)) ? 6'b10_10_10 : // Mortar
                    (texv[2:0]==0) ? (texu[0] ? 6'b01_01_01 : 6'b10_10_10) : // Brick shadow.
                    (texv[2:0]==7) ? 6'b11_01_00 : // Top sheen.
                    (texv[2:0]==1) ? 6'b01_00_00 : // Bottom shade.
                    6'b11_00_00
                  ):( // Dark side.
                    ((texu[4:0]==6&&texv[3]==0) || (texu[4:0]==24&&texv[3]==1)) ? 6'b01_01_01 : // Mortar
                    (texv[2:0]==0) ? (texu[0] ? 6'b00_00_00 : 6'b01_01_01) : // Brick shadow.
                    (texv[2:0]==7) ? 6'b11_00_00 : // Top sheen.
                    (texv[2:0]==1) ? 6'b00_00_00 : // Bottom shade.
                    6'b10_00_00
                  )
                ):
    // Purple panels:
    wall == 3 ? (side ?
                  ( // Light side.
                    (texu[3:1]==0 || texv[3:1]==7) ? 6'b11_01_11 : // Bright bevel.
                    (texu[3:1]==7 || texv[3:1]==0) ? 6'b10_00_10 : // Shadow bevel.
                    6'b10_00_11 // Panel middle.
                  ):( // Dark side.
                    (texu[3:1]==0 || texv[3:1]==7) ? 6'b10_00_10 : // Bright bevel.
                    (texu[3:1]==7 || texv[3:1]==0) ? 6'b01_00_01 : // Shadow bevel.
                    6'b01_00_10 // Panel middle.
                  )
                ): // Purple, with borders
    /*wall==0?*/(side ? 6'b00_00_11 : 6'b00_00_10); // Red.

endmodule
