// Converts a single 16-bit word read/write into a 128-bit cache line
// transaction. Each 128-bit line holds 8 words. On writes, only the
// two bytes corresponding to the target word are enabled.

`default_nettype none

module word_line_adapter (
    input  wire         clk,
    input  wire         rst_n,

    // Word interface (from DDR3 bridge)
    input  wire         word_request,
    output wire         word_ready,
    input  wire         word_write,
    input  wire [23:0]  word_address,     // 24-bit word address
    input  wire [15:0]  word_write_data,
    output reg          word_response_valid,
    output reg  [15:0]  word_read_data,

    // Line interface (to CDC bridge)
    output reg          line_request,
    input  wire         line_ready,
    output reg          line_write,
    output reg  [20:0]  line_address,     // 128-bit line address
    output reg  [127:0] line_write_data,
    output reg  [15:0]  line_write_enable,
    input  wire         line_response_valid,
    input  wire [127:0] line_read_data
);
    localparam [1:0] S_IDLE     = 2'd0;
    localparam [1:0] S_ISSUE    = 2'd1;
    localparam [1:0] S_RESPONSE = 2'd2;

    reg [1:0] state;
    reg [2:0] word_lane;

    assign word_ready = (state == S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= S_IDLE;
            word_lane           <= 3'b0;
            word_response_valid <= 1'b0;
            word_read_data      <= 16'b0;
            line_request        <= 1'b0;
            line_write          <= 1'b0;
            line_address        <= 21'b0;
            line_write_data     <= 128'b0;
            line_write_enable   <= 16'b0;
        end else begin
            word_response_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    line_request <= 1'b0;
                    if (word_request) begin
                        line_write   <= word_write;
                        line_address <= word_address[23:3];
                        word_lane    <= word_address[2:0];

                        // Place word data at the correct lane within the 128-bit line
                        line_write_data <= 128'b0;
                        line_write_data[word_address[2:0] * 16 +: 16] <= word_write_data;

                        // Enable 2 bytes for this word position
                        line_write_enable <= 16'b0;
                        line_write_enable[word_address[2:0] * 2 +: 2] <= 2'b11;

                        line_request <= 1'b1;
                        state        <= S_ISSUE;
                    end
                end

                S_ISSUE: begin
                    if (line_ready) begin
                        line_request <= 1'b0;
                        if (line_response_valid) begin
                            if (!line_write)
                                word_read_data <= line_read_data[word_lane * 16 +: 16];
                            word_response_valid <= 1'b1;
                            state               <= S_IDLE;
                        end else begin
                            state <= S_RESPONSE;
                        end
                    end
                end

                S_RESPONSE: begin
                    if (line_response_valid) begin
                        if (!line_write)
                            word_read_data <= line_read_data[word_lane * 16 +: 16];
                        word_response_valid <= 1'b1;
                        state               <= S_IDLE;
                    end
                end

                default: begin
                    line_request <= 1'b0;
                    state        <= S_IDLE;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
