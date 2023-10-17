`default_nettype none
`timescale 1ns / 1ps

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
  // output wire [5:0] rgb,  //NOTE: BBGGRR bit order.
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

  //SMELL: For now, just arbitrarily assign a colour based on side. Later, do textures.

  // // At this point, we have the following parameters to determine the pixel colour
  // // (and hence RGB222 output value):
  // // -  9 bits selecting the slice we want:
  // //    -   wall (2b): 4 possible wall materials (inc. 'other' cell)
  // //    -   side (1b): 2 possible 'side' variants of each wall material
  // //    -   texu (6b): 64 'slices' of each wall.
  // //    =>  Together these form the wall slice (texture) address.
  // //        NOTE: Could also use a counter as extra address bits, allowing for animation.
  // // -  texv (6b): The texel (0..63) we want to look up.
  // // We also have hpos to help us know what possible 'state' we're in for SPI access.

  // // A sloppy way to store 64 pixels, each with 3 channels (R, G, B), each with 2bpc:
  // reg [63:0] r0, r1, g0, g1, b0, b1;
  // // ...384 bits in total.

  // //NOTE: The following 'initial' block will simulate, and will synth for my DE0-Nano
  // // (Altera Cyclone IV FPGA), but probably won't for an ASIC:
  // initial begin
  //   integer i;
  //   for (i=0; i<64; i=i+1) begin
  //     r1[i] = i[5];
  //     r0[i] = i[4];
  //     g1[i] = i[3];
  //     g0[i] = i[2];
  //     b1[i] = i[1];
  //     b0[i] = i[0];
  //   end
  // end

  // // An equally sloppy way to look up the RGB value for an individual pixel?
  // assign rgb = {
  //   b1[texu],
  //   b0[texu],
  //   g1[texu],
  //   g0[texu],
  //   r1[texu],
  //   r0[texu]
  // };

  // assign rgb =
  //   // Fancy colourful XOR pattern:
  //   wall == 1 ? ({texu[0],side,texu[2],side,texu[4],side} ^ {texv[0],1'b0,texv[2],1'b0,texv[4],1'b0}): // Fancy.
  //   // Blue bricks:
  //   wall == 2 ? (side ?
  //                 ( // Light side.
  //                   ((texu[4:0]==6&&texv[3]==0) || (texu[4:0]==24&&texv[3]==1)) ? 6'b10_10_10 : // Mortar
  //                   (texv[2:0]==0) ? (texu[0] ? 6'b01_01_01 : 6'b10_10_10) : // Brick shadow.
  //                   (texv[2:0]==7) ? 6'b11_01_00 : // Top sheen.
  //                   (texv[2:0]==1) ? 6'b01_00_00 : // Bottom shade.
  //                   6'b11_00_00
  //                 ):( // Dark side.
  //                   ((texu[4:0]==6&&texv[3]==0) || (texu[4:0]==24&&texv[3]==1)) ? 6'b01_01_01 : // Mortar
  //                   (texv[2:0]==0) ? (texu[0] ? 6'b00_00_00 : 6'b01_01_01) : // Brick shadow.
  //                   (texv[2:0]==7) ? 6'b11_00_00 : // Top sheen.
  //                   (texv[2:0]==1) ? 6'b00_00_00 : // Bottom shade.
  //                   6'b10_00_00
  //                 )
  //               ):
  //   // Purple panels:
  //   wall == 3 ? (side ?
  //                 ( // Light side.
  //                   (texu[3:1]==0 || texv[3:1]==7) ? 6'b11_01_11 : // Bright bevel.
  //                   (texu[3:1]==7 || texv[3:1]==0) ? 6'b10_00_10 : // Shadow bevel.
  //                   6'b10_00_11 // Panel middle.
  //                 ):( // Dark side.
  //                   (texu[3:1]==0 || texv[3:1]==7) ? 6'b10_00_10 : // Bright bevel.
  //                   (texu[3:1]==7 || texv[3:1]==0) ? 6'b01_00_01 : // Shadow bevel.
  //                   6'b01_00_10 // Panel middle.
  //                 )
  //               ): // Purple, with borders
  //   /*wall==0?*/(side ? 6'b00_00_11 : 6'b00_00_10); // Red.

endmodule
