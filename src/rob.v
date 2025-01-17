`include "const.v"

module ReorderBuffer #(
    parameter ROB_SIZE_BIT = `ROB_BIT
) (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    // from decoder
    input wire                         inst_valid,
    input wire                         inst_ready,
    input wire [`ROB_TYPE_BIT - 1 : 0] inst_type,
    input wire [                  4:0] inst_rd,
    input wire [                 31:0] inst_value,
    input wire [                 31:0] inst_pc,
    input wire [                 31:0] inst_jump_addr,

    // from ReservationStation
    input wire                          rs_ready,
    input wire [`ROB_BIT - 1 : 0] rs_rob_id,
    input wire [                  31:0] rs_value,

    // from LoadStoreBuffer
    input wire                          lsb_ready,
    input wire [`ROB_BIT - 1 : 0] lsb_rob_id,
    input wire [                  31:0] lsb_value,

    output wire full,
    output wire empty,
    // to LoadStoreBuffer
    output wire [ROB_SIZE_BIT - 1 : 0] rob_id_head,
    // to Decoder
    output wire [ROB_SIZE_BIT - 1 : 0] rob_id_tail,

    // to Register
    output wire [                 4:0] set_reg_id,
    output wire [                31:0] set_val,
    output wire [`ROB_BIT - 1:0] set_reg_on_rob_id,
    output wire [                 4:0] set_dep_reg_id,
    output wire [`ROB_BIT - 1:0] set_dep_rob_id,

    // between ReorderBuffer and Register
    input  wire [`ROB_BIT - 1 : 0] get_rob_id1,
    output wire                          rob_value1_ready,
    output wire [                  31:0] rob_value1,
    input  wire [`ROB_BIT - 1 : 0] get_rob_id2,
    output wire                          rob_value2_ready,
    output wire [                  31:0] rob_value2,

    output reg clear,
    output reg [31:0] new_pc,

    output reg [15:0] count_finished
);

    localparam ROB_SIZE = 1 << ROB_SIZE_BIT;

    localparam TypeRg = `ROB_TYPE_RG;
    localparam TypeSt = `ROB_TYPE_ST;
    localparam TypeBr = `ROB_TYPE_BR;
    localparam TypeEx = `ROB_TYPE_EX;

    reg                       busy     [0 : ROB_SIZE - 1];
    reg                       ready    [0 : ROB_SIZE - 1];
    reg [`ROB_TYPE_BIT - 1:0] work_type[0 : ROB_SIZE - 1];
    reg [                4:0] rd       [0 : ROB_SIZE - 1];
    reg [               31:0] value    [0 : ROB_SIZE - 1];
    reg [               31:0] inst_addr[0 : ROB_SIZE - 1];
    reg [               31:0] jump_addr[0 : ROB_SIZE - 1];

    reg [ROB_SIZE_BIT - 1:0] head, tail;

    integer i;
    always @(posedge clk_in) begin
        if (rst_in) begin
            count_finished <= 1;
        end
        if (rst_in || (clear && rdy_in)) begin
            clear  <= 0;
            new_pc <= 0;
            for (i = 0; i < ROB_SIZE; i = i + 1) begin
                busy[i] <= 0;
                ready[i] <= 0;
                work_type[i] <= 0;
                rd[i] <= 0;
                value[i] <= 0;
                inst_addr[i] <= 0;
                jump_addr[i] <= 0;
            end
            head <= 0;
            tail <= 0;
        end
        else if (rdy_in) begin
            if (rs_ready) begin
                ready[rs_rob_id] <= 1;
                value[rs_rob_id] <= rs_value;
            end
            if (lsb_ready) begin
                ready[lsb_rob_id] <= 1;
                value[lsb_rob_id] <= lsb_value;
            end
            if (inst_valid) begin
                tail <= tail + 1;
                busy[tail] <= 1;
                ready[tail] <= inst_ready;
                work_type[tail] <= inst_type;
                rd[tail] <= inst_rd;
                value[tail] <= inst_value;
                inst_addr[tail] <= inst_pc;
                jump_addr[tail] <= inst_jump_addr;
                if (head == tail && busy[head] && !ready[head]) begin
                    $display("rob full, still adding");
                    $finish();
                end
            end
            if (busy[head] && ready[head]) begin
                count_finished <= count_finished + 1;
                head <= head + 1;
                busy[head] <= 0;
                ready[head] <= 0;
                case (work_type[head])
                    TypeRg: begin
                        // things are done by wire
                    end
                    TypeSt: begin
                        // do nothing
                    end
                    TypeBr: begin
                        if (value[head][0] ^ jump_addr[head][0]) begin
                            new_pc <= {jump_addr[head][31:1], 1'b0};
                            clear  <= 1;
                        end
                    end
                endcase
            end
        end
    end

    assign full = (head == tail && busy[head]) || (tail + `ROB_BIT'b1 == head && inst_valid && !ready[head]);
    assign empty = head == tail && !busy[head];

    assign rob_id_head = head;
    assign rob_id_tail = tail;

    wire need_set_reg = (rdy_in && busy[head] && ready[head] && work_type[head] == TypeRg);
    assign set_reg_id = need_set_reg ? rd[head] : 0;
    assign set_reg_on_rob_id = need_set_reg ? head : 0;
    assign set_val = need_set_reg ? value[head] : 0;

    wire need_set_dep = rdy_in && inst_valid && inst_type == TypeRg;
    assign set_dep_reg_id = need_set_dep ? inst_rd : 0;
    assign set_dep_rob_id = need_set_dep ? tail : 0;

    assign rob_value1_ready = ready[get_rob_id1] || (rs_ready && rs_rob_id == get_rob_id1) || (lsb_ready && lsb_rob_id == get_rob_id1) || (inst_valid && inst_ready && tail == get_rob_id1);
    assign rob_value1 = ready[get_rob_id1] ? value[get_rob_id1] : (rs_ready && rs_rob_id == get_rob_id1) ? rs_value : (lsb_ready && lsb_rob_id == get_rob_id1) ? lsb_value : inst_value;
    assign rob_value2_ready = ready[get_rob_id2] || (rs_ready && rs_rob_id == get_rob_id2) || (lsb_ready && lsb_rob_id == get_rob_id2) || (inst_valid && inst_ready && tail == get_rob_id2);
    assign rob_value2 = ready[get_rob_id2] ? value[get_rob_id2] : (rs_ready && rs_rob_id == get_rob_id2) ? rs_value : (lsb_ready && lsb_rob_id == get_rob_id2) ? lsb_value : inst_value;
endmodule