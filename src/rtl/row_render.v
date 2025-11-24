`default_nettype none
// `timescale 1ns / 1ps

`ifndef READMEM_PATH
`define READMEM_PATH ""
`endif // !READMEM_PATH

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
  input wire  `WALL wall, // Wall texture ID.
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

  reg [5:0] door_light [0:4095];
  reg [5:0] door_shade [0:4095];
  reg [5:0] frame_light [0:4095];
  reg [5:0] frame_shade [0:4095];

  initial begin
    `ifdef COCOTB_RTL_SIM // Can be defined in a tapeout project's test/Makefile.
      //SMELL: This pathing is a bit of a hack for tests before a tapeout.
      $readmemb("../src/raybox-zero/src/rtl/door_light.mem", door_light);
      $readmemb("../src/raybox-zero/src/rtl/door_shade.mem", door_shade);
      $readmemb("../src/raybox-zero/src/rtl/frame_light.mem", frame_light);
      $readmemb("../src/raybox-zero/src/rtl//frame_light.mem", frame_shade);
    `else // !COCOTB_RTL_SIM
      $readmemb({`READMEM_PATH, "door_light.mem"}, door_light);
      $readmemb({`READMEM_PATH, "door_shade.mem"}, door_shade);
      $readmemb({`READMEM_PATH, "frame_light.mem"}, frame_light);
      $readmemb({`READMEM_PATH, "frame_shade.mem"}, frame_shade);
    `endif // COCOTB_RTL_SIM
  end

  wire [7:0] ewall =
    (wall[7:5] == 3'b010 && wall[0])  ? 8 :                     // Door frame.
    (wall[7:4] == 4'b0100) /*0x4x*/   ? {5'b01000,wall[3:1]} :  // Door, with its own unique texture.
    (wall[7:4] == 4'b0101) /*0x5x*/   ? {5'b00000,wall[3:1]} :  // Door, but using a direct wall texture.
                                        {5'b00000,wall[2:0]};   // Regular wall.

  wire [5:0] checks = texu^texv;

  wire panel_binary = ((texu ^ (texv >> 2)) & 15) < 7;

  wire [5:0] x = texu;
  wire [5:0] y = texv;

  wire [5:0] pastel = checks[2] ? 6'b10_00_11 : 6'b11_00_10;
  wire [5:0] wall4;
  rgb222_darken wall4_tint(.ena(~side), .rgb_in(pastel), .rgb_out(wall4));

  wire `RGB wall6;
  wire [5:0] rainbow = (texu+texv);
  rgb222_darken wall6_tint(.ena(~side), .rgb_in(rainbow), .rgb_out(wall6));

  wire [5:0] nicexor = {checks[1:0],checks[5:2]};
  wire [5:0] wall7;
  rgb222_darken wall7_tint(.ena(~side), .rgb_in(nicexor), .rgb_out(wall7));

  wire [5:0] wall_doorframe = side ? frame_light[{texu,texv}] : frame_shade[{texu,texv}];

  wire [5:0] texvcomp = leakfix ? texvorg : texv;
  wire seam = (hpos < HALF_SIZE && texvorg == -6'd1) || (hpos >= HALF_SIZE && texvorg == 6'd0);

  wire `RGB door0 = 6'b00_00_11;
  wire `RGB door1 = side ? door_light[{texu,texv}] : door_shade[{texu,texv}]; //6'b00_11_11 & {3{{1'b1,side}}};
  wire `RGB door2 = side ? door_light[{texu,texv}] : door_shade[{texu,texv}]; //6'b00_11_00 & {3{{1'b1,side}}};
  wire `RGB door3 = side ? door_light[{texu,texv}] : door_shade[{texu,texv}]; //6'b11_11_00 & {3{{1'b1,side}}};
  wire `RGB door4 = side ? door_light[{texu,texv}] : door_shade[{texu,texv}]; //6'b11_00_00 & {3{{1'b1,side}}};
  wire `RGB door5 = side ? door_light[{texu,texv}] : door_shade[{texu,texv}]; //6'b11_00_11 & {3{{1'b1,side}}};
  wire `RGB door6 = side ? door_light[{texu,texv}] : door_shade[{texu,texv}]; //6'b11_11_11 & {3{{1'b1,side}}};
  wire `RGB door7 = side ? door_light[{texu,texv}] : door_shade[{texu,texv}]; //6'b00_00_11 & {3{{1'b1,side}}};

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
    ewall== 0 ? (side ? 6'b00_00_11 : 6'b00_00_10): // Red.
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
    // ----- Generated door textures -----
    ewall==8'h40  ? door0: //NOTE: Can't currently be selected by door reg, since '0' means "use map cell's wall ID"
    ewall==8'h41  ? door1:
    ewall==8'h42  ? door2:
    ewall==8'h43  ? door3:
    ewall==8'h44  ? door4:
    ewall==8'h45  ? door5:
    ewall==8'h46  ? door6:
    /*8'h47*/       door7;

endmodule


