// Toggle-based clock domain crossing bridge for the DDR3 memory path.
// Transfers one outstanding transaction at a time between the CPU clock
// domain and the memory controller clock domain using two-flop
// synchronizers on toggle signals.

`default_nettype none

module memory_cdc_bridge (
    // CPU clock domain
    input  wire         cpu_clk,
    input  wire         cpu_rst_n,
    input  wire         cpu_request,
    input  wire         cpu_write,
    input  wire [20:0]  cpu_line_addr,
    input  wire [127:0] cpu_write_data,
    input  wire [15:0]  cpu_write_enable,
    output reg          cpu_ready,
    output reg          cpu_response_valid,
    output reg  [127:0] cpu_read_data,

    // Memory clock domain
    input  wire         mem_clk,
    input  wire         mem_rst_n,
    output reg          mem_request,
    output reg          mem_write,
    output reg  [20:0]  mem_line_addr,
    output reg  [127:0] mem_write_data,
    output reg  [15:0]  mem_write_enable,
    input  wire         mem_ready,
    input  wire         mem_response_valid,
    input  wire [127:0] mem_read_data
);

    // --- CPU → Memory: request path ---
    reg        req_toggle_cpu;
    (* async_reg = "true" *) reg [1:0] req_toggle_sync_mem;
    reg        req_toggle_prev_mem;

    // Latch request data in CPU domain
    reg        req_write_lat;
    reg [20:0] req_addr_lat;
    reg [127:0] req_wdata_lat;
    reg [15:0] req_wen_lat;

    // --- Memory → CPU: response path ---
    reg        resp_toggle_mem;
    (* async_reg = "true" *) reg [1:0] resp_toggle_sync_cpu;
    reg        resp_toggle_prev_cpu;
    reg [127:0] resp_data_mem;

    // CPU domain logic
    always @(posedge cpu_clk or negedge cpu_rst_n) begin
        if (!cpu_rst_n) begin
            req_toggle_cpu      <= 1'b0;
            req_write_lat       <= 1'b0;
            req_addr_lat        <= 21'b0;
            req_wdata_lat       <= 128'b0;
            req_wen_lat         <= 16'b0;
            cpu_ready           <= 1'b1;
            cpu_response_valid  <= 1'b0;
            cpu_read_data       <= 128'b0;
            resp_toggle_sync_cpu <= 2'b0;
            resp_toggle_prev_cpu <= 1'b0;
        end else begin
            cpu_response_valid <= 1'b0;

            // Synchronize response toggle into CPU domain
            resp_toggle_sync_cpu <= {resp_toggle_sync_cpu[0], resp_toggle_mem};

            // Detect response toggle edge
            if (resp_toggle_sync_cpu[1] != resp_toggle_prev_cpu) begin
                resp_toggle_prev_cpu <= resp_toggle_sync_cpu[1];
                cpu_read_data        <= resp_data_mem;
                cpu_response_valid   <= 1'b1;
                cpu_ready            <= 1'b1;
            end

            // Accept new request
            if (cpu_request && cpu_ready) begin
                req_write_lat  <= cpu_write;
                req_addr_lat   <= cpu_line_addr;
                req_wdata_lat  <= cpu_write_data;
                req_wen_lat    <= cpu_write_enable;
                req_toggle_cpu <= ~req_toggle_cpu;
                cpu_ready      <= 1'b0;
            end
        end
    end

    // Memory domain logic
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            req_toggle_sync_mem  <= 2'b0;
            req_toggle_prev_mem  <= 1'b0;
            resp_toggle_mem      <= 1'b0;
            resp_data_mem        <= 128'b0;
            mem_request          <= 1'b0;
            mem_write            <= 1'b0;
            mem_line_addr        <= 21'b0;
            mem_write_data       <= 128'b0;
            mem_write_enable     <= 16'b0;
        end else begin
            // Synchronize request toggle into memory domain
            req_toggle_sync_mem <= {req_toggle_sync_mem[0], req_toggle_cpu};

            mem_request <= 1'b0;

            // Detect request toggle edge — new transaction arrived
            if (req_toggle_sync_mem[1] != req_toggle_prev_mem) begin
                req_toggle_prev_mem <= req_toggle_sync_mem[1];
                mem_write        <= req_write_lat;
                mem_line_addr    <= req_addr_lat;
                mem_write_data   <= req_wdata_lat;
                mem_write_enable <= req_wen_lat;
                mem_request      <= 1'b1;
            end

            // Capture response and toggle back
            if (mem_ready && mem_response_valid) begin
                resp_data_mem   <= mem_read_data;
                resp_toggle_mem <= ~resp_toggle_mem;
            end
        end
    end
endmodule

`default_nettype wire
