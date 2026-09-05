`timescale 1ns/1ps
import ppu_pkg::*;

module tb_tag_top();

    parameter DATA_WIDTH = 32;
    
    // DUT Signals
    logic                  clk;
    logic                  rst_n;
    logic [2:0]            algo_mode;
    logic [3:0]            math_mode;
    logic [2:0]            current_stage;
    logic [5:0]            current_batch;
    logic                  ntt_inverse;
    logic [DATA_WIDTH-1:0] zeta_out [4];

    // File I/O and Check Variables
    integer fd;
    integer scan_result;
    integer tests_run;
    integer tests_passed;
    integer tests_failed;
    
    // File reading variables
    logic [2:0]  f_algo;
    logic [3:0]  f_math;
    logic        f_inv;
    logic [2:0]  f_stage;
    logic [5:0]  f_batch;
    logic [31:0] exp_z0, exp_z1, exp_z2, exp_z3;

    // Instantiate DUT
    tag_top #(.DATA_WIDTH(DATA_WIDTH)) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .algo_mode     (algo_mode),
        .math_mode     (math_mode),
        .current_stage (current_stage),
        .current_batch (current_batch),
        .ntt_inverse   (ntt_inverse),
        .zeta_out      (zeta_out)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // Main Test Sequence
    initial begin
        // 1. Initialize
        rst_n = 0; algo_mode = 0; math_mode = 0; current_stage = 0; current_batch = 0; ntt_inverse = 0;
        tests_run = 0; tests_passed = 0; tests_failed = 0;
        
        #15 rst_n = 1;
        @(posedge clk);
        
        $display("==================================================");
        $display("   STARTING AUTOMATED GOLDEN MODEL VERIFICATION   ");
        $display("==================================================");

        // 2. Open Test Vector File
        fd = $fopen("tag_test_vectors.txt", "r");
        if (fd == 0) begin
            $display("ERROR: Could not open tag_test_vectors.txt");
            $finish;
        end

        // 3. Main Loop
        while (!$feof(fd)) begin
            // Read one line from the text file
            scan_result = $fscanf(fd, "%d %d %d %d %d %x %x %x %x\n", 
                                  f_algo, f_math, f_inv, f_stage, f_batch, 
                                  exp_z0, exp_z1, exp_z2, exp_z3);
            
            // If a valid line was read
            if (scan_result == 9) begin
                tests_run++;
                
                // Drive inputs on falling edge to simulate realistic timing
                @(negedge clk);
                algo_mode     = f_algo;
                math_mode     = f_math;
                ntt_inverse   = f_inv;
                current_stage = f_stage;
                current_batch = f_batch;
                
                // Check outputs on rising edge (+ small delay to let combinational logic settle)
                @(posedge clk);
                #1; 
                
                // Verify results
                if (zeta_out[0] !== exp_z0 || zeta_out[1] !== exp_z1 || 
                    zeta_out[2] !== exp_z2 || zeta_out[3] !== exp_z3) begin
                    
                    tests_failed++;
                    $display("[FAIL] Algo:%d Math:%d Stage:%d Batch:%d", f_algo, f_math, f_stage, f_batch);
                    $display("       Expected: Z0=%h Z1=%h Z2=%h Z3=%h", exp_z0, exp_z1, exp_z2, exp_z3);
                    $display("       Got     : Z0=%h Z1=%h Z2=%h Z3=%h", zeta_out[0], zeta_out[1], zeta_out[2], zeta_out[3]);
                end else begin
                    tests_passed++;
                    // Optional: Un-comment next line if you want to see all passes
                    // $display("[PASS] Algo:%d Math:%d Stage:%d Batch:%d", f_algo, f_math, f_stage, f_batch);
                end
            end
        end
        
        $fclose(fd);
        
        // 4. Final Report
        $display("==================================================");
        $display("   VERIFICATION COMPLETE ");
        $display("   Total Tests Run : %0d", tests_run);
        $display("   Tests Passed    : %0d", tests_passed);
        $display("   Tests Failed    : %0d", tests_failed);
        $display("==================================================");
        
        if (tests_failed == 0) $display("   STATUS: PERFECT MATCH! 100%% GOLDEN.");
        else                   $display("   STATUS: FAILED.");
        
        $finish;
    end
endmodule