package ppu_pkg;

    // ==============================================================================
    // MATH MODE CONSTANTS
    // ==============================================================================
    localparam FWD_NTT_KYB = 4'd0,
               FWD_NTT_DIL = 4'd1,
               INV_NTT_KYB = 4'd2,
               INV_NTT_DIL = 4'd3,
               B_MUL_KYB   = 4'd4,
               B_MUL_DIL   = 4'd5,
               COMP        = 4'd6,
               DCOMP       = 4'd7,
               ADD         = 4'd8,
               SUB         = 4'd9,
               SCALE_INTT_KYB =4'd10,
               SCALE_INTT_DIL =4'd11;   

    // ==============================================================================
    // DATAPATH MULTIPLEXER ENUMS
    // ==============================================================================
    
    // --- Multiplier Input A (4 bits) ---
    typedef enum logic [3:0] {
        MULT_A_B          = 4'd0,  // For FWD-NTT
        MULT_A_A_MINUS_B  = 4'd1,  // For INV-NTT
        MULT_A_a0         = 4'd2,  // For Base-Mul Step 0
        MULT_A_a1         = 4'd3,  // For Base-Mul Step 1
        MULT_A_SUM_A      = 4'd4,  // For Base-Mul Step 2
        MULT_A_REGB       = 4'd5,  // For Base-Mul Step 3
        MULT_A_U_SHFT_D   = 4'd6,  // For Compression (u << d)
        MULT_A_V_SHFT_D   = 4'd7,  // For Compression (v << d)
        MULT_A_U          = 4'd8,  // For Decompression (u)
        MULT_A_V          = 4'd9,   // For Decompression (v)
        MULT_A_A          = 4'd10
    } mult_a_sel_t;

    // --- Multiplier Input B (3 bits) ---
    typedef enum logic [2:0] {
        MULT_B_ZETA       = 3'd0,  // For NTT and Base-Mul
        MULT_B_b0         = 3'd1,  // For Base-Mul Step 0
        MULT_B_b1         = 3'd2,  // For Base-Mul Step 1
        MULT_B_SUM_B      = 3'd3,  // For Base-Mul Step 2
        MULT_B_C          = 3'd4,  // For Compression constant C
        MULT_B_Q          = 3'd5,   // For Decompression constant q
        MULT_B_B          = 3'd6,
        MULT_B_INV_N      = 3'd7
    } mult_b_sel_t;

    // --- Adder Input A (3 bits) ---
    typedef enum logic [2:0] {
        ADD_A_A           = 3'd0,  // For NTT, Addition
        ADD_A_a0          = 3'd1,  // For Base-Mul (sum_A)
        ADD_A_b0          = 3'd2,  // For Base-Mul (sum_B)
        ADD_A_REGA        = 3'd3   // For Base-Mul, Comp, Decomp
    } add_a_sel_t;

    // --- Adder Input B (3 bits) ---
    typedef enum logic [2:0] {
        ADD_B_MUL_OUT     = 3'd0,  // For FWD-NTT (B_zeta)
        ADD_B_B           = 3'd1,  // For INV-NTT, Addition
        ADD_B_a1          = 3'd2,  // For Base-Mul (sum_A)
        ADD_B_b1          = 3'd3,  // For Base-Mul (sum_B)
        ADD_B_REGD        = 3'd4,  // For Base-Mul (r0 = rega + regd)
        ADD_B_2_POW_23    = 3'd5,  // For Compression constant
        ADD_B_2_POW_D_1   = 3'd6   // For Decompression constant 2^(d-1)
    } add_b_sel_t;

    // --- Subtractor Input A (2 bits) ---
    typedef enum logic [1:0] {
        SUB_A_A           = 2'd0,  // For NTT, Subtraction
        SUB_A_REGC        = 2'd1,  // For Base-Mul (temp = regc - regb)
        SUB_A_TEMP        = 2'd2,  // For Base-Mul (r1 = temp - rega)
        SUB_A_b0          = 2'd3
    } sub_a_sel_t;

    // --- Subtractor Input B (3 bits) ---
    typedef enum logic [2:0] {
        SUB_B_MUL_OUT     = 3'd0,  // For FWD-NTT (B_zeta)
        SUB_B_B           = 3'd1,  // For INV-NTT, Subtraction
        SUB_B_REGB        = 3'd2,  // For Base-Mul (temp = regc - regb)
        SUB_B_REGA        = 3'd3,  // For Base-Mul (r1 = temp - rega)
        SUB_B_b1          = 3'd4
    } sub_b_sel_t;

endpackage