`default_nettype none

module door_check #(
    parameter MAP_WALLBITS = 3,
    parameter MAP_WBITS = 4,
    parameter MAP_HBITS = 4
) (
    // Yosys doesn't support arrayed ports?
    // input wire [23:0]               i_doors [0:3],
    input wire [23:0]               i_doors0,
    input wire [23:0]               i_doors1,
    input wire [23:0]               i_doors2,
    input wire [23:0]               i_doors3,
    input wire [MAP_WBITS-1:0]      i_mapx,
    input wire [MAP_HBITS-1:0]      i_mapy,
    output reg                      o_hit,
    output reg [MAP_WALLBITS-1:0]   o_wall, // Wall ID (texture) of the door.
    output reg [7:0]                o_pos   // Position (i.e. how open; 0=closed).
);
    wire [MAP_WBITS-1:0]    dx [0:3]; // Door X
    wire [MAP_HBITS-1:0]    dy [0:3]; // Door Y
    wire [2:0]              dw [0:3]; // Door wall
    wire [7:0]              dp [0:3]; // Door pos

    // Unpack the regs:
    //NOTE: Bits 8, 17, 23 are currently reserved.
    assign {dx[0], dy[0], dw[0], dp[0]} = { i_doors0[22:18], i_doors0[16:12], i_doors0[11:9], i_doors0[7:0] };
    assign {dx[1], dy[1], dw[1], dp[1]} = { i_doors1[22:18], i_doors1[16:12], i_doors1[11:9], i_doors1[7:0] };
    assign {dx[2], dy[2], dw[2], dp[2]} = { i_doors2[22:18], i_doors2[16:12], i_doors2[11:9], i_doors2[7:0] };
    assign {dx[3], dy[3], dw[3], dp[3]} = { i_doors3[22:18], i_doors3[16:12], i_doors3[11:9], i_doors3[7:0] };

    wire [MAP_WBITS-1:0] x = i_mapx;
    wire [MAP_HBITS-1:0] y = i_mapy;

    always @(*) begin
        o_hit = 1'b1; // Assume hit by default, but final 'else' will override this.
        /**/ if ( (dx[0]!=0 || dy[0]!=0) && dx[0]==x && dy[0]==y ) {o_wall, o_pos} = {dw[0], dp[0]};
        else if ( (dx[1]!=0 || dy[1]!=0) && dx[1]==x && dy[1]==y ) {o_wall, o_pos} = {dw[1], dp[1]};
        else if ( (dx[2]!=0 || dy[2]!=0) && dx[2]==x && dy[2]==y ) {o_wall, o_pos} = {dw[2], dp[2]};
        else if ( (dx[3]!=0 || dy[3]!=0) && dx[3]==x && dy[3]==y ) {o_wall, o_pos} = {dw[3], dp[3]};
        else begin
            o_hit = 0;
            {o_wall, o_pos} = 0;
        end
    end
endmodule
