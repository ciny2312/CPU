`include "const.v"

module ReservationStaion #(
    parameter RS_SIZE_BIT = `RS_SIZE_BIT
) (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire                           inst_valid,
    input wire [   `RS_TYPE_BIT - 1 : 0] inst_type,
    input wire [`ROB_BIT  - 1 : 0] inst_rob_id,
    input wire [                 31 : 0] inst_r1,
    input wire [                 31 : 0] inst_r2,
    input wire [ `ROB_BIT - 1 : 0] inst_dep1,
    input wire [ `ROB_BIT - 1 : 0] inst_dep2,
    input wire                           inst_has_dep1,
    input wire                           inst_has_dep2,

    output reg full,

    input wire                          lsb_ready,
    input wire [`ROB_BIT - 1 : 0] lsb_rob_id,
    input wire [                31 : 0] lsb_value,

    output wire                          rs_ready,
    output wire [`ROB_BIT - 1 : 0] rs_rob_id,
    output wire [                31 : 0] rs_value
);
    localparam RS_SIZE = 1 << RS_SIZE_BIT;

    reg                           busy      [0 : RS_SIZE - 1];
    reg  [`ROB_BIT - 1 : 0] rob_id    [0 : RS_SIZE - 1];
    reg  [  `RS_TYPE_BIT - 1 : 0] work_type [0 : RS_SIZE - 1];
    reg  [                31 : 0] r1        [0 : RS_SIZE - 1];
    reg  [                31 : 0] r2        [0 : RS_SIZE - 1];
    reg                           has_dep1  [0 : RS_SIZE - 1];
    reg                           has_dep2  [0 : RS_SIZE - 1];
    reg  [`ROB_BIT - 1 : 0] dep1      [0 : RS_SIZE - 1];
    reg  [`ROB_BIT - 1 : 0] dep2      [0 : RS_SIZE - 1];


    wire                          executable[0 : RS_SIZE - 1];
    wire                          free1     [0 : RS_SIZE - 1];
    wire                          free2     [0 : RS_SIZE - 1];
    wire [                31 : 0] sv1       [0 : RS_SIZE - 1];
    wire [                31 : 0] sv2       [0 : RS_SIZE - 1];


    generate
        genvar i;
        for (i = 0; i < RS_SIZE; i = i + 1) begin : Exe
            // assign free1[i] = !has_dep1[i] || (lsb_ready && lsb_rob_id == dep1[i]) || (rs_ready && rs_rob_id == dep1[i]);
            // assign free2[i] = !has_dep2[i] || (lsb_ready && lsb_rob_id == dep2[i]) || (rs_ready && rs_rob_id == dep2[i]);
            // assign sv1[i] = !has_dep1[i] ? r1[i] :  //
            //     (lsb_ready && lsb_rob_id == dep1[i]) ? lsb_value :  //
            //     (rs_ready && rs_rob_id == dep1[i]) ? rs_value : 32'b0;
            // assign sv2[i] = !has_dep2[i] ? r2[i] :  //
            //     (lsb_ready && lsb_rob_id == dep2[i]) ? lsb_value :  //
            //     (rs_ready && rs_rob_id == dep2[i]) ? rs_value : 32'b0;
            // assign executable[i] = busy[i] && free1[i] && free2[i];
            assign executable[i] = busy[i] && !has_dep1[i] && !has_dep2[i];
        end
    endgenerate

    wire shotable;
    wire [RS_SIZE_BIT - 1 : 0] shot_pos;
    wire [RS_SIZE_BIT - 1 : 0] insert_pos;

    generate
        wire tmp_exe[1 : 2 * RS_SIZE - 1];
        wire [RS_SIZE_BIT - 1:0] exe_pos[1 : 2 * RS_SIZE - 1];
        wire tmp_free[1 : 2 * RS_SIZE - 1];
        wire [RS_SIZE_BIT - 1:0] free_pos[1 : 2 * RS_SIZE - 1];
        for (i = RS_SIZE; i < 2 * RS_SIZE; i = i + 1) begin
            assign tmp_exe[i]  = executable[i-RS_SIZE];
            assign exe_pos[i]  = i - RS_SIZE;
            assign tmp_free[i] = ~busy[i-RS_SIZE];
            assign free_pos[i] = i - RS_SIZE;
        end
        for (i = 1; i < RS_SIZE; i = i + 1) begin
            assign tmp_exe[i]  = tmp_exe[i<<1] | tmp_exe[i<<1|1];
            assign exe_pos[i]  = tmp_exe[i<<1] ? exe_pos[i<<1] : exe_pos[i<<1|1];
            assign tmp_free[i] = tmp_free[i<<1] | tmp_free[i<<1|1];
            assign free_pos[i] = tmp_free[i<<1] ? free_pos[i<<1] : free_pos[i<<1|1];
        end
        assign shotable   = tmp_exe[1];
        assign shot_pos   = exe_pos[1];
        assign insert_pos = free_pos[1];
        // assign full = ~tmp_free[1];
    endgenerate

    reg  [       RS_SIZE_BIT : 0] size;
    wire [       RS_SIZE_BIT : 0] next_size = (inst_valid & !shotable) ? size + 1 :
                                              (!inst_valid & shotable) ? size - 1 : size;
    wire next_full = next_size == RS_SIZE;

    alu alu (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .valid(executable[shot_pos]),
        .work_type(work_type[shot_pos]),
        // .r1(sv1[shot_pos]),
        // .r2(sv2[shot_pos]),
        .r1(r1[shot_pos]),
        .r2(r2[shot_pos]),
        .inst_rob_id(rob_id[shot_pos]),
        .ready(rs_ready),
        .rob_id(rs_rob_id),
        .value(rs_value)
    );

    always @(posedge clk_in) begin : MainBlock
        integer i;
        if (rst_in) begin
            for (i = 0; i < RS_SIZE; i = i + 1) begin
                busy[i] <= 0;
                rob_id[i] <= 0;
                work_type[i] <= 0;
                r1[i] <= 0;
                r2[i] <= 0;
                has_dep1[i] <= 0;
                has_dep2[i] <= 0;
                dep1[i] <= 0;
                dep2[i] <= 0;
                size <= 0;
                full <= 0;
            end
        end
        else if (rdy_in) begin
            size <= next_size;
            full <= next_full;
            // insert
            if (inst_valid) begin
                busy[insert_pos] <= 1;
                rob_id[insert_pos] <= inst_rob_id;
                work_type[insert_pos] <= inst_type;
                r1[insert_pos] <= !inst_has_dep1 ? inst_r1 : rs_ready && inst_dep1 == rs_rob_id ? rs_value : lsb_ready && inst_dep1 == lsb_rob_id ? lsb_value : 32'b0;
                r2[insert_pos] <= !inst_has_dep2 ? inst_r2 : rs_ready && inst_dep2 == rs_rob_id ? rs_value : lsb_ready && inst_dep2 == lsb_rob_id ? lsb_value : 32'b0;
                dep1[insert_pos] <= inst_dep1;
                dep2[insert_pos] <= inst_dep2;
                has_dep1[insert_pos] <= inst_has_dep1 && !(rs_ready && inst_dep1 == rs_rob_id) && !(lsb_ready && inst_dep1 == lsb_rob_id);
                has_dep2[insert_pos] <= inst_has_dep2 && !(rs_ready && inst_dep2 == rs_rob_id) && !(lsb_ready && inst_dep2 == lsb_rob_id);
            end
            // update
            for (i = 0; i < RS_SIZE; i = i + 1) begin
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
            // pop
            if (shotable) begin
                busy[shot_pos] <= 0;
            end
        end
    end
endmodule