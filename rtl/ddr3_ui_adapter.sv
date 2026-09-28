// Adapts 128-bit cache lines to the 256-bit Gowin DDR3 controller interface.
// Each 256-bit DDR3 beat holds two 128-bit lines. Byte masks protect the
// untouched half during writes.

`default_nettype none

module ddr3_ui_adapter #(
    parameter integer WRITE_DRAIN_CYCLES = 64
) (
    input  wire         clk,
    input  wire         rst_n,

    // Line interface (from CDC bridge)
    input  wire         line_request,
    output reg          line_ready,
    input  wire         line_write,
    input  wire [20:0]  line_address,    // 128-bit line address
    input  wire [127:0] line_write_data,
    input  wire [15:0]  line_write_enable,
    output reg          line_response_valid,
    output reg  [127:0] line_read_data,

    // DDR3 controller interface (Gowin IP)
    input  wire         ctrl_cmd_ready,
    output reg  [2:0]   ctrl_cmd,
    output reg          ctrl_cmd_en,
    output reg  [28:0]  ctrl_addr,
    input  wire         ctrl_wr_data_ready,
    output reg  [255:0] ctrl_wr_data,
    output reg          ctrl_wr_data_en,
    output reg          ctrl_wr_data_end,
    output reg  [31:0]  ctrl_wr_data_mask,
    input  wire [255:0] ctrl_rd_data,
    input  wire         ctrl_rd_data_valid,
    output wire         ctrl_burst
);
    localparam [2:0] CMD_WRITE = 3'b000;
    localparam [2:0] CMD_READ  = 3'b001;

    localparam [2:0] S_IDLE         = 3'd0;
    localparam [2:0] S_WRITE        = 3'd1;
    localparam [2:0] S_WRITE_DRAIN  = 3'd2;
    localparam [2:0] S_READ_CMD     = 3'd3;
    localparam [2:0] S_READ_RESP    = 3'd4;

    reg [2:0]  state;
    reg        half_select;
    reg [15:0] drain_count;

    assign ctrl_burst = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= S_IDLE;
            half_select        <= 1'b0;
            drain_count        <= 0;
            line_ready         <= 1'b0;
            line_response_valid <= 1'b0;
            line_read_data     <= 128'b0;
            ctrl_cmd           <= 3'b0;
            ctrl_cmd_en        <= 1'b0;
            ctrl_addr          <= 29'b0;
            ctrl_wr_data       <= 256'b0;
            ctrl_wr_data_en    <= 1'b0;
            ctrl_wr_data_end   <= 1'b0;
            ctrl_wr_data_mask  <= 32'hFFFFFFFF;
        end else begin
            line_ready          <= 1'b0;
            line_response_valid <= 1'b0;
            ctrl_cmd_en         <= 1'b0;
            ctrl_wr_data_en     <= 1'b0;
            ctrl_wr_data_end    <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (line_request) begin
                        // 128-bit line → 256-bit beat: line_address[0] selects upper/lower half
                        // DDR3 address is in 32-bit words, 8 words per 256-bit beat
                        half_select <= line_address[0];
                        ctrl_addr   <= {6'b0, line_address[20:1], 3'b0};

                        if (line_write) begin
                            ctrl_cmd <= CMD_WRITE;
                            // Place data in correct half, mask protects the other
                            if (line_address[0]) begin
                                ctrl_wr_data <= {line_write_data, 128'b0};
                                ctrl_wr_data_mask <= {~line_write_enable, 16'hFFFF};
                            end else begin
                                ctrl_wr_data <= {128'b0, line_write_data};
                                ctrl_wr_data_mask <= {16'hFFFF, ~line_write_enable};
                            end
                            state <= S_WRITE;
                        end else begin
                            ctrl_cmd <= CMD_READ;
                            state <= S_READ_CMD;
                        end
                    end
                end

                S_WRITE: begin
                    if (ctrl_cmd_ready && ctrl_wr_data_ready) begin
                        ctrl_cmd_en      <= 1'b1;
                        ctrl_wr_data_en  <= 1'b1;
                        ctrl_wr_data_end <= 1'b1;
                        drain_count      <= 0;
                        state            <= S_WRITE_DRAIN;
                    end
                end

                S_WRITE_DRAIN: begin
                    if (drain_count >= WRITE_DRAIN_CYCLES - 1) begin
                        line_ready          <= 1'b1;
                        line_response_valid <= 1'b1;
                        state               <= S_IDLE;
                    end else begin
                        drain_count <= drain_count + 1'b1;
                    end
                end

                S_READ_CMD: begin
                    if (ctrl_cmd_ready) begin
                        ctrl_cmd_en <= 1'b1;
                        state       <= S_READ_RESP;
                    end
                end

                S_READ_RESP: begin
                    if (ctrl_rd_data_valid) begin
                        line_read_data <= half_select
                            ? ctrl_rd_data[255:128]
                            : ctrl_rd_data[127:0];
                        line_ready          <= 1'b1;
                        line_response_valid <= 1'b1;
                        state               <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
