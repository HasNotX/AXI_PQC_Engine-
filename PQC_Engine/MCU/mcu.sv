import ppu_pkg::*;
import agu_pkg::*;

module mcu (
    input  logic       clk,
    input  logic       rst_n,
    
    // CSR Inputs (Configuration)
    input  logic       csr_ppu_start,
    input  logic [2:0] csr_ppu_algo_mode,
    input  logic [3:0] csr_ppu_math_mode,
    input  logic [2:0] csr_ppu_src1,
    input  logic [2:0] csr_ppu_src2,
    input  logic [2:0] csr_ppu_dest,
    input  logic       csr_ppu_ntt_inverse,
    
    // CSR Outputs (Status)
    output logic       csr_ppu_busy,
    output logic       csr_ppu_done,

    // CSR Addr Mode Inputs
    input  addr_mode_e csr_ppu_addr_mode_rd,
    input  addr_mode_e csr_ppu_addr_mode_wr,

    // Interface to PPU
    output logic       ppu_start_out,
    output logic [2:0] ppu_algo_mode_out,
    output logic [3:0] ppu_math_mode_out,
    output logic       ppu_ntt_inverse_out,
    output addr_mode_e ext_ppu_addr_mode_rd,
    output addr_mode_e ext_ppu_addr_mode_wr,
    input  logic       ppu_all_done_in,

    // Interface to AGU
    output buffer_id_e agu_src1_out,
    output buffer_id_e agu_src2_out,
    output buffer_id_e agu_dest_out
);

    // =========================================================================
    // START PULSE EDGE DETECTOR
    // =========================================================================
    logic start_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) start_q <= 1'b0;
        else        start_q <= csr_ppu_start;
    end
    
    logic start_pulse;
    assign start_pulse = csr_ppu_start && !start_q;

    // =========================================================================
    // FSM FOR PPU LIFECYCLE
    // =========================================================================
    typedef enum logic [1:0] {
        IDLE,
        BUSY,
        DONE
    } state_e;
    state_e current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= IDLE;
        else        current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (start_pulse) next_state = BUSY;
            end
            BUSY: begin
                if (ppu_all_done_in) next_state = DONE;
            end
            DONE: begin
                if (!csr_ppu_start) next_state = IDLE; // Wait for software to clear start
            end
            default: next_state = IDLE;
        endcase
    end

    // =========================================================================
    // OUTPUT LOGIC
    // =========================================================================
    assign csr_ppu_busy  = (current_state == BUSY);
    assign csr_ppu_done  = (current_state == DONE);
    assign ppu_start_out = start_pulse;

    // Latch configuration only while IDLE (protects against CSR changes during run)
    logic [2:0] latched_algo_mode;
    logic [3:0] latched_math_mode;
    logic       latched_ntt_inverse;
    logic [2:0] latched_src1;
    logic [2:0] latched_src2;
    logic [2:0] latched_dest;
    addr_mode_e latched_addr_mode_rd;
    addr_mode_e latched_addr_mode_wr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_algo_mode    <= '0;
            latched_math_mode    <= '0;
            latched_ntt_inverse  <= '0;
            latched_src1         <= '0;
            latched_src2         <= '0;
            latched_dest         <= '0;
            latched_addr_mode_rd <= ADDR_XOR;
            latched_addr_mode_wr <= ADDR_XOR;
        end else if (current_state == IDLE && start_pulse) begin
            latched_algo_mode    <= csr_ppu_algo_mode;
            latched_math_mode    <= csr_ppu_math_mode;
            latched_ntt_inverse  <= csr_ppu_ntt_inverse;
            latched_src1         <= csr_ppu_src1;
            latched_src2         <= csr_ppu_src2;
            latched_dest         <= csr_ppu_dest;
            latched_addr_mode_rd <= csr_ppu_addr_mode_rd;
            latched_addr_mode_wr <= csr_ppu_addr_mode_wr;
        end
    end

    assign ppu_algo_mode_out   = (current_state == IDLE) ? csr_ppu_algo_mode   : latched_algo_mode;
    assign ppu_math_mode_out   = (current_state == IDLE) ? csr_ppu_math_mode   : latched_math_mode;
    assign ppu_ntt_inverse_out = (current_state == IDLE) ? csr_ppu_ntt_inverse : latched_ntt_inverse;
    assign agu_src1_out        = buffer_id_e'((current_state == IDLE) ? csr_ppu_src1 : latched_src1);
    assign agu_src2_out        = buffer_id_e'((current_state == IDLE) ? csr_ppu_src2 : latched_src2);
    assign agu_dest_out        = buffer_id_e'((current_state == IDLE) ? csr_ppu_dest : latched_dest);
    assign ext_ppu_addr_mode_rd = (current_state == IDLE) ? csr_ppu_addr_mode_rd : latched_addr_mode_rd;
    assign ext_ppu_addr_mode_wr = (current_state == IDLE) ? csr_ppu_addr_mode_wr : latched_addr_mode_wr;

endmodule
