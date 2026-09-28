#!/bin/bash

# Exit immediately if any command fails
set -e

# Default source file
SOURCE="${1:-tests/test_program.asm}"

echo "=== Step 1: Running Assembler ==="
python3 tools/assembler.py "$SOURCE"

echo ""
echo "=== Step 2: Compiling RTL & Testbench ==="
iverilog -g2012 -o sim.out rtl/cpu_core.sv rtl/timer.sv rtl/dma_controller.sv rtl/mpu.sv rtl/word_line_adapter.sv rtl/memory_cdc_bridge.sv rtl/ddr3_ui_adapter.sv rtl/ddr3_memory_path.sv tests/mock_ddr3_controller.sv tests/tb_cpu_core.sv

echo ""
echo "=== Step 3: Launching Simulation ==="
vvp sim.out
