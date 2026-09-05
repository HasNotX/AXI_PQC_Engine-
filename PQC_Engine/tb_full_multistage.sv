`timescale 1ns/1ps
import agu_pkg::*;
import ppu_pkg::*;

module tb_full_multistage;
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    // SRAMs
    localparam DATA_WIDTH = 32;
    localparam BANK_ADDR_WIDTH = 6;

    logic csr_ppu_start;
    logic csr_ppu_busy;
    logic csr_ppu_done;
    logic [2:0] csr_ppu_algo_mode;
    logic [3:0] csr_ppu_math_mode;
    logic csr_ppu_ntt_inverse;
    buffer_id_e csr_ppu_src1;
    buffer_id_e csr_ppu_src2;
    buffer_id_e csr_ppu_dest;
    addr_mode_e csr_ppu_addr_mode_rd;
    addr_mode_e csr_ppu_addr_mode_wr;

    logic ppu_start;
    logic all_done;
    logic is_intt;
    logic [3:0] math_mode_val;
    logic [2:0] algo_mode_val;
    buffer_id_e ppu_src1;
    buffer_id_e ppu_src2;
    buffer_id_e ppu_dest;
    addr_mode_e ext_ppu_addr_mode_rd;
    addr_mode_e ext_ppu_addr_mode_wr;

    assign csr_ppu_start = ppu_start;
    assign all_done = csr_ppu_done;
    assign csr_ppu_ntt_inverse = is_intt;
    assign csr_ppu_math_mode = math_mode_val;
    assign csr_ppu_algo_mode = algo_mode_val;
    assign csr_ppu_src1 = ppu_src1;
    assign csr_ppu_src2 = ppu_src2;
    assign csr_ppu_dest = ppu_dest;
    assign csr_ppu_addr_mode_rd = ext_ppu_addr_mode_rd;
    assign csr_ppu_addr_mode_wr = ext_ppu_addr_mode_wr;

    // Monitor aliases
    wire [5:0] ppu_wr_batch = u_pqc_top.u_delay_line.delayed_batch_out;
    wire [2:0] ppu_wr_stage = u_pqc_top.u_delay_line.delayed_stage_out;
    wire [5:0] current_batch_out = u_pqc_top.u_ppu.current_batch_out;
    wire [2:0] current_stage_raw = u_pqc_top.u_ppu.current_stage_out;
    wire we_r0 [4] = u_pqc_top.u_ppu.we_r0;
    wire we_r1 [4] = u_pqc_top.u_ppu.we_r1;
    wire [31:0] r0_data [4] = u_pqc_top.u_ppu.r0_out;
    wire [31:0] r1_data [4] = u_pqc_top.u_ppu.r1_out;
    wire [31:0] port_a [4] = u_pqc_top.u_ppu.port_a_in;
    wire [31:0] port_b [4] = u_pqc_top.u_ppu.port_b_in;
    
    // SRAM outputs for SNIPER DEBUG
    wire [31:0] sram_A_rdata [8] = u_pqc_top.agu_rdata_porta;


    pqc_top #(
        .DATA_WIDTH(32),
        .BANK_ADDR_WIDTH(6),
        .ROM_ROWS(128)
    ) u_pqc_top (
        .clk(clk),
        .rst_n(rst_n),
        .csr_ppu_start(csr_ppu_start),
        .csr_ppu_algo_mode(csr_ppu_algo_mode),
        .csr_ppu_math_mode(csr_ppu_math_mode),
        .csr_ppu_src1(csr_ppu_src1),
        .csr_ppu_src2(csr_ppu_src2),
        .csr_ppu_dest(csr_ppu_dest),
        .csr_ppu_ntt_inverse(csr_ppu_ntt_inverse),
        .csr_ppu_addr_mode_rd(csr_ppu_addr_mode_rd),
        .csr_ppu_addr_mode_wr(csr_ppu_addr_mode_wr),
        .csr_ppu_busy(csr_ppu_busy),
        .csr_ppu_done(csr_ppu_done),
        // Placeholders for DMA and PSU
        .csr_dma_start(1'b0),
        .csr_dma_direction(1'b0),
        .csr_dma_buffer_row(5'd0),
        .csr_dma_buffer_id(3'd0),
        .csr_dma_length(9'd0),
        .csr_dma_busy(),
        .csr_dma_done(),
        .csr_psu_start(1'b0),
        .csr_psu_mode(4'd0),
        .csr_psu_busy()
    );

    // Monitor AGU READS going INTO the pipeline
    always_ff @(posedge clk) begin
        if (u_pqc_top.u_ppu.gen_ppu_lanes[0].u_butterfly.u_fsm.current_state == 2) begin // S_EXECUTE
            for (int l = 0; l < 4; l++) begin
                $display("[%0d] AGU_FETCH: stage=%0d rd_batch=%0d lane=%0d fetched_a=%0d fetched_b=%0d", math_mode_val, 
                         current_stage_raw, current_batch_out, l, port_a[l], port_b[l]);
            end
        end
    end

    // Monitor PPU WRITES coming OUT OF the pipeline
    always_ff @(posedge clk) begin
        if (we_r0[0]) begin 
            for (int l = 0; l < 4; l++) begin
                $display("[%0d] PPU_WRITE: stage=%0d wr_batch=%0d lane=%0d r0=%0d r1=%0d", math_mode_val, 
                         ppu_wr_stage, ppu_wr_batch, l, r0_data[l], r1_data[l]);
            end
        end
    end

    // Monitor PPU WRITES for r1-only operations (COMP/DCOMP step 0)
    always_ff @(posedge clk) begin
        if (we_r1[0] && !we_r0[0]) begin 
            for (int l = 0; l < 4; l++) begin
                $display("[%0d] PPU_WRITE_R1: stage=%0d wr_batch=%0d lane=%0d r1=%0d", math_mode_val, 
                         ppu_wr_stage, ppu_wr_batch, l, r1_data[l]);
            end
        end
    end

    // SNIPER DEBUG: Catch Batch 1 exactly as it exits the math pipeline
    always_ff @(posedge clk) begin
        if (we_r0[0] && ppu_wr_batch == 1) begin 
            $display("\n=======================================================");
            $display("BOMBSHELL DEBUG FOR BATCH 1 (LANE 0):");
            $display("PPU Wrote: r0 = %0d, r1 = %0d", r0_data[0], r1_data[0]);
            $display("Datapath registered A = %0d", u_pqc_top.u_ppu.gen_ppu_lanes[0].u_butterfly.u_datapath.mult_in_a_reg);
            $display("Datapath registered B = %0d", u_pqc_top.u_ppu.gen_ppu_lanes[0].u_butterfly.u_datapath.mult_in_b_reg);
            $display("SRAM Bank 4 Output = %0d", sram_A_rdata[4]);
            $display("SRAM Bank 0 Output = %0d", sram_A_rdata[0]);
            
            // UPDATED INSTANCE NAMES HERE
            $display("Target Bank RD A = %0d", u_pqc_top.u_agu.u_mapper_porta_addr.target_bank_rd[0]);
            $display("Target Bank RD B = %0d", u_pqc_top.u_agu.u_mapper_portb_addr.target_bank_rd[0]);
            
            $display("=======================================================\n");
        end
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_full_multistage);
        rst_n = 0; ppu_start = 0; algo_mode_val = 3'd0;
        #25 rst_n = 1;

        #10;
        $readmemh("sram_init_0.hex", u_pqc_top.gen_sram_A[0].u_sram_A.mem);
        $readmemh("sram_init_1.hex", u_pqc_top.gen_sram_A[1].u_sram_A.mem);
        $readmemh("sram_init_2.hex", u_pqc_top.gen_sram_A[2].u_sram_A.mem);
        $readmemh("sram_init_3.hex", u_pqc_top.gen_sram_A[3].u_sram_A.mem);
        $readmemh("sram_init_4.hex", u_pqc_top.gen_sram_A[4].u_sram_A.mem);
        $readmemh("sram_init_5.hex", u_pqc_top.gen_sram_A[5].u_sram_A.mem);
        $readmemh("sram_init_6.hex", u_pqc_top.gen_sram_A[6].u_sram_A.mem);
        $readmemh("sram_init_7.hex", u_pqc_top.gen_sram_A[7].u_sram_A.mem);
        #1; $writememh("debug_sram_A_after_readmemh.hex", u_pqc_top.gen_sram_A[0].u_sram_A.mem);
        $readmemh("sram_init_0.hex", u_pqc_top.gen_sram_B[0].u_sram_B.mem);
        $readmemh("sram_init_1.hex", u_pqc_top.gen_sram_B[1].u_sram_B.mem);
        $readmemh("sram_init_2.hex", u_pqc_top.gen_sram_B[2].u_sram_B.mem);
        $readmemh("sram_init_3.hex", u_pqc_top.gen_sram_B[3].u_sram_B.mem);
        $readmemh("sram_init_4.hex", u_pqc_top.gen_sram_B[4].u_sram_B.mem);
        $readmemh("sram_init_5.hex", u_pqc_top.gen_sram_B[5].u_sram_B.mem);
        $readmemh("sram_init_6.hex", u_pqc_top.gen_sram_B[6].u_sram_B.mem);
        $readmemh("sram_init_7.hex", u_pqc_top.gen_sram_B[7].u_sram_B.mem);

        // FWD NTT on BUF_A0
        $display("\n--- RUNNING FWD NTT (BUF_A0) ---");
        is_intt = 0; math_mode_val = 4'd0; // FWD_NTT_KYB
        ppu_src1 = BUF_A0; ppu_src2 = BUF_A0; ppu_dest = BUF_A0; 
        ext_ppu_addr_mode_rd = ADDR_XOR; ext_ppu_addr_mode_wr = ADDR_CONCAT;
        #10; ppu_start = 1; #20; ppu_start = 0;
        wait(all_done == 1'b1); #10;
        
        $writememh("sram_out_fwd_0.hex", u_pqc_top.gen_sram_A[0].u_sram_A.mem);
        $writememh("sram_out_fwd_1.hex", u_pqc_top.gen_sram_A[1].u_sram_A.mem);
        $writememh("sram_out_fwd_2.hex", u_pqc_top.gen_sram_A[2].u_sram_A.mem);
        $writememh("sram_out_fwd_3.hex", u_pqc_top.gen_sram_A[3].u_sram_A.mem);
        $writememh("sram_out_fwd_4.hex", u_pqc_top.gen_sram_A[4].u_sram_A.mem);
        $writememh("sram_out_fwd_5.hex", u_pqc_top.gen_sram_A[5].u_sram_A.mem);
        $writememh("sram_out_fwd_6.hex", u_pqc_top.gen_sram_A[6].u_sram_A.mem);
        $writememh("sram_out_fwd_7.hex", u_pqc_top.gen_sram_A[7].u_sram_A.mem);

        // FWD NTT on BUF_B0
        $display("\n--- RUNNING FWD NTT (BUF_B0) ---");
        ppu_src1 = BUF_B0; ppu_src2 = BUF_B0; ppu_dest = BUF_B0; 
        ext_ppu_addr_mode_rd = ADDR_XOR; ext_ppu_addr_mode_wr = ADDR_CONCAT;
        #10; ppu_start = 1; #20; ppu_start = 0;
        wait(all_done == 1'b1); #10;

        // BASEMUL
        $display("\n--- RUNNING BASEMUL ---");
        is_intt = 0; math_mode_val = 4'd4; // B_MUL_KYB
        ppu_src1 = BUF_A0; ppu_src2 = BUF_B0; ppu_dest = BUF_B1; 
        ext_ppu_addr_mode_rd = ADDR_CONCAT; ext_ppu_addr_mode_wr = ADDR_XOR;
        #20; ppu_start = 1; #20; ppu_start = 0;
        wait(all_done == 1'b1); #10;
        
        $writememh("sram_out_basemul_0.hex", u_pqc_top.gen_sram_B[0].u_sram_B.mem);
        $writememh("sram_out_basemul_1.hex", u_pqc_top.gen_sram_B[1].u_sram_B.mem);
        $writememh("sram_out_basemul_2.hex", u_pqc_top.gen_sram_B[2].u_sram_B.mem);
        $writememh("sram_out_basemul_3.hex", u_pqc_top.gen_sram_B[3].u_sram_B.mem);
        $writememh("sram_out_basemul_4.hex", u_pqc_top.gen_sram_B[4].u_sram_B.mem);
        $writememh("sram_out_basemul_5.hex", u_pqc_top.gen_sram_B[5].u_sram_B.mem);
        $writememh("sram_out_basemul_6.hex", u_pqc_top.gen_sram_B[6].u_sram_B.mem);
        $writememh("sram_out_basemul_7.hex", u_pqc_top.gen_sram_B[7].u_sram_B.mem);

        // INV NTT
        $display("\n--- RUNNING INV NTT ---");
        is_intt = 1; math_mode_val = 4'd2; // INV_NTT_KYB
        ppu_src1 = BUF_B1; ppu_src2 = BUF_B1; ppu_dest = BUF_B1; 
        ext_ppu_addr_mode_rd = ADDR_XOR; ext_ppu_addr_mode_wr = ADDR_XOR;
        
        #20; ppu_start = 1; #20; ppu_start = 0;
        wait(all_done == 1'b1); #10;
        
        // SCALE INTT
        $display("\n--- RUNNING SCALE INTT ---");
        is_intt = 0; math_mode_val = 4'd10; // SCALE_INTT_KYB
        ppu_src1 = BUF_B1; ppu_src2 = BUF_B1; ppu_dest = BUF_B1; 
        ext_ppu_addr_mode_rd = ADDR_FLAT; ext_ppu_addr_mode_wr = ADDR_FLAT;
        
        #20; ppu_start = 1; #20; ppu_start = 0;
        wait(all_done == 1'b1); #10;

        $writememh("sram_out_inv_0.hex", u_pqc_top.gen_sram_B[0].u_sram_B.mem);
        $writememh("sram_out_inv_1.hex", u_pqc_top.gen_sram_B[1].u_sram_B.mem);
        $writememh("sram_out_inv_2.hex", u_pqc_top.gen_sram_B[2].u_sram_B.mem);
        $writememh("sram_out_inv_3.hex", u_pqc_top.gen_sram_B[3].u_sram_B.mem);
        $writememh("sram_out_inv_4.hex", u_pqc_top.gen_sram_B[4].u_sram_B.mem);
        $writememh("sram_out_inv_5.hex", u_pqc_top.gen_sram_B[5].u_sram_B.mem);
        $writememh("sram_out_inv_6.hex", u_pqc_top.gen_sram_B[6].u_sram_B.mem);
        $writememh("sram_out_inv_7.hex", u_pqc_top.gen_sram_B[7].u_sram_B.mem);

        
        // Reload SRAM A for Dilithium testing
        $display("\n--- RELOADING SRAM A FOR DILITHIUM ---");
        #1; $writememh("debug_sram_A_before_readmemh.hex", u_pqc_top.gen_sram_A[0].u_sram_A.mem);
        $readmemh("sram_init_0.hex", u_pqc_top.gen_sram_A[0].u_sram_A.mem);
        $readmemh("sram_init_1.hex", u_pqc_top.gen_sram_A[1].u_sram_A.mem);
        $readmemh("sram_init_2.hex", u_pqc_top.gen_sram_A[2].u_sram_A.mem);
        $readmemh("sram_init_3.hex", u_pqc_top.gen_sram_A[3].u_sram_A.mem);
        $readmemh("sram_init_4.hex", u_pqc_top.gen_sram_A[4].u_sram_A.mem);
        $readmemh("sram_init_5.hex", u_pqc_top.gen_sram_A[5].u_sram_A.mem);
        $readmemh("sram_init_6.hex", u_pqc_top.gen_sram_A[6].u_sram_A.mem);
        $readmemh("sram_init_7.hex", u_pqc_top.gen_sram_A[7].u_sram_A.mem);
        #1; $writememh("debug_sram_A_after_readmemh.hex", u_pqc_top.gen_sram_A[0].u_sram_A.mem);

        // FWD NTT DILITHIUM on BUF_A0
        $display("\n--- RUNNING FWD NTT DILITHIUM (BUF_A0) ---");
        algo_mode_val = 3'd1;
        is_intt = 0; math_mode_val = 4'd1; // FWD_NTT_DIL
        ppu_src1 = BUF_A0; ppu_src2 = BUF_A0; ppu_dest = BUF_A0; 
        ext_ppu_addr_mode_rd = ADDR_XOR; ext_ppu_addr_mode_wr = ADDR_XOR;
        
        #20; ppu_start = 1; #20; ppu_start = 0;
        wait(all_done == 1'b1); #10;
        
        // INV NTT DILITHIUM on BUF_A0
        $display("\n--- RUNNING INV NTT DILITHIUM (BUF_A0) ---");
        is_intt = 1; math_mode_val = 4'd3; // INV_NTT_DIL
        ppu_src1 = BUF_A0; ppu_src2 = BUF_A0; ppu_dest = BUF_A0; 
        ext_ppu_addr_mode_rd = ADDR_XOR; ext_ppu_addr_mode_wr = ADDR_XOR;
        
        #20; ppu_start = 1; #20; ppu_start = 0;
        wait(all_done == 1'b1); #10;

        // SCALE INTT DILITHIUM
        $display("\n--- RUNNING SCALE INTT DILITHIUM ---");
        is_intt = 0; math_mode_val = 4'd11; // SCALE_INTT_DIL
        ppu_src1 = BUF_A0; ppu_src2 = BUF_A0; ppu_dest = BUF_A0; 
        ext_ppu_addr_mode_rd = ADDR_FLAT; ext_ppu_addr_mode_wr = ADDR_FLAT;
        
        #20; ppu_start = 1; #20; ppu_start = 0;
        wait(all_done == 1'b1); #10;

        // RELOAD FOR DILITHIUM BASEMUL
        $display("\n--- RELOADING SRAM FOR DILITHIUM BASEMUL (SEESAW MODE) ---");
        $readmemh("sram_init_seesaw_0.hex", u_pqc_top.gen_sram_A[0].u_sram_A.mem);
        $readmemh("sram_init_seesaw_1.hex", u_pqc_top.gen_sram_A[1].u_sram_A.mem);
        $readmemh("sram_init_seesaw_2.hex", u_pqc_top.gen_sram_A[2].u_sram_A.mem);
        $readmemh("sram_init_seesaw_3.hex", u_pqc_top.gen_sram_A[3].u_sram_A.mem);
        $readmemh("sram_init_seesaw_4.hex", u_pqc_top.gen_sram_A[4].u_sram_A.mem);
        $readmemh("sram_init_seesaw_5.hex", u_pqc_top.gen_sram_A[5].u_sram_A.mem);
        $readmemh("sram_init_seesaw_6.hex", u_pqc_top.gen_sram_A[6].u_sram_A.mem);
        $readmemh("sram_init_seesaw_7.hex", u_pqc_top.gen_sram_A[7].u_sram_A.mem);

        // RUN BASEMUL DILITHIUM
        $display("\n--- RUNNING BASEMUL DILITHIUM ---");
        algo_mode_val = 3'd1;
        is_intt = 0; math_mode_val = 4'd5; // B_MUL_DIL
        ppu_src1 = BUF_A0; ppu_src2 = BUF_A1; ppu_dest = BUF_B1; 
        ext_ppu_addr_mode_rd = ADDR_SEESAW; ext_ppu_addr_mode_wr = ADDR_XOR;
        
        #20; ppu_start = 1; #20; ppu_start = 0;
        wait(all_done == 1'b1); #10;
        
        $writememh("sram_out_basemul_dil_0.hex", u_pqc_top.gen_sram_B[0].u_sram_B.mem);
        $writememh("sram_out_basemul_dil_1.hex", u_pqc_top.gen_sram_B[1].u_sram_B.mem);
        $writememh("sram_out_basemul_dil_2.hex", u_pqc_top.gen_sram_B[2].u_sram_B.mem);
        $writememh("sram_out_basemul_dil_3.hex", u_pqc_top.gen_sram_B[3].u_sram_B.mem);
        $writememh("sram_out_basemul_dil_4.hex", u_pqc_top.gen_sram_B[4].u_sram_B.mem);
        $writememh("sram_out_basemul_dil_5.hex", u_pqc_top.gen_sram_B[5].u_sram_B.mem);
        $writememh("sram_out_basemul_dil_6.hex", u_pqc_top.gen_sram_B[6].u_sram_B.mem);
        $writememh("sram_out_basemul_dil_7.hex", u_pqc_top.gen_sram_B[7].u_sram_B.mem);

        // =====================================================================
        // COMPRESSION TEST (Kyber / ML-KEM-768, d=10)
        // =====================================================================
        // Reload SRAM A and B with fresh polynomial data for compression test.
        // Compression reads coefficients in [0, q-1] and produces d-bit compressed values.
        $display("\n--- RELOADING SRAM A/B FOR COMPRESSION TEST ---");
        $readmemh("sram_init_comp_A_0.hex", u_pqc_top.gen_sram_A[0].u_sram_A.mem);
        $readmemh("sram_init_comp_A_1.hex", u_pqc_top.gen_sram_A[1].u_sram_A.mem);
        $readmemh("sram_init_comp_A_2.hex", u_pqc_top.gen_sram_A[2].u_sram_A.mem);
        $readmemh("sram_init_comp_A_3.hex", u_pqc_top.gen_sram_A[3].u_sram_A.mem);
        $readmemh("sram_init_comp_A_4.hex", u_pqc_top.gen_sram_A[4].u_sram_A.mem);
        $readmemh("sram_init_comp_A_5.hex", u_pqc_top.gen_sram_A[5].u_sram_A.mem);
        $readmemh("sram_init_comp_A_6.hex", u_pqc_top.gen_sram_A[6].u_sram_A.mem);
        $readmemh("sram_init_comp_A_7.hex", u_pqc_top.gen_sram_A[7].u_sram_A.mem);

        $readmemh("sram_init_comp_B_0.hex", u_pqc_top.gen_sram_B[0].u_sram_B.mem);
        $readmemh("sram_init_comp_B_1.hex", u_pqc_top.gen_sram_B[1].u_sram_B.mem);
        $readmemh("sram_init_comp_B_2.hex", u_pqc_top.gen_sram_B[2].u_sram_B.mem);
        $readmemh("sram_init_comp_B_3.hex", u_pqc_top.gen_sram_B[3].u_sram_B.mem);
        $readmemh("sram_init_comp_B_4.hex", u_pqc_top.gen_sram_B[4].u_sram_B.mem);
        $readmemh("sram_init_comp_B_5.hex", u_pqc_top.gen_sram_B[5].u_sram_B.mem);
        $readmemh("sram_init_comp_B_6.hex", u_pqc_top.gen_sram_B[6].u_sram_B.mem);
        $readmemh("sram_init_comp_B_7.hex", u_pqc_top.gen_sram_B[7].u_sram_B.mem);

        // RUN COMPRESSION
        $display("\n--- RUNNING COMPRESSION (ML-KEM-768, d=10) ---");
        algo_mode_val = 3'd0; // ML-KEM-768 => d=10
        is_intt = 0; math_mode_val = 4'd6; // COMP
        ppu_src1 = BUF_A0; ppu_src2 = BUF_B0; ppu_dest = BUF_A0;
        ext_ppu_addr_mode_rd = ADDR_FLAT; ext_ppu_addr_mode_wr = ADDR_FLAT;

        #20; ppu_start = 1; #20; ppu_start = 0;
        wait(all_done == 1'b1); #10;

        $writememh("sram_out_comp_0.hex", u_pqc_top.gen_sram_A[0].u_sram_A.mem);
        $writememh("sram_out_comp_1.hex", u_pqc_top.gen_sram_A[1].u_sram_A.mem);
        $writememh("sram_out_comp_2.hex", u_pqc_top.gen_sram_A[2].u_sram_A.mem);
        $writememh("sram_out_comp_3.hex", u_pqc_top.gen_sram_A[3].u_sram_A.mem);
        $writememh("sram_out_comp_4.hex", u_pqc_top.gen_sram_A[4].u_sram_A.mem);
        $writememh("sram_out_comp_5.hex", u_pqc_top.gen_sram_A[5].u_sram_A.mem);
        $writememh("sram_out_comp_6.hex", u_pqc_top.gen_sram_A[6].u_sram_A.mem);
        $writememh("sram_out_comp_7.hex", u_pqc_top.gen_sram_A[7].u_sram_A.mem);

        // =====================================================================
        // DECOMPRESSION TEST (Kyber / ML-KEM-768, d=10)
        // =====================================================================
        // Reload SRAM A and B with compressed values for decompression test.
        $display("\n--- RELOADING SRAM A/B FOR DECOMPRESSION TEST ---");
        $readmemh("sram_init_decomp_A_0.hex", u_pqc_top.gen_sram_A[0].u_sram_A.mem);
        $readmemh("sram_init_decomp_A_1.hex", u_pqc_top.gen_sram_A[1].u_sram_A.mem);
        $readmemh("sram_init_decomp_A_2.hex", u_pqc_top.gen_sram_A[2].u_sram_A.mem);
        $readmemh("sram_init_decomp_A_3.hex", u_pqc_top.gen_sram_A[3].u_sram_A.mem);
        $readmemh("sram_init_decomp_A_4.hex", u_pqc_top.gen_sram_A[4].u_sram_A.mem);
        $readmemh("sram_init_decomp_A_5.hex", u_pqc_top.gen_sram_A[5].u_sram_A.mem);
        $readmemh("sram_init_decomp_A_6.hex", u_pqc_top.gen_sram_A[6].u_sram_A.mem);
        $readmemh("sram_init_decomp_A_7.hex", u_pqc_top.gen_sram_A[7].u_sram_A.mem);

        $readmemh("sram_init_decomp_B_0.hex", u_pqc_top.gen_sram_B[0].u_sram_B.mem);
        $readmemh("sram_init_decomp_B_1.hex", u_pqc_top.gen_sram_B[1].u_sram_B.mem);
        $readmemh("sram_init_decomp_B_2.hex", u_pqc_top.gen_sram_B[2].u_sram_B.mem);
        $readmemh("sram_init_decomp_B_3.hex", u_pqc_top.gen_sram_B[3].u_sram_B.mem);
        $readmemh("sram_init_decomp_B_4.hex", u_pqc_top.gen_sram_B[4].u_sram_B.mem);
        $readmemh("sram_init_decomp_B_5.hex", u_pqc_top.gen_sram_B[5].u_sram_B.mem);
        $readmemh("sram_init_decomp_B_6.hex", u_pqc_top.gen_sram_B[6].u_sram_B.mem);
        $readmemh("sram_init_decomp_B_7.hex", u_pqc_top.gen_sram_B[7].u_sram_B.mem);

        // RUN DECOMPRESSION
        $display("\n--- RUNNING DECOMPRESSION (ML-KEM-768, d=10) ---");
        algo_mode_val = 3'd0; // ML-KEM-768 => d=10
        is_intt = 0; math_mode_val = 4'd7; // DCOMP
        ppu_src1 = BUF_A0; ppu_src2 = BUF_B0; ppu_dest = BUF_A0;
        ext_ppu_addr_mode_rd = ADDR_FLAT; ext_ppu_addr_mode_wr = ADDR_FLAT;

        #20; ppu_start = 1; #20; ppu_start = 0;
        wait(all_done == 1'b1); #10;

        $writememh("sram_out_decomp_0.hex", u_pqc_top.gen_sram_A[0].u_sram_A.mem);
        $writememh("sram_out_decomp_1.hex", u_pqc_top.gen_sram_A[1].u_sram_A.mem);
        $writememh("sram_out_decomp_2.hex", u_pqc_top.gen_sram_A[2].u_sram_A.mem);
        $writememh("sram_out_decomp_3.hex", u_pqc_top.gen_sram_A[3].u_sram_A.mem);
        $writememh("sram_out_decomp_4.hex", u_pqc_top.gen_sram_A[4].u_sram_A.mem);
        $writememh("sram_out_decomp_5.hex", u_pqc_top.gen_sram_A[5].u_sram_A.mem);
        $writememh("sram_out_decomp_6.hex", u_pqc_top.gen_sram_A[6].u_sram_A.mem);
        $writememh("sram_out_decomp_7.hex", u_pqc_top.gen_sram_A[7].u_sram_A.mem);


        // =====================================================================
        // ADDITION TEST
        // =====================================================================
        $display("\n--- RELOADING SRAM A/B FOR ADDITION TEST ---");
        $readmemh("sram_init_addsub_A_0.hex", u_pqc_top.gen_sram_A[0].u_sram_A.mem);
        $readmemh("sram_init_addsub_A_1.hex", u_pqc_top.gen_sram_A[1].u_sram_A.mem);
        $readmemh("sram_init_addsub_A_2.hex", u_pqc_top.gen_sram_A[2].u_sram_A.mem);
        $readmemh("sram_init_addsub_A_3.hex", u_pqc_top.gen_sram_A[3].u_sram_A.mem);
        $readmemh("sram_init_addsub_A_4.hex", u_pqc_top.gen_sram_A[4].u_sram_A.mem);
        $readmemh("sram_init_addsub_A_5.hex", u_pqc_top.gen_sram_A[5].u_sram_A.mem);
        $readmemh("sram_init_addsub_A_6.hex", u_pqc_top.gen_sram_A[6].u_sram_A.mem);
        $readmemh("sram_init_addsub_A_7.hex", u_pqc_top.gen_sram_A[7].u_sram_A.mem);

        $readmemh("sram_init_addsub_B_0.hex", u_pqc_top.gen_sram_B[0].u_sram_B.mem);
        $readmemh("sram_init_addsub_B_1.hex", u_pqc_top.gen_sram_B[1].u_sram_B.mem);
        $readmemh("sram_init_addsub_B_2.hex", u_pqc_top.gen_sram_B[2].u_sram_B.mem);
        $readmemh("sram_init_addsub_B_3.hex", u_pqc_top.gen_sram_B[3].u_sram_B.mem);
        $readmemh("sram_init_addsub_B_4.hex", u_pqc_top.gen_sram_B[4].u_sram_B.mem);
        $readmemh("sram_init_addsub_B_5.hex", u_pqc_top.gen_sram_B[5].u_sram_B.mem);
        $readmemh("sram_init_addsub_B_6.hex", u_pqc_top.gen_sram_B[6].u_sram_B.mem);
        $readmemh("sram_init_addsub_B_7.hex", u_pqc_top.gen_sram_B[7].u_sram_B.mem);

        $display("\n--- RUNNING ADDITION ---");
        algo_mode_val = 3'd0; 
        is_intt = 0; math_mode_val = 4'd8; // ADD
        ppu_src1 = BUF_A0; ppu_src2 = BUF_B0; ppu_dest = BUF_A1; 
        ext_ppu_addr_mode_rd = ADDR_SEESAW; ext_ppu_addr_mode_wr = ADDR_SEESAW;
        
        #20; ppu_start = 1; #20; ppu_start = 0;
        wait(all_done == 1'b1); #10;
        
        $writememh("sram_out_add_0.hex", u_pqc_top.gen_sram_A[0].u_sram_A.mem);
        $writememh("sram_out_add_1.hex", u_pqc_top.gen_sram_A[1].u_sram_A.mem);
        $writememh("sram_out_add_2.hex", u_pqc_top.gen_sram_A[2].u_sram_A.mem);
        $writememh("sram_out_add_3.hex", u_pqc_top.gen_sram_A[3].u_sram_A.mem);
        $writememh("sram_out_add_4.hex", u_pqc_top.gen_sram_A[4].u_sram_A.mem);
        $writememh("sram_out_add_5.hex", u_pqc_top.gen_sram_A[5].u_sram_A.mem);
        $writememh("sram_out_add_6.hex", u_pqc_top.gen_sram_A[6].u_sram_A.mem);
        $writememh("sram_out_add_7.hex", u_pqc_top.gen_sram_A[7].u_sram_A.mem);

        // =====================================================================
        // SUBTRACTION TEST
        // =====================================================================
        $display("\n--- RUNNING SUBTRACTION ---");
        algo_mode_val = 3'd0; 
        is_intt = 0; math_mode_val = 4'd9; // SUB
        ppu_src1 = BUF_A0; ppu_src2 = BUF_B0; ppu_dest = BUF_B1; 
        ext_ppu_addr_mode_rd = ADDR_SEESAW; ext_ppu_addr_mode_wr = ADDR_SEESAW;
        
        #20; ppu_start = 1; #20; ppu_start = 0;
        wait(all_done == 1'b1); #10;

        $writememh("sram_out_sub_0.hex", u_pqc_top.gen_sram_B[0].u_sram_B.mem);
        $writememh("sram_out_sub_1.hex", u_pqc_top.gen_sram_B[1].u_sram_B.mem);
        $writememh("sram_out_sub_2.hex", u_pqc_top.gen_sram_B[2].u_sram_B.mem);
        $writememh("sram_out_sub_3.hex", u_pqc_top.gen_sram_B[3].u_sram_B.mem);
        $writememh("sram_out_sub_4.hex", u_pqc_top.gen_sram_B[4].u_sram_B.mem);
        $writememh("sram_out_sub_5.hex", u_pqc_top.gen_sram_B[5].u_sram_B.mem);
        $writememh("sram_out_sub_6.hex", u_pqc_top.gen_sram_B[6].u_sram_B.mem);
        $writememh("sram_out_sub_7.hex", u_pqc_top.gen_sram_B[7].u_sram_B.mem);

        $finish;


    end
endmodule