import ppu_pkg::*;

module tag_top #(
    parameter DATA_WIDTH     = 32,
    parameter ROM_ROWS       = 128,  
    parameter ROM_ADDR_WIDTH = $clog2(ROM_ROWS)
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [2:0]            algo_mode, 
    input  logic [3:0]            math_mode, 
    input  logic [2:0]            current_stage,
    input  logic [5:0]            current_batch,
    input  logic                  ntt_inverse, 
    output logic [DATA_WIDTH-1:0] zeta_out [4]
);

    logic [7:0]                  sw_idx;
    logic [ROM_ADDR_WIDTH-1:0]   rom_addr;
    logic [127:0]                rom_row;

    // =====================================================================
    // 1. Control Decoding
    // =====================================================================
    logic is_ml_dsa;
    logic is_base_mul;
    logic is_intt;

    always_comb begin
        is_ml_dsa   = (math_mode == FWD_NTT_DIL) || (math_mode == INV_NTT_DIL) || 
                      (math_mode == B_MUL_DIL)   || (math_mode == SCALE_INTT_DIL) || (algo_mode == 3'd1);
        is_base_mul = (math_mode == B_MUL_KYB)   || (math_mode == B_MUL_DIL);
        is_intt     = (math_mode == INV_NTT_KYB) || (math_mode == INV_NTT_DIL) || ntt_inverse;
    end

    logic [2:0] max_stage;
    assign max_stage = is_ml_dsa ? 3'd7 : 3'd6;

    // =====================================================================
    // 2. Exact Index Calculation
    // =====================================================================
    logic [2:0] batch_shift;
    logic [7:0] group_idx;
    logic [7:0] stage_start_fwd;
    logic [7:0] stage_start_inv;

    always_comb begin
        // Determine hold cycles for Broadcast stages
        case (current_stage)
            3'd0: batch_shift = 3'd5;
            3'd1: batch_shift = 3'd4;
            3'd2: batch_shift = 3'd3;
            3'd3: batch_shift = 3'd2;
            3'd4: batch_shift = 3'd1;
            default: batch_shift = 3'd0; // Stages 5, 6, 7
        endcase

        group_idx       = {2'b00, current_batch} >> batch_shift;
        stage_start_fwd = 8'd1 << current_stage;
        stage_start_inv = (8'd1 << (current_stage + 1)) - 1; // Highest index in the current stage

        if (is_base_mul) begin
            // Base Mul: Jump by 2 (2 twiddles per batch, shared across 4 lanes)
            sw_idx = (8'd1 << max_stage) + ({2'b00, current_batch[5:0]} << 1);
        end else if (current_stage == 3'd7) begin
            // Stage 7: Jump by 4
            sw_idx = is_intt ? (stage_start_inv - ({2'b00, current_batch[5:0]} << 2)) 
                             : (stage_start_fwd + ({2'b00, current_batch[5:0]} << 2));
        end else if (current_stage == 3'd6) begin
            // Stage 6: Jump by 2
            sw_idx = is_intt ? (stage_start_inv - ({2'b00, current_batch[5:0]} << 1))
                             : (stage_start_fwd + ({2'b00, current_batch[5:0]} << 1));
        end else begin
            // Stages 0-5: Step by group_idx
            sw_idx = is_intt ? (stage_start_inv - group_idx)
                             : (stage_start_fwd + group_idx);
        end
    end

    // =====================================================================
    // 3. ROM Instantiation
    // =====================================================================
    assign rom_addr = sw_idx[7:2] + (is_ml_dsa ? 7'd32 : 7'd0);

    twiddle_rom_128 #(
        .ROWS(ROM_ROWS), .ADDR_WIDTH(ROM_ADDR_WIDTH)
    ) u_twiddle_rom (
        .addr  (rom_addr),
        .data_o(rom_row)
    );

    // =====================================================================
    // 4. Precision Twiddle Router
    // =====================================================================
    logic [1:0]  mux_sel;
    logic [31:0] selected_twiddle;

    assign mux_sel = sw_idx[1:0];
    assign selected_twiddle = rom_row[mux_sel * 32 +: 32];

    always_comb begin
        if (is_base_mul) begin
            // FULL MODE (Base Mul)
            // Share twiddles between pairs: Lane 0/1 share z0, Lane 2/3 share z1
            if (sw_idx[1] == 1'b0) begin
                zeta_out[0] = rom_row[31:0];
                zeta_out[1] = rom_row[31:0];
                zeta_out[2] = rom_row[63:32];
                zeta_out[3] = rom_row[63:32];
            end else begin
                zeta_out[0] = rom_row[95:64];
                zeta_out[1] = rom_row[95:64];
                zeta_out[2] = rom_row[127:96];
                zeta_out[3] = rom_row[127:96];
            end
        end else if (current_stage == 3'd7) begin
            // FULL MODE (Dilithium Stage 7)
            if (is_intt) begin
                // INTT counts down (Z0=3, Z1=2, Z2=1, Z3=0)
                zeta_out[0] = rom_row[127:96];
                zeta_out[1] = rom_row[95:64];
                zeta_out[2] = rom_row[63:32];
                zeta_out[3] = rom_row[31:0];
            end else begin
                // FWD counts up (Z0=0, Z1=1, Z2=2, Z3=3)
                zeta_out[0] = rom_row[31:0];
                zeta_out[1] = rom_row[63:32];
                zeta_out[2] = rom_row[95:64];
                zeta_out[3] = rom_row[127:96];
            end
            
        end else if (current_stage == 3'd6) begin
            // PAIR MODE (Stage 6)
            if (is_intt) begin
                if (mux_sel[1]) begin
                    zeta_out[0] = rom_row[127:96]; zeta_out[1] = rom_row[127:96];
                    zeta_out[2] = rom_row[95:64];  zeta_out[3] = rom_row[95:64];
                end else begin
                    zeta_out[0] = rom_row[63:32];  zeta_out[1] = rom_row[63:32];
                    zeta_out[2] = rom_row[31:0];   zeta_out[3] = rom_row[31:0];
                end
            end else begin
                if (mux_sel[1]) begin
                    zeta_out[0] = rom_row[95:64];  zeta_out[1] = rom_row[95:64];
                    zeta_out[2] = rom_row[127:96]; zeta_out[3] = rom_row[127:96];
                end else begin
                    zeta_out[0] = rom_row[31:0];   zeta_out[1] = rom_row[31:0];
                    zeta_out[2] = rom_row[63:32];  zeta_out[3] = rom_row[63:32];
                end
            end
            
        end else begin
            // BROADCAST MODE (Stages 0-5)
            zeta_out[0] = selected_twiddle;
            zeta_out[1] = selected_twiddle;
            zeta_out[2] = selected_twiddle;
            zeta_out[3] = selected_twiddle;
        end
    end
endmodule