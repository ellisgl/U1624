// Mock DDR3 controller for simulation.
// Behaves like the Gowin DDR3_Memory_Interface_Top with configurable
// read latency. Backs onto a simple 256-bit-wide memory array.

`timescale 1ns / 1ps
`default_nettype none

module mock_ddr3_controller #(
    parameter integer MEM_DEPTH    = 1024,  // number of 256-bit beats
    parameter integer READ_LATENCY = 4      // cycles from cmd to rd_data_valid
) (
    input  wire         clk,
    input  wire         rst_n,

    output wire         cmd_ready,
    input  wire [2:0]   cmd,
    input  wire         cmd_en,
    input  wire [28:0]  addr,

    output wire         wr_data_ready,
    input  wire [255:0] wr_data,
    input  wire         wr_data_en,
    input  wire         wr_data_end,
    input  wire [31:0]  wr_data_mask,

    output reg  [255:0] rd_data,
    output reg          rd_data_valid,

    input  wire         burst
);
    localparam [2:0] CMD_WRITE = 3'b000;
    localparam [2:0] CMD_READ  = 3'b001;

    // Always ready to accept commands
    assign cmd_ready     = 1'b1;
    assign wr_data_ready = 1'b1;

    // Backing memory — addressed by beat index (addr >> 3)
    reg [255:0] mem [0:MEM_DEPTH-1];

    // Read pipeline
    reg [READ_LATENCY-1:0] rd_valid_pipe;
    reg [255:0]            rd_data_pipe [0:READ_LATENCY-1];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data       <= 256'b0;
            rd_data_valid <= 1'b0;
            rd_valid_pipe <= 0;
            for (i = 0; i < READ_LATENCY; i = i + 1) begin
                rd_data_pipe[i] <= 256'b0;
            end
        end else begin
            // Handle write commands
            if (cmd_en && cmd == CMD_WRITE && wr_data_en) begin
                // Apply byte mask (0 = write, 1 = mask/protect)
                for (i = 0; i < 32; i = i + 1) begin
                    if (!wr_data_mask[i])
                        mem[addr[9:0]][i*8 +: 8] <= wr_data[i*8 +: 8];
                end
            end

            // Handle read commands — pipeline with latency
            if (cmd_en && cmd == CMD_READ) begin
                rd_valid_pipe[0]  <= 1'b1;
                rd_data_pipe[0]   <= mem[addr[9:0]];
            end else begin
                rd_valid_pipe[0]  <= 1'b0;
                rd_data_pipe[0]   <= 256'b0;
            end

            // Shift pipeline
            for (i = 1; i < READ_LATENCY; i = i + 1) begin
                rd_valid_pipe[i] <= rd_valid_pipe[i-1];
                rd_data_pipe[i]  <= rd_data_pipe[i-1];
            end

            // Output from end of pipeline
            rd_data_valid <= rd_valid_pipe[READ_LATENCY-1];
            rd_data       <= rd_data_pipe[READ_LATENCY-1];
        end
    end

    // Initialize memory to zero
    integer j;
    initial begin
        for (j = 0; j < MEM_DEPTH; j = j + 1)
            mem[j] = 256'b0;
    end
endmodule

`default_nettype wire
