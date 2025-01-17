`include "const.v"
module InstuctionCache #(
    parameter Bit = `ICACHE_SIZE_BIT
) (
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    input  wire [31:0] addr,  // the last 2 bit should be 0
    output wire        hit,
    output wire [31:0] res,
    input  wire        we,    // write enable
    input  wire [31:0] data
);

    localparam SIZE = 1 << Bit;
    localparam TagBit = 32 - 2 - Bit;

    wire [TagBit - 1:0] tag = addr[31:2+Bit];
    wire [ Bit - 1 : 0] index = addr[2+Bit-1:2];

    reg                 exist                   [0 : SIZE-1];
    reg  [        31:0] buff                    [0 : SIZE-1];
    reg  [TagBit - 1:0] tags                    [0 : SIZE-1];

    assign hit = exist[index] && tags[index] == tag;
    assign res = buff[index];

    always @(posedge clk_in) begin
        if (rst_in) begin : RESET
            integer i;
            for (i = 0; i < SIZE; i = i + 1) begin
                buff[i]  <= 0;
                tags[i]  <= 0;
                exist[i] <= 0;
            end
        end
        else if (rdy_in&&we) begin
            exist[index] <= 1;
            buff[index]  <= data;
            tags[index]  <= tag;
        end
    end

endmodule