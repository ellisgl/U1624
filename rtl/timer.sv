// =============================================================================
// U1624 Timer Peripheral
// =============================================================================
//
// A simple countdown timer that can generate interrupts at regular intervals.
// This is a common peripheral in real microcontrollers (think Arduino's Timer0).
//
// How it works:
//   1. Software writes a reload value (e.g., 1000) to set the countdown target
//   2. Software enables the timer via the control register
//   3. The timer decrements the count by 1 every clock cycle
//   4. When count reaches 0:
//      - The "pending" flag is set (this drives the IRQ output)
//      - If auto-reload is enabled, count reloads and keeps going
//      - If auto-reload is disabled, the timer stops
//   5. Software acknowledges the interrupt by writing to the status register,
//      which clears the pending flag and deasserts IRQ
//
// Register Map (accent from the CPU via memory-mapped I/O):
//   Offset 0 (0xFFF2): Reload value — writing also sets the current count
//   Offset 1 (0xFFF3): Current count — read-only view of the countdown
//   Offset 2 (0xFFF4): Control — bit 0: enable, bit 1: auto-reload
//   Offset 3 (0xFFF5): Status  — bit 0: pending (write to acknowledge/clear)
//
// =============================================================================

`timescale 1ns / 1ps

module timer (
    input  wire        clk,        // Clock — timer decrements once per cycle
    input  wire        rst_n,      // Active-low reset

    // Register interface — directly wired by the system's address decoder.
    // reg_addr selects which of the 4 registers to access.
    input  wire [1:0]  reg_addr,   // Which register (0–3)
    input  wire [15:0] write_data, // Data to write
    input  wire        write_en,   // 1 = write, 0 = read
    output reg  [15:0] read_data,  // Data read from selected register

    // Interrupt output — active-high, directly driven by the pending flag.
    // This connects to the system's IRQ OR gate, which feeds the CPU's irq input.
    output wire        irq
);

    // Internal state
    reg [15:0] reload;      // The value loaded into count when (re)starting
    reg [15:0] count;       // Current countdown value — decrements each cycle
    reg        enabled;     // Timer is running when 1
    reg        auto_reload; // When 1, timer restarts automatically after reaching 0
    reg        pending;     // Interrupt pending — set when count reaches 0

    // IRQ is simply the pending flag. It stays asserted until software clears it.
    // This is "level-sensitive" — the CPU sees irq=1 as long as pending=1.
    assign irq = pending;

    // Register reads — combinational (no clock needed).
    // Whenever reg_addr changes, read_data updates instantly.
    always @(*) begin
        case (reg_addr)
            2'd0: read_data = reload;
            2'd1: read_data = count;
            2'd2: read_data = {14'b0, auto_reload, enabled};
            2'd3: read_data = {15'b0, pending};
        endcase
    end

    // Main timer logic — runs on every clock edge
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all state to defaults
            reload      <= 16'h0000;
            count       <= 16'h0000;
            enabled     <= 1'b0;
            auto_reload <= 1'b0;
            pending     <= 1'b0;
        end else begin
            // Handle register writes from the CPU
            if (write_en) begin
                case (reg_addr)
                    2'd0: begin
                        // Writing reload also sets count — this way software
                        // only needs one write to configure and arm the timer.
                        reload <= write_data;
                        count  <= write_data;
                    end
                    2'd2: begin
                        // Control register: bit 0 = enable, bit 1 = auto-reload
                        enabled     <= write_data[0];
                        auto_reload <= write_data[1];
                    end
                    2'd3: begin
                        // Writing to status register acknowledges the interrupt.
                        // This clears the pending flag, which deasserts IRQ.
                        pending <= 1'b0;
                    end
                    default: ; // Count register (offset 1) is read-only
                endcase
            end

            // Countdown logic — runs every cycle when enabled
            if (enabled && count != 16'h0000) begin
                // Still counting down
                count <= count - 1;
            end else if (enabled && count == 16'h0000) begin
                // Timer has fired! Set the pending flag to signal an interrupt.
                pending <= 1'b1;
                if (auto_reload) begin
                    // Restart the countdown from the reload value
                    count <= reload;
                end else begin
                    // One-shot mode: stop the timer after firing
                    enabled <= 1'b0;
                end
            end
        end
    end

endmodule
