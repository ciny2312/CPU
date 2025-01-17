`include "const.v"
module scalar_alu (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire                           valid,
    input wire [   `RS_TYPE_BIT - 1 : 0] work_type,
    input wire [                 31 : 0] r1,
    input wire [                 31 : 0] r2,
    input wire [`ROB_WIDTH_BIT  - 1 : 0] inst_rob_id,

    output reg                           ready,
    output reg [`ROB_WIDTH_BIT  - 1 : 0] rob_id,
    output reg [                 31 : 0] value
);

    localparam AddSub = 3'b000;
    localparam Sll = 3'b001;
    localparam Slt = 3'b010;
    localparam Sltu = 3'b011;
    localparam Xor = 3'b100;
    localparam SrlSra = 3'b101;
    localparam Or = 3'b110;
    localparam And = 3'b111;

    always @(posedge clk_in) begin
        if (rst_in) begin
            ready  <= 0;
            rob_id <= 0;
            value  <= 0;
        end
        else if (!rdy_in) begin
            // do nothing
        end
        else if (!valid) begin
            ready <= 0;
        end
        else begin
            ready  <= 1'b1;
            rob_id <= inst_rob_id;

            if (work_type[4]) begin
                case (work_type[2:0])
                    3'b000: value <= r1 == r2;
                    3'b001: value <= r1 != r2;
                    3'b100: value <= $signed(r1) < $signed(r2);
                    3'b101: value <= $signed(r1) >= $signed(r2);
                    3'b110: value <= $unsigned(r1) < $unsigned(r2);
                    3'b111: value <= $unsigned(r1) >= $unsigned(r2);
                endcase
            end
            else begin
                case (work_type[2:0])
                    AddSub: value <= work_type[3] ? r1 - r2 : r1 + r2;
                    Sll: value <= r1 << r2[4:0];
                    Slt: value <= $signed(r1) < $signed(r2);
                    Sltu: value <= $unsigned(r1) < $unsigned(r2);
                    Xor: value <= r1 ^ r2;
                    SrlSra: value <= work_type[3] ? $signed(r1) >>> r2[4:0] : r1 >> r2[4:0];
                    Or: value <= r1 | r2;
                    And: value <= r1 & r2;
                endcase
            end
        end
    end

endmodule