
module Cache (
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    input  wire [ 7:0] mem_din,
    output wire [ 7:0] mem_dout,
    output wire [31:0] mem_a,
    output wire        mem_wr,
    input  wire        io_buffer_full,

    input wire rob_clear,

    input wire inst_valid,
    input wire [31:0] PC,
    output wire inst_ready,
    output wire [31:0] inst_res,

    input  wire        data_valid,
    input  wire        data_wr,
    input  wire [ 2:0] data_size,
    input  wire [31:0] data_addr,
    input  wire [31:0] data_value,
    output wire        data_ready,
    output wire [31:0] data_res
);

    reg         mc_enable;
    reg         mc_wr;
    reg  [31:0] mc_addr;
    reg  [ 2:0] mc_len;
    reg  [31:0] mc_data;
    wire        mc_ready;
    wire [31:0] mc_res;
    wire        i_hit;
    wire [31:0] i_res;
    wire        i_we;  // i cache write enable
    InstuctionCache iCache (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .addr(PC),
        .hit (i_hit),
        .res (i_res),
        .we  (i_we),
        .data(mc_res)
    );

    MemoryController memCtrl (
        .clk_in(clk_in),
        .rst_in(rst_in | rob_clear),
        .rdy_in(rdy_in),

        .mem_din(mem_din),
        .mem_dout(mem_dout),
        .mem_a(mem_a),
        .mem_wr(mem_wr),
        .io_buffer_full(io_buffer_full),

        .valid(mc_enable),
        .wr(mc_wr),
        .addr(mc_addr),
        .len(mc_len),
        .data(mc_data),
        .ready(mc_ready),
        .res(mc_res)
    );
    initial begin    
        $write("!!!\n");
        $display("This is a test.");
    end

    reg working;
    reg work_type;

    assign data_ready = working && work_type && mc_ready;
    assign data_res = mc_res;
    assign inst_ready = i_hit;
    assign inst_res = i_res;
    assign i_we = working && !work_type && mc_ready;

    always @(posedge clk_in) begin
        if (rst_in | rob_clear) begin
            working <= 0;
            work_type <= 0;
            mc_enable <= 0;
            mc_wr <= 0;
            mc_addr <= 0;
            mc_len <= 0;
            mc_data <= 0;
        end
        else if (rdy_in&&!working) begin
            if (data_valid) begin
                working <= 1;
                work_type <= 1;
                mc_enable <= 1;
                mc_wr <= data_wr;
                mc_addr <= data_addr;
                mc_len <= data_size;
                mc_data <= data_value;
            end
            else if (inst_valid && !inst_ready) begin
                working <= 1;
                work_type <= 0;
                mc_enable <= 1;
                mc_wr <= 0;
                mc_addr <= PC;
                mc_len <= 3'b010;
                mc_data <= 0;
            end
        end
        else if (mc_ready) begin
            working   <= 0;
            mc_enable <= 0;
        end
    end

endmodule