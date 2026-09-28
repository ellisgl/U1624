// =============================================================================
// U1624 Memory Protection Unit (MPU)
// =============================================================================
//
// 4-region MPU with base/limit/permissions per region.
// Memory-mapped registers at 0xFFFC-0xFFFF (indirect access):
//   0xFFFC = Control register (region select + global enable)
//   0xFFFD = Base address of selected region
//   0xFFFE = Limit address of selected region
//   0xFFFF = Permissions of selected region
//
// Control register layout:
//   bit [1:0]  = region select (0-3)
//   bit [15]   = global MPU enable
//
// Permission bits per region:
//   bit 0 = user read (and execute)
//   bit 1 = user write
//   bit 7 = region enable
//
// When MPU is enabled and CPU is in user mode:
//   - Each access is checked against all enabled regions
//   - If any enabled region covers the address and grants the
//     requested permission, the access is allowed
//   - If no region matches, a fault is raised
//   - Supervisor mode bypasses all MPU checks
//
// =============================================================================

`timescale 1ns / 1ps

module mpu (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface (memory-mapped at 0xFFFC-0xFFFF)
    input  wire [1:0]  reg_addr,      // 0=control, 1=base, 2=limit, 3=perms
    input  wire [15:0] write_data,
    input  wire        write_en,
    output reg  [15:0] read_data,

    // Access check interface
    input  wire [15:0] check_addr,    // Address being accessed
    input  wire        check_write,   // 1=write access, 0=read/execute
    input  wire        supervisor,    // 1=supervisor mode (bypasses MPU)
    output wire        fault          // 1=access denied
);

    // Region registers
    reg [15:0] base  [0:3];
    reg [15:0] limit [0:3];
    reg [7:0]  perms [0:3];

    // Control register
    reg [1:0]  region_sel;
    reg        mpu_enable;

    // Register read mux
    always @(*) begin
        case (reg_addr)
            2'd0: read_data = {mpu_enable, 13'b0, region_sel};
            2'd1: read_data = base[region_sel];
            2'd2: read_data = limit[region_sel];
            2'd3: read_data = {8'h00, perms[region_sel]};
            default: read_data = 16'h0000;
        endcase
    end

    // Register writes
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            region_sel <= 2'd0;
            mpu_enable <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                base[i]  <= 16'h0000;
                limit[i] <= 16'h0000;
                perms[i] <= 8'h00;
            end
        end else if (write_en) begin
            case (reg_addr)
                2'd0: begin
                    region_sel <= write_data[1:0];
                    mpu_enable <= write_data[15];
                end
                2'd1: base[region_sel]  <= write_data;
                2'd2: limit[region_sel] <= write_data;
                2'd3: perms[region_sel] <= write_data[7:0];
            endcase
        end
    end

    // Combinational access check — all regions checked in parallel
    wire region_match [0:3];
    wire region_allow [0:3];

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : region_check
            assign region_match[g] = perms[g][7] &&
                                     (check_addr >= base[g]) &&
                                     (check_addr <= limit[g]);
            assign region_allow[g] = region_match[g] &&
                                     (check_write ? perms[g][1] : perms[g][0]);
        end
    endgenerate

    wire any_allowed = region_allow[0] || region_allow[1] ||
                       region_allow[2] || region_allow[3];

    assign fault = mpu_enable && !supervisor && !any_allowed;

endmodule
