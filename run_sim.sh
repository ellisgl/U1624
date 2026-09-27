#!/bin/bash

# Exit immediately if any command fails
set -e

echo "=== Step 1: Running Assembler ==="
python3 tools/assembler.py

echo ""
echo "=== Step 2: Compiling RTL & Testbench ==="
iverilog -g2012 -o sim.out rtl/cpu_core.sv tests/tb_cpu_core.sv

echo ""
echo "=== Step 3: Launching Simulation ==="
vvp sim.out
