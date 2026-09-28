// Top-level DDR3 memory path for U1624.
// Composes: word_line_adapter → memory_cdc_bridge → ddr3_ui_adapter
// Provides a simple word-level interface with bus_ready stalling and
// timeout fault detection.

`default_nettype none

module ddr3_memory_path #(
    parameter integer TIMEOUT_CYCLES     = 4096,
    parameter integer WRITE_DRAIN_CYCLES = 64
) (
    // CPU clock domain
    input  wire         cpu_clk,
    input  wire         cpu_rst_n,

    // CPU bus interface
    input  wire         request,
    input  wire         write_en,
    input  wire [23:0]  address,
    input  wire [15:0]  write_data,
    output wire [15:0]  read_data,
    output wire         ready,
    output wire         response_valid,

    // Fault output — active-high pulse on timeout
    output reg          fault_timeout,

    // Memory clock domain
    input  wire         mem_clk,
    input  wire         mem_rst_n,

    // DDR3 controller interface (directly to Gowin IP)
    input  wire         ctrl_cmd_ready,
    output wire [2:0]   ctrl_cmd,
    output wire         ctrl_cmd_en,
    output wire [28:0]  ctrl_addr,
    input  wire         ctrl_wr_data_ready,
    output wire [255:0] ctrl_wr_data,
    output wire         ctrl_wr_data_en,
    output wire         ctrl_wr_data_end,
    output wire [31:0]  ctrl_wr_data_mask,
    input  wire [255:0] ctrl_rd_data,
    input  wire         ctrl_rd_data_valid,
    output wire         ctrl_burst
);

    // --- Word ↔ Line adapter (CPU clock domain) ---
    wire         wla_line_request;
    wire         wla_line_ready;
    wire         wla_line_write;
    wire [20:0]  wla_line_addr;
    wire [127:0] wla_line_write_data;
    wire [15:0]  wla_line_write_enable;
    wire         wla_line_response_valid;
    wire [127:0] wla_line_read_data;

    word_line_adapter wla (
        .clk(cpu_clk),
        .rst_n(cpu_rst_n),
        .word_request(request),
        .word_ready(ready),
        .word_write(write_en),
        .word_address(address),
        .word_write_data(write_data),
        .word_response_valid(response_valid),
        .word_read_data(read_data),
        .line_request(wla_line_request),
        .line_ready(wla_line_ready),
        .line_write(wla_line_write),
        .line_address(wla_line_addr),
        .line_write_data(wla_line_write_data),
        .line_write_enable(wla_line_write_enable),
        .line_response_valid(wla_line_response_valid),
        .line_read_data(wla_line_read_data)
    );

    // --- CDC bridge (CPU clock → Memory clock) ---
    wire         cdc_mem_request;
    wire         cdc_mem_write;
    wire [20:0]  cdc_mem_line_addr;
    wire [127:0] cdc_mem_write_data;
    wire [15:0]  cdc_mem_write_enable;
    wire         cdc_mem_ready;
    wire         cdc_mem_response_valid;
    wire [127:0] cdc_mem_read_data;

    memory_cdc_bridge cdc (
        .cpu_clk(cpu_clk),
        .cpu_rst_n(cpu_rst_n),
        .cpu_request(wla_line_request),
        .cpu_write(wla_line_write),
        .cpu_line_addr(wla_line_addr),
        .cpu_write_data(wla_line_write_data),
        .cpu_write_enable(wla_line_write_enable),
        .cpu_ready(wla_line_ready),
        .cpu_response_valid(wla_line_response_valid),
        .cpu_read_data(wla_line_read_data),
        .mem_clk(mem_clk),
        .mem_rst_n(mem_rst_n),
        .mem_request(cdc_mem_request),
        .mem_write(cdc_mem_write),
        .mem_line_addr(cdc_mem_line_addr),
        .mem_write_data(cdc_mem_write_data),
        .mem_write_enable(cdc_mem_write_enable),
        .mem_ready(cdc_mem_ready),
        .mem_response_valid(cdc_mem_response_valid),
        .mem_read_data(cdc_mem_read_data)
    );

    // --- DDR3 UI adapter (Memory clock domain) ---
    ddr3_ui_adapter #(
        .WRITE_DRAIN_CYCLES(WRITE_DRAIN_CYCLES)
    ) ui_adapter (
        .clk(mem_clk),
        .rst_n(mem_rst_n),
        .line_request(cdc_mem_request),
        .line_ready(cdc_mem_ready),
        .line_write(cdc_mem_write),
        .line_address(cdc_mem_line_addr),
        .line_write_data(cdc_mem_write_data),
        .line_write_enable(cdc_mem_write_enable),
        .line_response_valid(cdc_mem_response_valid),
        .line_read_data(cdc_mem_read_data),
        .ctrl_cmd_ready(ctrl_cmd_ready),
        .ctrl_cmd(ctrl_cmd),
        .ctrl_cmd_en(ctrl_cmd_en),
        .ctrl_addr(ctrl_addr),
        .ctrl_wr_data_ready(ctrl_wr_data_ready),
        .ctrl_wr_data(ctrl_wr_data),
        .ctrl_wr_data_en(ctrl_wr_data_en),
        .ctrl_wr_data_end(ctrl_wr_data_end),
        .ctrl_wr_data_mask(ctrl_wr_data_mask),
        .ctrl_rd_data(ctrl_rd_data),
        .ctrl_rd_data_valid(ctrl_rd_data_valid),
        .ctrl_burst(ctrl_burst)
    );

    // --- Timeout fault detection (CPU clock domain) ---
    reg [15:0] timeout_cnt;

    always @(posedge cpu_clk or negedge cpu_rst_n) begin
        if (!cpu_rst_n) begin
            timeout_cnt  <= 0;
            fault_timeout <= 1'b0;
        end else begin
            fault_timeout <= 1'b0;
            if (!ready && request) begin
                if (timeout_cnt >= TIMEOUT_CYCLES - 1) begin
                    fault_timeout <= 1'b1;
                    timeout_cnt   <= 0;
                end else begin
                    timeout_cnt <= timeout_cnt + 1'b1;
                end
            end else if (ready) begin
                timeout_cnt <= 0;
            end
        end
    end
endmodule

`default_nettype wire
