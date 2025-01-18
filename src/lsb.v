`include "const.v"

module LoadStoreBuffer #(
    parameter LSB_SIZE_BIT = `LSB_SIZE_BIT
) (
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    // from Decoder
    input  wire                        inst_valid,
    input  wire [`LS_TYPE_BIT - 1 : 0] inst_type,
    input  wire [                31:0] inst_r1,
    input  wire [                31:0] inst_r2,
    input  wire [`ROB_BIT - 1:0] ins_dep_1,
    input  wire [`ROB_BIT - 1:0] ins_dep_2,
    input  wire                        ins_has_dep1,
    input  wire                        ins_has_dep2,
    input  wire [                11:0] inst_offset,
    input  wire [`ROB_BIT - 1:0] inst_rob_id,
    // to Decoder
    output reg                         full,

    // with cache
    output wire        c_valid,
    output reg         c_wr,
    output reg  [ 2:0] c_size,
    output reg  [31:0] c_addr,
    output reg  [31:0] c_value,
    input  wire        c_ready,
    input  wire [31:0] c_res,

    // from ReorderBuffer
    input wire                          rob_empty,
    input wire [`ROB_BIT - 1 : 0] rob_id_head,

    // from ReservationStation
    input wire                          rs_ready,
    input wire [`ROB_BIT - 1 : 0] rs_rob_id,
    input wire [                  31:0] rs_value,

    // output LoadStoreBuffer result
    output wire                         lsb_ready,
    output wire [`ROB_BIT- 1 : 0] lsb_rob_id,
    output wire [31:0] lsb_value
);

    localparam LSB_SIZE = 1 << LSB_SIZE_BIT;

    reg  [  LSB_SIZE_BIT - 1:0] head;
    reg  [  LSB_SIZE_BIT - 1:0] tail;
    reg  [    LSB_SIZE_BIT : 0] size;

    reg                         busy     [0 : LSB_SIZE - 1];
    reg  [`ROB_BIT - 1:0] rob_id   [0 : LSB_SIZE - 1];
    reg  [  `LS_TYPE_BIT - 1:0] work_type[0 : LSB_SIZE - 1];
    reg  [                31:0] r1       [0 : LSB_SIZE - 1];
    reg  [                31:0] r2       [0 : LSB_SIZE - 1];
    reg  [`ROB_BIT - 1:0] dep1     [0 : LSB_SIZE - 1];
    reg  [`ROB_BIT - 1:0] dep2     [0 : LSB_SIZE - 1];
    reg                         has_dep1 [0 : LSB_SIZE - 1];
    reg                         has_dep2 [0 : LSB_SIZE - 1];
    reg  [                11:0] offset   [0 : LSB_SIZE - 1];


    wire                        pop_able;

    assign pop_able = c_ready;

    // is_working
    reg work;
    // k : which slot to shot
    wire [LSB_SIZE_BIT - 1 : 0] k = work ? head + 1 : head;
    wire [31:0] need_addr = r1[k] + {{20{offset[k][11]}}, offset[k]};
    wire need_confirm = work_type[k][3] || (need_addr[17:16] == 2'b11);
    wire shot_able = busy[k] && !has_dep1[k] && !has_dep2[k] && (!need_confirm || (!rob_empty && rob_id[k] == rob_id_head));
    wire shot_this_cycle = shot_able && (!work || c_ready);

    assign c_valid = work;

    wire [LSB_SIZE_BIT : 0] next_size = (inst_valid && !pop_able) ? size + 1 : (!inst_valid && pop_able) ? size - 1 : size;
    wire next_full = next_size == LSB_SIZE || next_size + 1 == LSB_SIZE;

    integer i;
//    initial begin
//        $display("lsb here");
//    end
    always @(posedge clk_in) begin
        if (rst_in) begin
            head <= 0;
            tail <= 0;
            size <= 0;
            full <= 0;
            work <= 0;
            for (i = 0; i < LSB_SIZE; i = i + 1) begin : RESET
                r1[i] <= 0;
                r2[i] <= 0;
                has_dep1[i] <= 0;
                has_dep2[i] <= 0;
                dep1[i] <= 0;
                dep2[i] <= 0;
                busy[i] <= 0;
                rob_id[i] <= 0;
                work_type[i] <= 0;
                offset[i] <= 0;
            end
        end
        else if (rdy_in) begin
            size <= next_size;
            full <= next_full;
            if (shot_this_cycle) begin
                work <= 1;
                c_wr <= work_type[k][3];
                c_addr <= need_addr;
                c_size <= work_type[k][2:0];
                c_value <= r2[k];
            end
            else if (work && c_ready) begin
                work <= 0;
            end

            if (inst_valid) begin
                tail <= tail + 1;
                busy[tail] <= 1;
                rob_id[tail] <= inst_rob_id;
                work_type[tail] <= inst_type;
                r1[tail] <= !ins_has_dep1 ? inst_r1 : rs_ready && ins_dep_1 == rs_rob_id ? rs_value : lsb_ready && ins_dep_1 == lsb_rob_id ? lsb_value : 32'b0;
                r2[tail] <= !ins_has_dep2 ? inst_r2 : rs_ready && ins_dep_2 == rs_rob_id ? rs_value : lsb_ready && ins_dep_2 == lsb_rob_id ? lsb_value : 32'b0;
                dep1[tail] <= ins_dep_1;
                dep2[tail] <= ins_dep_2;
                has_dep1[tail] <= ins_has_dep1 && !(rs_ready && ins_dep_1 == rs_rob_id) && !(lsb_ready && ins_dep_1 == lsb_rob_id);
                has_dep2[tail] <= ins_has_dep2 && !(rs_ready && ins_dep_2 == rs_rob_id) && !(lsb_ready && ins_dep_2 == lsb_rob_id);
                offset[tail] <= inst_offset;
            end
            // pop
            if (pop_able) begin
                head <= head + 1;
                busy[head] <= 0;
            end
    
            for (i = 0; i < LSB_SIZE; i = i + 1) begin : UPDATE
                if (busy[i]) begin
                    if (rs_ready && has_dep1[i] && (rs_rob_id == dep1[i])) begin
                        r1[i] <= rs_value;
                        has_dep1[i] <= 0;
                    end
                    if (rs_ready && has_dep2[i] && (rs_rob_id == dep2[i])) begin
                        r2[i] <= rs_value;
                        has_dep2[i] <= 0;
                    end
                    if (lsb_ready && has_dep1[i] && (lsb_rob_id == dep1[i])) begin
                        r1[i] <= lsb_value;
                        has_dep1[i] <= 0;
                    end
                    if (lsb_ready && has_dep2[i] && (lsb_rob_id == dep2[i])) begin
                        r2[i] <= lsb_value;
                        has_dep2[i] <= 0;
                    end
                end
            end
        end
    end

    assign lsb_ready  = c_ready;
    assign lsb_rob_id = rob_id[head];
    assign lsb_value  = c_res;
endmodule