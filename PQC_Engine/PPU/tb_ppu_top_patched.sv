`timescale 1ns/1ps
import ppu_pkg::*;

module tb_ppu_top();

    parameter DATA_WIDTH = 32;

    // DUT Signals
    logic                  clk;
    logic                  rst_n;
    logic                  start;
    logic [2:0]            algo_mode;
    logic [3:0]            math_mode;
    logic                  ntt_inverse;
    
    logic [DATA_WIDTH-1:0] port_a_in [4];
    logic [DATA_WIDTH-1:0] port_b_in [4];
    
    logic                  all_done;
    logic                  we_r0  [4];
    logic                  we_r1  [4];
    logic [DATA_WIDTH-1:0] r0_out [4];
    logic [DATA_WIDTH-1:0] r1_out [4];

    // Verification Memory and Queues
    logic [DATA_WIDTH-1:0] mem_A [0:959];
    logic [DATA_WIDTH-1:0] mem_B [0:959];
    logic [DATA_WIDTH-1:0] mem_R0 [0:959];
    logic [DATA_WIDTH-1:0] mem_R1 [0:959];
    
    logic [DATA_WIDTH-1:0] exp_R0_queue [$];
    logic [DATA_WIDTH-1:0] exp_R1_queue [$];

    integer tests_passed = 0;
    integer tests_failed = 0;

    // Instantiate DUT
    ppu_top #(.DATA_WIDTH(DATA_WIDTH)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .algo_mode(algo_mode), .math_mode(math_mode), .ntt_inverse(ntt_inverse),
        .port_a_in(port_a_in), .port_b_in(port_b_in),
        .all_done(all_done), .we_r0(we_r0), .we_r1(we_r1),
        .r0_out(r0_out), .r1_out(r1_out)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // ==========================================
    // Math Checker Block
    // ==========================================
        integer r0_passed = 0;
    integer r0_failed = 0;
    integer r1_passed = 0;
    integer r1_failed = 0;
    
    logic [31:0] expected_0;
    logic [31:0] expected_1;

    always @(posedge clk) begin
        if (we_r0[0]) begin

            if (op_count < 32 && name == "Kyber FWD NTT") begin
                $display("SV_TRACE_FWD: op=%0d a=%0d b=%0d zeta=%0d mult=%0d add=%0d sub=%0d",
                    op_count,
                    expected_0_a, // We will track A and B
                    expected_0_b,
                    dut.gen_ppu_lanes[0].u_butterfly.u_datapath.mult_in_b_reg, // zeta
                    dut.gen_ppu_lanes[0].u_butterfly.u_datapath.mult_out_raw,
                    dut.gen_ppu_lanes[0].u_butterfly.u_datapath.add_out_raw,
                    dut.gen_ppu_lanes[0].u_butterfly.u_datapath.sub_out_raw
                );
            end
            op_count++;
            if (exp_R0_queue.size() > 0) begin
                expected_0 = exp_R0_queue.pop_front();
                if (r0_out[0] !== expected_0) begin
                    $display("[FAIL R0] Time: %0t | Exp: R0=%08x | Got: R0=%08x", $time, expected_0, r0_out[0]);
                    r0_failed++;
                end else begin
                    r0_passed++;
                end
            end
        end
        if (we_r1[0]) begin
            if (exp_R1_queue.size() > 0) begin
                expected_1 = exp_R1_queue.pop_front();
                if (r1_out[0] !== expected_1) begin
                    $display("[FAIL R1] Time: %0t | Exp: R1=%08x | Got: R1=%08x", $time, expected_1, r1_out[0]);
                    r1_failed++;
                end else begin
                    r1_passed++;
                end
            end
        end
    end

    // ==========================================
    // Test Task
    // ==========================================
    task run_test_sequence(input int start_idx, input int count, input logic [2:0] algo, input logic [3:0] mode, input logic inv, input string name);
        $display("--- Starting %s ---", name);
        
        // 1. Assert Start (S_IDLE -> S_INIT)
        @(posedge clk);
        algo_mode   = algo;
        math_mode   = mode;
        ntt_inverse = inv;
        start       = 1;
        
        // 2. Wait for S_INIT state
        @(posedge clk);
        start = 0; // Handshake complete
        
        // 3. Wait for S_EXECUTE state (Hardware is now ready for data)
        @(posedge clk); 
        
        // 4. Fire the continuous data stream
        for (int i = 0; i < count; i++) begin
            port_a_in[0] = mem_A[start_idx + i];
            port_b_in[0] = mem_B[start_idx + i];
            exp_R0_queue.push_back(mem_R0[start_idx + i]);
            exp_R1_queue.push_back(mem_R1[start_idx + i]);
            @(posedge clk);
        end
        
        // 5. Wait for pipeline to flush and all_done to assert
        wait(all_done == 1'b1);
        @(posedge clk); 
        $display("--- %s Finished ---", name);
    endtask
    // ==========================================
    // Main FSM
    // ==========================================
    integer fd, status, i;
    initial begin
        // 1. Read Test Vectors
        fd = $fopen("math_vectors_fixed.txt", "r");
        if (fd == 0) begin
            $display("ERROR: Could not open math_vectors_fixed.txt");
            $finish;
        end
        for (i = 0; i < 960; i++) begin
            status = $fscanf(fd, "%x %x %x %x\n", mem_A[i], mem_B[i], mem_R0[i], mem_R1[i]);
        end
        $fclose(fd);

        // 2. Init and Reset
        rst_n = 0; start = 0;
        algo_mode = 0; math_mode = 0; ntt_inverse = 0;
        for(int j=0; j<4; j++) begin port_a_in[j]=0; port_b_in[j]=0; end
        
        #25 rst_n = 1;
        @(posedge clk);
        $display("==================================================");
        $display("   STARTING PPU MATHEMATICAL VERIFICATION");
        $display("==================================================");

        // 3. Run Tests
        // Kyber FWD (224 cycles) -> starts at idx 0
        run_test_sequence(0, 224, 3'd0, FWD_NTT_KYB, 1'b0, "Kyber FWD NTT");
        repeat(5) @(posedge clk);
        
        // Kyber INV (224 cycles) -> starts at idx 224
        run_test_sequence(224, 224, 3'd0, INV_NTT_KYB, 1'b1, "Kyber INV NTT");
        repeat(5) @(posedge clk);

        // Dilithium FWD (256 cycles) -> starts at idx 448
        run_test_sequence(448, 256, 3'd1, FWD_NTT_DIL, 1'b0, "Dilithium FWD NTT");
        repeat(5) @(posedge clk);

        // Dilithium INV (256 cycles) -> starts at idx 704
        run_test_sequence(704, 256, 3'd1, INV_NTT_DIL, 1'b1, "Dilithium INV NTT");
        repeat(5) @(posedge clk);

        // 4. Report
        $display("==================================================");
        $display("   MATHEMATICAL VERIFICATION COMPLETE");
        $display("   Total Checks : %0d", r0_passed + r0_failed + r1_passed + r1_failed);
        $display("   Tests Passed : %0d", r0_passed + r1_passed);
        $display("   Tests Failed : %0d", r0_failed + r1_failed);
        $display("==================================================");
        if ((r0_failed + r1_failed) == 0) $display("   STATUS: PERFECT MATCH! MATH IS FLAWLESS.");
        else                   $display("   STATUS: FAILED.");
        $finish;
    end
endmodule