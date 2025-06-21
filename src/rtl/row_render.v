`default_nettype none
// `timescale 1ns / 1ps

module rgb222_darken(
  input ena,
  input [5:0] rgb_in,
  output [5:0] rgb_out
);
  wire [5:0] i = rgb_in;
  assign rgb_out =
    ena ? {
            i[5:4]==0 ? 2'b0 : i[5:4]-2'b1,
            i[3:2]==0 ? 2'b0 : i[3:2]-2'b1,
            i[1:0]==0 ? 2'b0 : i[1:0]-2'b1
          } :
          rgb_in; // Darkening disabled.
endmodule

module row_render #(
  parameter MAP_WALLBITS = 3,
  parameter H_VIEW = 640
) (
  input wire        specialwall, // If set, 'wall' is a special wall ID reserved for things like door frames.
  input wire  [MAP_WALLBITS-1:0] wall, // Wall texture ID.
  input wire        side, // Light or dark side? side==1 is light.
  input wire [10:0] size, // Supports 0..2047; remember this is mirrored, too.
  input wire  [9:0] hpos, // Current horizontal trace position.
  input wire  [5:0] texu, // Texture 'u' coordinate, 0..63
  input wire  [5:0] texv, // Texture 'v' coordinate, 0..63
  input wire  [5:0] texvorg,
  input wire        vinf, // Infinite V mode?
  input wire  [5:0] leak, // How far up the wall does the 'floor leak'? 0 is normal (no leak).
  input wire        leakfix, // Is the 'leak' fixed to the floor, or can it move with Vshift (which is new behaviour)?
  output wire [5:0] gen_tex_rgb,  // Bitwise-generated texture, if desired. //NOTE: BBGGRR bit order.
  output wire hit         // Are we in this row or not?
);
  localparam HALF_SIZE = H_VIEW/2;
  //SMELL: Instead of combo logic, could use a register and check for enter/leave:

  wire [MAP_WALLBITS:0] ewall = {specialwall, wall}; // NOTE: Extra bit at the top for 'specialwall'.

  wire [5:0] checks = texu^texv;

  wire panel_binary = ((texu ^ (texv >> 2)) & 15) < 7;

  wire [5:0] x = texu;
  wire [5:0] y = texv;

  wire [5:0] pastel = checks[2] ? 6'b10_00_11 : 6'b11_00_10;
  wire [5:0] wall4;
  rgb222_darken wall4_tint(.ena(~side), .rgb_in(pastel), .rgb_out(wall4));

  wire [5:0] rainbow = (texu+texv);
  wire [5:0] wall6;
  rgb222_darken wall6_tint(.ena(~side), .rgb_in(rainbow), .rgb_out(wall6));

  wire [5:0] manhat = (((x - y) ^ (x + y)));
  wire [5:0] wall7;
  rgb222_darken wall7_tint(.ena(~side), .rgb_in(manhat), .rgb_out(wall7));

  wire [5:0] doorframe;
  door_frame door_frame_tex(.x(texu), .y(texv), .rgb(doorframe));
  wire [5:0] wall_doorframe;
  rgb222_darken wall_doorframe_tint(.ena(~side), .rgb_in(doorframe), .rgb_out(wall_doorframe));

  wire [5:0] texvcomp = leakfix ? texvorg : texv;
  wire seam = (hpos < HALF_SIZE && texvorg == -6'd1) || (hpos >= HALF_SIZE && texvorg == 6'd0);

  assign hit =
    (texvcomp >= leak) &                      // 'Leaking' means background is visible instead of texture, up to 'leak' point. Can fake 'wading'.
    (vinf | (
      (!seam) & // Don't render the very edges where there is an erroneous seam (i.e. fix texture under/overflow).
      (
        (size > HALF_SIZE) ||               // If texture is taller than the screen itself, it's always visible.
        ((HALF_SIZE-size <= {1'b0,hpos}) && ({1'b0,hpos} <= HALF_SIZE+size))
      )
    ));

  // The following is just some bitwise maths to generate textures IF we don't have an external
  // texture memory via SPI, and just want something to show off/test:
  assign gen_tex_rgb =
    // Fancy colourful XOR pattern:
    ewall== 1 ? ({texu[0],side,texu[2],side,texu[4],side} ^ {texv[0],1'b0,texv[2],1'b0,texv[4],1'b0}): // Fancy.
    // Blue bricks:
    ewall== 2 ? (side ?
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
    ewall== 3 ? (side ?
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
    ewall== 4 ? wall4: // Fuchsia.
    ewall== 5 ? (side ? (panel_binary ? 6'b00_10_11 : 6'b00_01_10) : (panel_binary ? 6'b00_01_10 : 6'b00_00_01)) : // Orange.
    ewall== 6 ? wall6: // Rainbow stripes (Brown on map).
    ewall== 7 ? wall7: // Argyle (yellow-green on map).
    // ----- Extended (special) walls -----
    ewall== 8 ? wall_doorframe:
    /*wall==0?*/(side ? 6'b00_00_11 : 6'b00_00_10); // Red.

endmodule


module door_frame
(
    input  wire [5:0] x,
    input  wire [5:0] y,
    output wire [5:0] rgb
);
    // Centre black stripe:
    wire stripe = x >= 30 && x <= 33;
    wire bottom = y == 0;
    wire top = y == 63;
    wire rail = (x >= 28 && x <= 35) || x <= 1 || x >= 62;
    wire sheen = (x==0) | (x==27) | (x==61);
    wire shade = (x==2) | (x==36) | (x==63);

    // Checker for metal panel shading – just XOR a low-order bit of X & Y
    wire shade_sel = x[0] ^ y[0];   // toggles every 4 px horizontally/vertically

    // -------- Final pixel ----------------------------------------------------
    assign rgb =
      stripe    ? 6'b00_00_00 :
      top       ? 6'b11_11_10 :
      bottom    ? 6'b10_00_00 :
      sheen     ? 6'b10_11_11 :
      shade     ? 6'b10_01_00 :
      rail      ? 6'b10_10_10 :
      shade_sel ? 6'b11_10_00 :
                  6'b10_01_00;
endmodule
