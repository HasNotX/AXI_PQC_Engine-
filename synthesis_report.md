# PQC Engine Synthesis & Timing Report

## 1. Synthesis Overview
The AXI PQC Wrapper and Engine were synthesized targeting a **Xilinx Zynq UltraScale+ MPSoC (xczu7ev)** to evaluate hardware cost and maximum clock frequency (Fmax) for high-performance edge cryptographic applications. The design leverages DSP slices for the heavy polynomial arithmetic and aggressively utilizes Block RAMs (BRAMs) for the conflict-free SRAM subsystem.

## 2. Resource Utilization Summary
The synthesis results demonstrate a highly efficient footprint on the FPGA. Notably, because the SRAM sub-banks are relatively shallow (Depth=64), Vivado optimally inferred Distributed LUT RAM rather than consuming massive Block RAM primitives, preserving BRAMs for system-level use:
*   **LUTs**: 11,622 / 230,400 (5.0%)
    *   *Includes 640 LUTs inferred as high-speed Distributed RAM.*
*   **Registers (FFs)**: 4,931 / 460,800 (1.0%)
*   **DSP Slices**: 16 / 1,728 (0.9%)
    *   *Directly maps to the 4 parallel PPU lanes executing dual-stage multiplications for Barrett reduction and twiddle factor application.*
*   **Block RAM (BRAM)**: 0 (Optimized out in favor of Distributed RAM)

## 3. Timing & Performance (Fmax)
*   **Target Clock Period**: 3.33 ns (300 MHz)
*   **Achieved Fmax**: **~257 MHz** (Worst Negative Slack: -0.550 ns on a 3.33ns constraint)

At 257 MHz, the engine executes a complete 7-stage Kyber Forward NTT (896 butterfly operations) in approximately **3.4 microseconds**, demonstrating immense throughput well-suited for high-volume network encryption endpoints.

## 4. Critical Path Analysis
**Path Description:**
The real-world Vivado timing report indicates the critical path is heavily routing-dominated (76.4% routing delay, 23.5% logic delay across 14 logic levels). The path originates at the Main Control Unit (`mcu.sv`) state register (`FSM_onehot_current_state_reg`) and terminates at the multiplier operand registers (`mult_in_b_reg_reg`) deep inside the PPU datapath. This massive fanout and combinatorial depth is caused by the global control state driving multiplexers across all 4 parallel butterfly lanes simultaneously.

**Proposed Optimizations:**
To push the Fmax beyond 300+ MHz, the control signal broadcast must be optimized:
1. **Control Signal Register Replication**: The MCU state registers should be replicated (via `(* MAX_FANOUT = "32" *)` or manual instantiation) so each PPU lane receives its own dedicated, locally-routed copy of the control state, slashing the routing delay.
2. **Datapath Pipelining**: Insert an extra pipeline stage between the MCU state generation and the PPU operand multiplexers, allowing the control signals a full clock cycle to traverse the FPGA fabric before evaluating the multiplexer conditions.
