module InstFetcher (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    // cache
    output wire        need_inst,
    output reg  [31:0] PC,
    input  wire        inst_ready_in,
    input  wire [31:0] inst_in,

    // lines between decoder
    input  wire        dc_stall,
    input  wire        dc_clear,
    input  wire [31:0] dc_new_pc,
    output reg         inst_ready_out,
    output reg  [31:0] inst_addr,
    output reg  [31:0] inst_out,

    input wire        rob_clear,
    input wire [31:0] rob_new_pc
);
    reg stall;
    wire [31:0] next_PC = rob_clear ? rob_new_pc : dc_clear ? dc_new_pc : PC + 4;
    always @(posedge clk_in) begin
        if (rst_in) begin
            PC <= 0;
            inst_ready_out <= 0;
            inst_addr <= 0;
            inst_out <= 0;
            stall <= 0;
        end
        else if (!rdy_in) begin
            // do nothing
        end
        else if (rob_clear || (stall && dc_clear)) begin
            PC <= next_PC;
            inst_ready_out <= 0;
            inst_addr <= 0;
            inst_out <= 0;
            stall <= 0;
        end
        else if (inst_ready_in && inst_in && !stall && !dc_stall) begin
            PC <= next_PC;
            inst_ready_out <= 1;
            inst_addr <= PC;
            inst_out <= inst_in;

            case (inst_in[6:0])
                7'b1101111, 7'b1100111, 7'b1100011: begin
                    stall <= 1;
                end
            endcase
        end
    end

    assign need_inst = !stall;
endmodule