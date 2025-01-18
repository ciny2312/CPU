`include "const.v"
// RISCV32I CPU top module
// port modification allowed for debugging purposes

module cpu (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input  wire [ 7 : 0] mem_din,   // data input bus
    output wire [ 7 : 0] mem_dout,  // data output bus
    output wire [31 : 0] mem_a,     // address bus (only 17 : 0 is used)
    output wire          mem_wr,    // write/read signal (1 for write)

    input wire io_buffer_full,  // 1 if uart buffer is full

    output wire [31 : 0] dbgreg_dout  // cpu register output (debugging demo)
);

    // implementation goes here

    // Specifications : 
    // - Pause cpu(freeze pc, registers, etc.) when rdy_in is low
    // - Memory read result will be returned in the next cycle. Write takes 1 cycle(no need to wait)
    // - Memory is of size 128KB, with valid address ranging from 0x0 to 0x20000
    // - I/O port is mapped to address higher than 0x30000 (mem_a[17 : 16]==2'b11)
    // - 0x30000 read :  read a byte from input
    // - 0x30000 write :  write a byte to output (write 0x00 is ignored)
    // - 0x30004 read :  read clocks passed since cpu starts (in dword, 4 bytes)
    // - 0x30004 write :  indicates program stop (will output '\0' through uart tx)

    wire [                 4 : 0] set_reg_id;
    wire [                31 : 0] set_val;
    wire [`ROB_BIT - 1 : 0] set_reg_on_rob_id;
    wire [                 4 : 0] set_dep_reg_id;
    wire [`ROB_BIT - 1 : 0] set_dep_rob_id;
    wire [                 4 : 0] get_id1;
    wire [                31 : 0] get_val1;
    wire                          get_has_dep1;
    wire [`ROB_BIT - 1 : 0] get_dep1;
    wire [                 4 : 0] get_id2;
    wire [                31 : 0] get_val2;
    wire                          get_has_dep2;
    wire [`ROB_BIT - 1 : 0] get_dep2;

    wire [`ROB_BIT - 1 : 0] get_rob_id1;
    wire                          rob_value1_ready;
    wire [                  31:0] rob_value1;
    wire [`ROB_BIT - 1 : 0] get_rob_id2;
    wire                          rob_value2_ready;
    wire [                  31:0] rob_value2;
    wire                          rob_clear;

    RegisterFile register_file (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .rob_clear(rob_clear),

        .set_reg_id       (set_reg_id),
        .set_val          (set_val),
        .set_reg_on_rob_id(set_reg_on_rob_id),
        .set_dep_reg_id   (set_dep_reg_id),
        .set_dep_rob_id   (set_dep_rob_id),

        .get_id1     (get_id1),
        .get_val1    (get_val1),
        .get_has_dep1(get_has_dep1),
        .get_dep1    (get_dep1),
        .get_id2     (get_id2),
        .get_val2    (get_val2),
        .get_has_dep2(get_has_dep2),
        .get_dep2    (get_dep2),

        .get_rob_id1     (get_rob_id1),
        .rob_value1_ready(rob_value1_ready),
        .rob_value1      (rob_value1),
        .get_rob_id2     (get_rob_id2),
        .rob_value2_ready(rob_value2_ready),
        .rob_value2      (rob_value2)
    );

    wire          icache_ready;
    wire          if_need_inst;
    wire [31 : 0] if_addr_needed;
    wire [31 : 0] if_inst_in;
    wire [31 : 0] if_addr_out;
    wire [31 : 0] if_inst_out;

    wire          lsb2cache_valid;
    wire          lsb2cache_wr;
    wire [ 2 : 0] lsb2cache_size;
    wire [31 : 0] lsb2cache_addr;
    wire [31 : 0] lsb2cache_value;
    wire          cache2lsb_ready;
    wire [31 : 0] cache2lsb_res;
//    initial begin
//        $display("here");
//    end

    Cache cache (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .mem_din (mem_din),
        .mem_dout(mem_dout),
        .mem_a   (mem_a),
        .mem_wr  (mem_wr),
        .io_buffer_full(io_buffer_full),

        .rob_clear(rob_clear),

        .inst_valid(if_need_inst),
        .PC        (if_addr_needed),
        .inst_ready(icache_ready),
        .inst_res  (if_inst_in),

        .data_valid(lsb2cache_valid),
        .data_wr   (lsb2cache_wr),
        .data_size (lsb2cache_size),
        .data_addr (lsb2cache_addr),
        .data_value(lsb2cache_value),
        .data_ready(cache2lsb_ready),
        .data_res  (cache2lsb_res)
    );

    wire          dc2if_stall;
    wire          dc2if_clear;
    wire [  31:0] dc2if_new_pc;
    wire [31 : 0] rob2if_new_pc;
    wire          if_ready;

    InstFetcher inst_fetcher (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .need_inst    (if_need_inst),
        .PC           (if_addr_needed),
        .inst_ready_in(icache_ready),
        .inst_in      (if_inst_in),

        .dc_stall      (dc2if_stall),
        .dc_clear      (dc2if_clear),
        .dc_new_pc     (dc2if_new_pc),
        .inst_ready_out(if_ready),
        .inst_addr     (if_addr_out),
        .inst_out      (if_inst_out),

        .rob_clear (rob_clear),
        .rob_new_pc(rob2if_new_pc)
    );


    // from ReorderBuffer
    wire                          rob_full;
    wire [`ROB_BIT - 1 : 0] rob_id_tail;
    // Decoder to ReorderBuffer
    wire                          dc2rob_valid;
    wire [ `ROB_TYPE_BIT - 1 : 0] dc2rob_type;
    wire [                 4 : 0] dc2rob_reg_id;
    wire [                31 : 0] dc2rob_value;
    wire [                31 : 0] dc2rob_inst_addr;
    wire [                31 : 0] dc2rob_jump_addr;
    wire                          dc2rob_ready;

    // from ReservationStation
    wire                          rs_full;
    // Decoder to ReservationStation
    wire                          dc2rs_valid;
    wire [  `RS_TYPE_BIT - 1 : 0] dc2rs_type;
    wire [                31 : 0] dc2rs_r1;
    wire [                31 : 0] dc2rs_r2;
    wire [`ROB_BIT - 1 : 0] dc2rs_dep1;
    wire [`ROB_BIT - 1 : 0] dc2rs_dep2;
    wire                          dc2rs_has_dep1;
    wire                          dc2rs_has_dep2;
    wire [`ROB_BIT - 1 : 0] dc2rs_rob_id;

    // from LoadStoreBuffer
    wire                          lsb_full;
    // Decoder to LoadStoreBuffer
    wire                          dc2lsb_valid;
    wire [  `LS_TYPE_BIT - 1 : 0] dc2lsb_type;
    wire [                31 : 0] dc2lsb_r1;
    wire [                31 : 0] dc2lsb_r2;
    wire [`ROB_BIT - 1 : 0] dc2lsb_dep1;
    wire [`ROB_BIT - 1 : 0] dc2lsb_dep2;
    wire                          dc2lsb_has_dep1;
    wire                          dc2lsb_has_dep2;
    wire [                11 : 0] dc2lsb_offset;
    wire [`ROB_BIT - 1 : 0] dc2lsb_rob_id;

    Decoder decoder (
        .clk_in(clk_in),
        .rst_in(rst_in | rob_clear),
        .rdy_in(rdy_in),

        .valid    (if_ready),
        .inst_addr(if_addr_out),
        .inst     (if_inst_out),

        .get_reg_id1(get_id1),
        .rs1_val_in (get_val1),
        .has_dep1   (get_has_dep1),
        .dep1       (get_dep1),
        .get_reg_id2(get_id2),
        .rs2_val_in (get_val2),
        .has_dep2   (get_has_dep2),
        .dep2       (get_dep2),

        .rob_full     (rob_full),
        .rob_free_id  (rob_id_tail),
        .rob_valid    (dc2rob_valid),
        .rob_type     (dc2rob_type),
        .rob_reg_id   (dc2rob_reg_id),
        .rob_value    (dc2rob_value),
        .rob_inst_addr(dc2rob_inst_addr),
        .rob_jump_addr(dc2rob_jump_addr),
        .rob_ready    (dc2rob_ready),

        .rs_full    (rs_full),
        .rs_valid   (dc2rs_valid),
        .rs_type    (dc2rs_type),
        .rs_r1      (dc2rs_r1),
        .rs_r2      (dc2rs_r2),
        .rs_dep1    (dc2rs_dep1),
        .rs_dep2    (dc2rs_dep2),
        .rs_has_dep1(dc2rs_has_dep1),
        .rs_has_dep2(dc2rs_has_dep2),
        .rs_rob_id  (dc2rs_rob_id),

        .lsb_full    (lsb_full),
        .lsb_valid   (dc2lsb_valid),
        .lsb_type    (dc2lsb_type),
        .lsb_r1      (dc2lsb_r1),
        .lsb_r2      (dc2lsb_r2),
        .lsb_dep1    (dc2lsb_dep1),
        .lsb_dep2    (dc2lsb_dep2),
        .lsb_has_dep1(dc2lsb_has_dep1),
        .lsb_has_dep2(dc2lsb_has_dep2),
        .lsb_offset  (dc2lsb_offset),
        .lsb_rob_id  (dc2lsb_rob_id),

        .ins_fet_stall   (dc2if_stall),
        .ins_fet_clear   (dc2if_clear),
        .ins_fet_set_addr(dc2if_new_pc)
    );

    // from ReorderBuffer
    wire                          rob_empty;
    wire [`ROB_BIT - 1 : 0] rob_id_head;

    // output of LoadStoreBuffer
    wire                          lsb_ready;
    wire [`ROB_BIT - 1 : 0] lsb_rob_id;
    wire [                31 : 0] lsb_value;
    // output of ReservationStation
    wire                          rs_ready;
    wire [`ROB_BIT - 1 : 0] rs_rob_id;
    wire [                31 : 0] rs_value;

    ReservationStaion rs (
        .clk_in(clk_in),
        .rst_in(rst_in | rob_clear),
        .rdy_in(rdy_in),

        .inst_valid   (dc2rs_valid),
        .inst_type    (dc2rs_type),
        .inst_rob_id  (dc2rs_rob_id),
        .inst_r1      (dc2rs_r1),
        .inst_r2      (dc2rs_r2),
        .inst_dep1    (dc2rs_dep1),
        .inst_dep2    (dc2rs_dep2),
        .inst_has_dep1(dc2rs_has_dep1),
        .inst_has_dep2(dc2rs_has_dep2),

        .full(rs_full),

        .rs_ready  (rs_ready),
        .rs_rob_id (rs_rob_id),
        .rs_value  (rs_value),
        .lsb_ready (lsb_ready),
        .lsb_rob_id(lsb_rob_id),
        .lsb_value (lsb_value)
    );

    LoadStoreBuffer lsb (
        .clk_in(clk_in),
        .rst_in(rst_in | rob_clear),
        .rdy_in(rdy_in),

        .inst_valid   (dc2lsb_valid),
        .inst_type    (dc2lsb_type),
        .inst_r1      (dc2lsb_r1),
        .inst_r2      (dc2lsb_r2),
        .ins_dep_1    (dc2lsb_dep1),
        .ins_dep_2    (dc2lsb_dep2),
        .ins_has_dep1(dc2lsb_has_dep1),
        .ins_has_dep2(dc2lsb_has_dep2),
        .inst_offset  (dc2lsb_offset),
        .inst_rob_id  (dc2lsb_rob_id),

        .full(lsb_full),

        .c_valid(lsb2cache_valid),
        .c_wr   (lsb2cache_wr),
        .c_size (lsb2cache_size),
        .c_addr (lsb2cache_addr),
        .c_value(lsb2cache_value),
        .c_ready(cache2lsb_ready),
        .c_res  (cache2lsb_res),

        .rob_empty  (rob_empty),
        .rob_id_head(rob_id_head),

        .rs_ready (rs_ready),
        .rs_rob_id(rs_rob_id),
        .rs_value (rs_value),

        .lsb_ready (lsb_ready),
        .lsb_rob_id(lsb_rob_id),
        .lsb_value (lsb_value)
    );

    ReorderBuffer rob (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .inst_valid    (dc2rob_valid),
        .inst_ready    (dc2rob_ready),
        .inst_type     (dc2rob_type),
        .inst_rd       (dc2rob_reg_id),
        .inst_value    (dc2rob_value),
        .inst_pc       (dc2rob_inst_addr),
        .inst_jump_addr(dc2rob_jump_addr),

        .get_rob_id1     (get_rob_id1),
        .rob_value1_ready(rob_value1_ready),
        .rob_value1      (rob_value1),
        .get_rob_id2     (get_rob_id2),
        .rob_value2_ready(rob_value2_ready),
        .rob_value2      (rob_value2),

        .rs_ready  (rs_ready),
        .rs_rob_id (rs_rob_id),
        .rs_value  (rs_value),
        .lsb_ready (lsb_ready),
        .lsb_rob_id(lsb_rob_id),
        .lsb_value (lsb_value),

        .full(rob_full),
        .empty(rob_empty),
        .rob_id_head(rob_id_head),
        .rob_id_tail(rob_id_tail),

        .set_reg_id       (set_reg_id),
        .set_val          (set_val),
        .set_reg_on_rob_id(set_reg_on_rob_id),
        .set_dep_reg_id   (set_dep_reg_id),
        .set_dep_rob_id   (set_dep_rob_id),

        .clear (rob_clear),
        .new_pc(rob2if_new_pc)

    );

endmodule