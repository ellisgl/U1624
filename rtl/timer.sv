`timescale 1ns / 1ps

module timer (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [1:0]  reg_addr,
    input  wire [15:0] write_data,
    input  wire        write_en,
    output reg  [15:0] read_data,

    // Interrupt output
    output wire        irq
);

    // Registers
    reg [15:0] reload;
    reg [15:0] count;
    reg        enabled;
    reg        auto_reload;
    reg        pending;

    assign irq = pending;

    // Register reads (combinational)
    always @(*) begin
        case (reg_addr)
            2'd0: read_data = reload;
            2'd1: read_data = count;
            2'd2: read_data = {14'b0, auto_reload, enabled};
            2'd3: read_data = {15'b0, pending};
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reload      <= 16'h0000;
            count       <= 16'h0000;
            enabled     <= 1'b0;
            auto_reload <= 1'b0;
            pending     <= 1'b0;
        end else begin
            // Register writes
            if (write_en) begin
                case (reg_addr)
                    2'd0: begin
                        reload <= write_data;
                        count  <= write_data;
                    end
                    2'd2: begin
                        enabled     <= write_data[0];
                        auto_reload <= write_data[1];
                    end
                    2'd3: begin
                        pending <= 1'b0;
                    end
                    default: ;
                endcase
            end

            // Countdown logic
            if (enabled && count != 16'h0000) begin
                count <= count - 1;
            end else if (enabled && count == 16'h0000) begin
                pending <= 1'b1;
                if (auto_reload) begin
                    count <= reload;
                end else begin
                    enabled <= 1'b0;
                end
            end
        end
    end

endmodule
