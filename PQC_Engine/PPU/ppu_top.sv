import ppu_pkg::*;

module ppu_top #(
    parameter DATA_WIDTH     = 32,
    parameter ROM_ROWS       = 128,  
    parameter ROM_ADDR_WIDTH = $clog2(ROM_ROWS)
)(
    input  logic                  clk,
    input  logic                  rst_n,
    
    // Broadcast Control Signals 
    input  logic                  start,
    output logic [2:0]            current_stage_out,
    output logic [5:0]            current_batch_out,
    output logic [5:0]            next_batch_out,
    output logic [2:0]            next_stage_out,
    output agu_pkg::addr_mode_e   ppu_addr_mode_rd,
    output agu_pkg::addr_mode_e   ppu_addr_mode_wr,
    input  logic [2:0]            algo_mode,
    input  logic [3:0]            math_mode,
    input  logic                  ntt_inverse, // Added for TAG
    input  agu_pkg::addr_mode_e   ext_ppu_addr_mode_rd,
    input  agu_pkg::addr_mode_e   ext_ppu_addr_mode_wr,
    
    // 4 Parallel Input Streams
    input  logic [DATA_WIDTH-1:0] port_a_in [4],
    input  logic [DATA_WIDTH-1:0] port_b_in [4],
    
    // Global Status
    output logic                  all_done,
    
    // 4 Parallel Output Streams & Write Enables
    output logic                  we_r0  [4],
    output logic                  we_r1  [4],
    output logic [DATA_WIDTH-1:0] r0_out [4],
    output logic [DATA_WIDTH-1:0] r1_out [4]
);

    // Internal routing signals
    logic [2:0]            stage_flags [4];
    logic [5:0]            batch_flags [4];
    logic [5:0]            batch_next_flags [4];
    logic [2:0]            stage_next_flags [4];
    agu_pkg::addr_mode_e   addr_mode_rd_flags [4];
    agu_pkg::addr_mode_e   addr_mode_wr_flags [4];
    logic [3:0]            done_flags;
    logic [DATA_WIDTH-1:0] internal_zeta [4];
    
    logic [2:0] current_stage;
    logic [5:0] current_batch;

    // Use Lane 0's FSM state to drive the Twiddle Address Generator
    assign current_stage = stage_flags[0];
    assign current_batch = batch_flags[0];
    assign current_stage_out = current_stage;
    assign current_batch_out = current_batch;
    assign next_batch_out    = batch_next_flags[0];
    assign next_stage_out    = stage_next_flags[0];
    assign ppu_addr_mode_rd  = addr_mode_rd_flags[0];
    assign ppu_addr_mode_wr  = addr_mode_wr_flags[0];

    // =====================================================================
    // Twiddle Address Generator (TAG) Instance
    // =====================================================================
    tag_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ROM_ROWS(ROM_ROWS),
        .ROM_ADDR_WIDTH(ROM_ADDR_WIDTH)
    ) u_tag (
        .clk           (clk),
        .rst_n         (rst_n),
        .algo_mode     (algo_mode),
        .math_mode     (math_mode),
        .current_stage (current_stage),
        .current_batch (current_batch),
        .ntt_inverse   (ntt_inverse),
        .zeta_out      (internal_zeta)
    );

    // =====================================================================
    // PPU Butterfly Lanes
    // =====================================================================
    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : gen_ppu_lanes
            
            ppu_butterfly #(
                .DATA_WIDTH (DATA_WIDTH)
            ) u_butterfly (
                .clk       (clk),
                .rst_n     (rst_n),
                
                .start     (start),
                .algo_mode (algo_mode),
                .math_mode (math_mode),
                .ext_ppu_addr_mode_rd (ext_ppu_addr_mode_rd),
                .ext_ppu_addr_mode_wr (ext_ppu_addr_mode_wr),
                
                .port_a_in (port_a_in[i]),
                .port_b_in (port_b_in[i]),
                .zeta_in   (internal_zeta[i]), // Fed internally from TAG
                
                .all_done  (done_flags[i]),
                .we_r0     (we_r0[i]),
                .we_r1     (we_r1[i]),
                .r0_out    (r0_out[i]),
                .r1_out    (r1_out[i]),

                .current_stage_out (stage_flags[i]),
                .current_batch_out (batch_flags[i]),
                .next_batch_out (batch_next_flags[i]),
                .next_stage_out (stage_next_flags[i]),
                .ppu_addr_mode_rd (addr_mode_rd_flags[i]),
                .ppu_addr_mode_wr (addr_mode_wr_flags[i])
            );
            
        end
    endgenerate

    // Global done flag
    assign all_done = &done_flags;
    
endmodule