`include "const.v"

module RegisterFile (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire rob_clear,

    input wire [4:0] set_reg_id,
    input wire [31:0] set_val,
    input wire [`ROB_WIDTH_BIT - 1:0] set_reg_on_rob_id,

    input wire [                 4:0] set_dep_reg_id,
    input wire [`ROB_WIDTH_BIT - 1:0] set_dep_rob_id,

    input  wire [                 4:0] get_id1,
    output wire [                31:0] get_val1,
    output wire                        get_has_dep1,
    output wire [`ROB_WIDTH_BIT - 1:0] get_dep1,
    input  wire [                 4:0] get_id2,
    output wire [                31:0] get_val2,
    output wire                        get_has_dep2,
    output wire [`ROB_WIDTH_BIT - 1:0] get_dep2,

    // between ReorderBuffer and Register
    output wire [`ROB_WIDTH_BIT - 1 : 0] get_rob_id1,
    input  wire                          rob_value1_ready,
    input  wire [                  31:0] rob_value1,
    output wire [`ROB_WIDTH_BIT - 1 : 0] get_rob_id2,
    input  wire                          rob_value2_ready,
    input  wire [                  31:0] rob_value2
);
    reg [31:0] regs[0:31];
    reg [`ROB_WIDTH_BIT - 1:0] dep[0:31];
    reg has_dep[0:31];
    wire hd1 = has_dep[get_id1] || set_dep_reg_id && set_dep_reg_id == get_id1;
    wire hd2 = has_dep[get_id2] || set_dep_reg_id && set_dep_reg_id == get_id2;
    assign get_val1 = hd1 ? rob_value1 : regs[get_id1];
    assign get_val2 = hd2 ? rob_value2 : regs[get_id2];
    assign get_has_dep1 = hd1 && !rob_value1_ready;
    assign get_has_dep2 = hd2 && !rob_value2_ready;
    assign get_dep1 = set_dep_reg_id == get_id1 ? set_dep_rob_id : dep[get_id1];
    assign get_dep2 = set_dep_reg_id == get_id2 ? set_dep_rob_id : dep[get_id2];
    assign get_rob_id1 = get_dep1;
    assign get_rob_id2 = get_dep2;

    always @(posedge clk_in) begin : MainBlock
        integer i;
        if (rst_in) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 0;
                dep[i] <= 0;
                has_dep[i] <= 0;
            end
        end
        else if (!rdy_in) begin
            // do nothing
        end
        else if (rob_clear) begin
            for (i = 0; i < 32; i = i + 1) begin
                dep[i] <= 0;
                has_dep[i] <= 0;
            end
        end
        else begin
            if (set_reg_id) begin
                regs[set_reg_id] <= set_val;
                if (set_dep_reg_id != set_reg_id && set_reg_on_rob_id == dep[set_reg_id]) begin
                    has_dep[set_reg_id] <= 0;
                    dep[set_reg_id] <= 0;
                end
            end
            if (set_dep_reg_id) begin
                dep[set_dep_reg_id] <= set_dep_rob_id;
                has_dep[set_dep_reg_id] <= 1;
            end
        end
    end

endmodule