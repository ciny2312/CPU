module MemoryController (
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    input  wire [ 7:0] mem_din,
    output wire [ 7:0] mem_dout,
    output wire [31:0] mem_a,
    output wire        mem_wr,
    input  wire        io_buffer_full,

    input  wire        valid,
    input  wire        wr,
    input  wire [31:0] addr,
    input  wire [ 2:0] len,
    input  wire [31:0] data,
    output reg         ready,
    output wire [31:0] res
);
    reg         worked;
    reg  [31:0] work_addr;
    reg         work_wr;
    reg  [ 2:0] work_len;
    reg  [ 2:0] work_cycle;
    reg  [31:0] current_addr;
    reg  [ 7:0] current_data;
    reg         current_wr;
    reg  [31:0] result;
    
    function [31:0] get_result;
        input [2:0] len;
        input [31:0] result;
        input [7:0] mem_din;
        case (len)
            3'b000:  get_result = {24'b0, mem_din};
            3'b100:  get_result = {{24{mem_din[7]}}, mem_din};
            3'b001:  get_result = {16'b0, mem_din[7:0], result[7:0]};
            3'b101:  get_result = {{16{mem_din[7]}}, mem_din[7:0], result[7:0]};
            3'b010:  get_result = {mem_din[7:0], result[23:0]};
            default: get_result = 0;
        endcase
    endfunction

    wire        is_io_mapping = addr[17:16] == 2'b11;
    wire        able_to_write = !(is_io_mapping && wr && io_buffer_full);
    wire        need_work = valid && !ready && able_to_write;

    wire        direct = work_cycle == 0 && need_work;
    assign mem_wr = direct ? wr : current_wr;
    assign mem_a = direct ? addr : current_addr;
    assign mem_dout = direct ? data[7:0] : current_data;

    assign res = get_result(work_len, result, mem_din);

    always @(posedge clk_in) begin
        if (rst_in) begin
            worked <= 0;
            work_addr <= 0;
            work_wr <= 0;
            work_len <= 0;
            work_cycle <= 0;
            current_addr <= 0;
            current_data <= 0;
            current_wr <= 0;
            result <= 0;
            ready <= 0;
        end
        else if (rdy_in) begin
            if (ready) begin
                ready <= 0;
            end
            else begin
                case (work_cycle)
                    3'b000: begin  // not working: waiting or done
                        if (need_work) begin
                            result <= data;
                            worked <= 1;
                            work_len <= len;
                            work_addr <= addr;
                            work_wr    <= wr;
                            if (len[1:0]) begin
                                work_cycle   <= 3'b001;
                                current_addr <= addr + 1;
                                current_data <= data[15:8];
                                current_wr   <= wr;
                            end
                            else begin
                                work_cycle   <= 3'b000;
                                current_addr <= addr[17:16] == 2'b11 ? 0 : addr;
                                current_data <= 0;
                                current_wr   <= 0;
                                ready <= 1;
                            end
                        end
                    end
                    3'b001: begin
                        result[7:0] <= mem_din;
                        if (work_len[1:0] == 2'b01) begin
                            work_cycle   <= 3'b000;
                            current_data <= 0;
                            current_wr   <= 0;
                            ready <= 1;
                            // keep current_addr
                        end
                        else begin
                            work_cycle   <= 3'b010;
                            current_addr <= work_addr + 2;
                            current_data <= data[23:16];
                        end
                    end
                    3'b010: begin
                        result[15:8] <= mem_din;
                        current_addr <= work_addr + 3;
                        current_data <= data[31:24];
                        work_cycle   <= 3'b011;
                    end
                    3'b011: begin
                        result[23:16] <= mem_din;
                        work_cycle <= 3'b000;
                        current_data <= 0;
                        current_wr <= 0;
                        ready <= 1;
                        // keep current_addr
                    end
                endcase
            end
        end
    end

endmodule