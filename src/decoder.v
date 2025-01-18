`include "const.v"

module Decoder (
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    input wire        valid,
    input wire [31:0] inst_addr,
    input wire [31:0] inst,

    output wire [                   4:0] get_reg_id1,
    input  wire [                  31:0] rs1_val_in,
    input  wire                          has_dep1,
    input  wire [`ROB_BIT - 1 : 0] dep1,

    output wire [                   4:0] get_reg_id2,
    input  wire [                  31:0] rs2_val_in,
    input  wire                          has_dep2,
    input  wire [`ROB_BIT - 1 : 0] dep2,

    // from ReorderBuffer
    input  wire                          rob_full,
    input  wire [`ROB_BIT - 1 : 0] rob_free_id,
    // to ReorderBuffer
    output reg                           rob_valid,
    output reg  [ `ROB_TYPE_BIT - 1 : 0] rob_type,
    output reg  [                   4:0] rob_reg_id,
    output reg  [                  31:0] rob_value,
    output reg  [                  31:0] rob_inst_addr,
    output reg  [                  31:0] rob_jump_addr,
    output reg                           rob_ready,

    // from ReservationStation
    input  wire                        rs_full,
    // to ReservationStation
    output reg                         rs_valid,
    output reg  [`RS_TYPE_BIT - 1 : 0] rs_type,
    output wire [                31:0] rs_r1,
    output wire [                31:0] rs_r2,
    output wire [`ROB_BIT - 1:0] rs_dep1,
    output wire [`ROB_BIT - 1:0] rs_dep2,
    output wire                        rs_has_dep1,
    output wire                        rs_has_dep2,
    output wire [`ROB_BIT - 1:0] rs_rob_id,

    // from LoadStoreBuffer
    input  wire                        lsb_full,
    // to LoadStoreBuffer
    output reg                         lsb_valid,
    output reg  [`LS_TYPE_BIT - 1 : 0] lsb_type,
    output wire [                31:0] lsb_r1,
    output wire [                31:0] lsb_r2,
    output wire [`ROB_BIT - 1:0] lsb_dep1,
    output wire [`ROB_BIT - 1:0] lsb_dep2,
    output wire                        lsb_has_dep1,
    output wire                        lsb_has_dep2,
    output reg  [                11:0] lsb_offset,
    output wire [`ROB_BIT - 1:0] lsb_rob_id,

    // to InstFetcher
    output wire        ins_fet_stall,
    output reg         ins_fet_clear,
    output reg  [31:0] ins_fet_set_addr
);
    localparam Lui = 7'b0110111, Aupic = 7'b0010111, Jal = 7'b1101111;
    localparam Jalr = 7'b1100111, Br = 7'b1100011, Load = 7'b0000011;
    localparam Store = 7'b0100011, ArithR = 7'b0110011, ArithI = 7'b0010011;

    wire [  6:0] opcode = inst[6:0];
    wire [  2:0] func = inst[14:12];
    wire [  7:0] ex_func = inst[31:25];

    wire [  4:0] rd = inst[11:7];
    wire [  4:0] rs1 = inst[19:15];
    wire [  4:0] rs2 = inst[24:20];
    wire [31:12] immU = inst[31:12];
    wire [ 20:1] immJ = {inst[31], inst[19:12], inst[20], inst[30:21]};
    wire [ 11:0] immI = inst[31:20];
    wire [ 12:1] immB = {inst[31], inst[7], inst[30:25], inst[11:8]};
    wire [ 11:0] immS = {inst[31:25], inst[11:7]};
    wire [  4:0] shamt = inst[24:20];

    reg [31:0] last_inst_addr;
    wire need_work, ready_work;
    wire need_RS, need_LSB, need_rob, need_reg_s1;

    assign need_work = valid && (last_inst_addr != inst_addr);
    assign need_rob = 1'b1;
    assign need_RS = opcode == Br || opcode == ArithR || opcode == ArithI;
    assign need_LSB = opcode == Load || opcode == Store;
    assign need_reg_s1 = opcode == Jalr;
    assign ready_work = !((need_RS && rs_full) || (need_LSB && lsb_full) || (need_rob && rob_full) || (need_reg_s1 && has_dep1));

    wire use_reg_s1 = opcode == Jalr || opcode == Br || opcode == Load || opcode == Store || opcode == ArithI || opcode == ArithR;
    wire use_reg_s2 = opcode == Br || opcode == Store || opcode == ArithR;

    wire [31:0] next_rs2_val = opcode == ArithI ? ((func == 3'b001 || func == 3'b101) ? shamt : {{20{immI[11]}}, immI}) : rs2_val_in;

    reg [31:0] rs1_val, rs2_val;
    reg is_dep1, is_dep2;
    reg [`ROB_BIT - 1 : 0] dep1_val, dep2_val;

    wire predict_jump = 1'b1;

    always @(posedge clk_in) begin
        if (rst_in) begin
            last_inst_addr <= 32'hffffffff;
            rs1_val <= 0;
            rs2_val <= 0;
            dep1_val <= 0;
            dep2_val <= 0;
            is_dep1 <= 0;
            is_dep2 <= 0;

            lsb_valid <= 0;
            lsb_type <= 0;
            ins_fet_clear <= 0;
            ins_fet_set_addr <= 0;
            rob_value <= 0;
            rob_valid <= 0;
            rob_type <= 0;
            rob_reg_id <= 0;
            rob_ready <= 0;
            rob_inst_addr <= 0;
            rob_jump_addr <= 0;
            rs_valid <= 0;
            rs_type <= 0;
        end
        else if (!rdy_in) begin
        end
        else if (!(need_work && ready_work)) begin
            rob_valid <= 0;
            rs_valid  <= 0;
            lsb_valid <= 0;
            ins_fet_clear  <= 0;
        end
        else begin
            last_inst_addr <= inst_addr;

            rob_valid <= need_rob;
            rs_valid <= need_RS;
            lsb_valid <= need_LSB;

            rs_type <= {(opcode == Br), (opcode == ArithR && inst[30]), func};
            lsb_type <= {(opcode == Load ? 1'b0 : 1'b1), func};
            rob_type <= inst == 32'hff9ff06f ? `ROB_TYPE_EX : opcode == Store ? `ROB_TYPE_ST : opcode == Br ? `ROB_TYPE_BR : `ROB_TYPE_RG;

            rs1_val <= rs1_val_in;
            rs2_val <= next_rs2_val;
            is_dep1 <= use_reg_s1 && has_dep1;
            is_dep2 <= use_reg_s2 && has_dep2;
            dep1_val <= dep1;
            dep2_val <= dep2;
            lsb_offset <= (opcode == Load) ? immI : immS;

            rob_reg_id <= rd;
            rob_inst_addr <= inst_addr;
            // without predictor, default not branch
            rob_jump_addr <= inst_addr + (predict_jump ? 5 : {{19{immB[11]}}, immB, 1'b0});
            rob_ready <= opcode == Lui || opcode == Aupic || opcode == Jal || opcode == Jalr;

            case (opcode)
                Lui: begin
                    rob_value <= {immU, 12'b0};
                end
                Jal: begin
                    rob_value <= inst_addr + 4;
                    ins_fet_clear <= 1;
                    ins_fet_set_addr <= inst_addr + {{12{immJ[19]}}, immJ, 1'b0};
                end
                Jalr: begin
                    rob_value <= inst_addr + 4;
                    ins_fet_clear <= 1;
                    ins_fet_set_addr <= (rs1_val_in + {{20{immI[10]}}, immI}) & ~32'b1;
                end
                ArithI: begin
                end
                Store: begin
                end
                Load: begin
                end
                Br: begin
                    ins_fet_clear <= 1'b1;
                    ins_fet_set_addr <= inst_addr + (predict_jump ? {{19{immB[11]}}, immB, 1'b0} : 4);
                end
                ArithR: begin
                end
                Aupic: begin
                    rob_value <= inst_addr + {immU, 12'b0};
                end
            endcase
        end
    end

    assign ins_fet_stall = need_work && !ready_work;

    assign get_reg_id1 = rs1;
    assign get_reg_id2 = rs2;

    assign rs_r1 = rs1_val;
    assign rs_r2 = rs2_val;
    assign rs_dep1 = dep1_val;
    assign rs_dep2 = dep2_val;
    assign rs_has_dep1 = is_dep1;
    assign rs_has_dep2 = is_dep2;
    assign rs_rob_id = rob_free_id;

    assign lsb_r1 = rs1_val;
    assign lsb_r2 = rs2_val;
    assign lsb_dep1 = dep1_val;
    assign lsb_dep2 = dep2_val;
    assign lsb_has_dep1 = is_dep1;
    assign lsb_has_dep2 = is_dep2;
    assign lsb_rob_id = rob_free_id;
endmodule


module predictor(
    input clk,
    input rst,
    input hci_rdy,
    input branch_record_en,
    input [16:0] branch_address,
    input branch_take,
    input [16:0] q_address,
    output reg q_take
);
    reg [9:0] global_state;
    reg [1:0] global_predictor[1023:0];
    reg [1:0] local_predictor[1023:0];
    
    reg [1:0] selector[1023:0];

    always @(*) begin : predictor_query
        reg [9:0] index;
        index = q_address[9:0];
        q_take = selector[index][1] ? local_predictor[index][1] : global_predictor[global_state][1];
    end

    always @(posedge clk) begin : predictor_sequential
        integer i;
        if (rst) begin
            global_state <= 0;
            for (i = 0; i < 1024; i = i + 1) begin
                global_predictor[i] <= 2'b00;
                local_predictor[i] <= 2'b00;
                selector[i] <= 2'b01;
            end
        end else if (hci_rdy) begin
            if (branch_record_en) begin : predictor_branch_record
                reg [9:0] index;
                index = branch_address[9:0];
                if (global_predictor[global_state][1] == branch_take && local_predictor[index][1] != branch_take) begin
                    selector[index] <= (selector[index] == 0) ? 0 : selector[index] - 1;
                end
                if (global_predictor[global_state][1] != branch_take && local_predictor[index][1] == branch_take) begin
                    selector[index] <= (selector[index] == 2'b11) ? 2'b11 : selector[index] + 1;
                end
                if (branch_take) begin
                    global_predictor[global_state] <= (global_predictor[global_state] == 2'b11) ? 2'b11 : global_predictor[global_state] + 1;
                    local_predictor[index] <= (local_predictor[index] == 2'b11) ? 2'b11 : local_predictor[index] + 1;
                end else begin
                    global_predictor[global_state] <= (global_predictor[global_state] == 0) ? 0 : global_predictor[global_state] - 1;
                    local_predictor[index] <= (local_predictor[index] == 0) ? 0 : local_predictor[index] - 1;
                end
                global_state <= {global_state[8:0], branch_take};
            end
        end
    end
endmodule