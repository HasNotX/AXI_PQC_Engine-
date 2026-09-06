# AXI PQC Wrapper Simulation Summary

## Overview
This document summarizes the simulation and verification flow for the **AXI PQC Wrapper** (`pqc_axi_wrapper.sv`). The wrapper exposes an AXI4-Lite slave interface to control the underlying Post-Quantum Cryptography (PQC) Engine, which is designed for executing polynomial arithmetic (such as NTT, Inverse NTT, and Base Multiplication) for Kyber and Dilithium.

## Simulation Setup
We created a dedicated testbench (`tb_axi_wrapper.sv`) to validate the AXI integration. The current simulation flow specifically targets the **Forward NTT (Kyber Mode)** operation to verify the wrapper's control logic.

### What We Ran
1. **SRAM Initialization**: The testbench leverages `generate_sram_init.py` to generate golden, randomly seeded 256-coefficient polynomial vectors. These are loaded into the hardware's physical SRAM banks (representing logical `BUF_A0`) via `$readmemh`.
2. **AXI Configuration**: The AXI master in the testbench uses standard AXI4-Lite handshake tasks to write a single 32-bit control word to the wrapper's `slv_ppu_ctrl` register at offset `0x00`.
   - `start` = 1
   - `algo_mode` = 0 (Kyber)
   - `math_mode` = 0 (FWD NTT KYB)
   - `src1`, `src2`, `dest` = 0 (`BUF_A0`)
   - `ntt_inverse` = 0
   - `addr_mode_rd` = 1 (`ADDR_XOR`)
   - `addr_mode_wr` = 2 (`ADDR_CONCAT`)
   - **Total AXI Write Data**: `0x00240001`
3. **Hardware Execution & Polling**: The AXI master continuously polls the status register at offset `0x04` via AXI reads. It waits for the `ppu_busy` bit to assert (indicating the MCU successfully started the pipeline), and then waits for it to deassert (indicating the 7-stage NTT has completed).
4. **Result Extraction**: Upon completion, the modified SRAM buffers containing the hardware-computed NTT results are dumped back into `.hex` files.

## Verification & Success
The verification flow is fully automated using Python scripts (`verify_simulation_results.py` and `verify_all.py`):
- The `sim_transcript.log`, which contains real-time logs of all Address Generation Unit (AGU) fetches and Polynomial Processing Unit (PPU) memory writes, is parsed.
- Every single butterfly operation and mathematical calculation is independently simulated in Python and compared against the hardware logs.

**Result**: 
```text
==================================================
              MATCH VERIFICATION SUMMARY          
==================================================
[  FWD NTT (BUF_A0)  ] :  896 /  896 matches | PASSED 
==================================================
SUCCESS: All 896 operations match perfectly! 
```

The testbench conclusively proves that the AXI4-Lite wrapper successfully registers the software commands, translates them into internal CSR signals, triggers the PQC Engine, and completes the multi-stage FWD NTT operation flawlessly.
