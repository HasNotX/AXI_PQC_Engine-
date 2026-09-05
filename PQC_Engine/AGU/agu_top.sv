import agu_pkg::*;

module agu_top #(
    parameter DATA_WIDTH = 32,
    parameter BANK_ADDR_WIDTH = 6 
)(
    input  logic clk,
    input  logic rst_n,

    // [All original inputs/outputs remain exactly the same]
    input  addr_mode_e            ppu_addr_mode_rd,
    input  addr_mode_e            ppu_addr_mode_wr,
    input  buffer_id_e ppu_src1_id,
    input  buffer_id_e ppu_src2_id,
    input  buffer_id_e ppu_dest_id,
    input  buffer_id_e pgu_dest_id,
    input  buffer_id_e dma_src_id,
    input  buffer_id_e dma_dest_id,
    
    input  logic [2:0]            ppu_stage_id,
    input  logic [2:0]            ppu_next_stage_id,
    input  logic [5:0]            ppu_rd_batch,
    input  logic [5:0]            ppu_wr_batch,
    
    input  logic                  ppu_we_r0   [4],
    input  logic                  ppu_we_r1   [4],
    input  logic [DATA_WIDTH-1:0] ppu_r0_data [4],
    input  logic [DATA_WIDTH-1:0] ppu_r1_data [4],
    output logic [DATA_WIDTH-1:0] ppu_port_a_out [4],
    output logic [DATA_WIDTH-1:0] ppu_port_b_out [4],
    
    input  logic                  pgu_burst_valid,
    input  logic [4:0]            pgu_burst_offset,
    input  logic [DATA_WIDTH-1:0] pgu_burst_wdata [8],
    input  logic                  pgu_burst_we    [8],
    
    input  logic                  dma_burst_valid,
    input  logic [4:0]            dma_burst_offset,
    input  logic [DATA_WIDTH-1:0] dma_burst_wdata [8],
    input  logic                  dma_burst_we    [8],
    input  logic                  dma_read_req,
    output logic [DATA_WIDTH-1:0] dma_burst_rdata [8],
    
    output logic [BANK_ADDR_WIDTH-1:0] sram_A_wr_addr [8],
    output logic [BANK_ADDR_WIDTH-1:0] sram_A_rd_addr [8],
    output logic                       sram_A_we      [8],
    output logic [DATA_WIDTH-1:0]      sram_A_wdata   [8],
    input  logic [DATA_WIDTH-1:0]      sram_A_rdata   [8],
    
    output logic [BANK_ADDR_WIDTH-1:0] sram_B_wr_addr [8],
    output logic [BANK_ADDR_WIDTH-1:0] sram_B_rd_addr [8],
    output logic                       sram_B_we      [8],
    output logic [DATA_WIDTH-1:0]      sram_B_wdata   [8],
    input  logic [DATA_WIDTH-1:0]      sram_B_rdata   [8]
);

    // =========================================================================
    // HELPERS
    // =========================================================================
    function automatic logic is_upper_half(input buffer_id_e id);
        return (id == BUF_A0) || (id == BUF_B0);
    endfunction
    function automatic logic is_a_side(input buffer_id_e id);
        return (id == BUF_A0) || (id == BUF_A1);
    endfunction
    function automatic logic is_b_side(input buffer_id_e id);
        return (id == BUF_B0) || (id == BUF_B1);
    endfunction

    // =========================================================================
    // DUMMY SIGNALS
    // =========================================================================
    logic dummy_re [8];
    logic dummy_we [4];
    logic [DATA_WIDTH-1:0] dummy_rdata_zero [8];
    logic [DATA_WIDTH-1:0] dummy_wdata [4];
    
    always_comb begin
        for (int i=0; i<4; i++) dummy_we[i] = 1'b0;
        for (int i=0; i<8; i++) dummy_rdata_zero[i] = '0;
        for (int i=0; i<4; i++) dummy_wdata[i] = '0;
    end

    // =========================================================================
    // TIME DOMAIN SEPARATION REGISTERS
    // Delays the tracking variables by 1 cycle for the returning read data mux
    // =========================================================================
    logic [5:0] ppu_rd_batch_q;
    logic [2:0] ppu_next_stage_id_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ppu_rd_batch_q <= '0;
            ppu_next_stage_id_q <= '0;
        end else begin
            ppu_rd_batch_q <= ppu_rd_batch;
            ppu_next_stage_id_q <= ppu_next_stage_id;
        end
    end

    // =========================================================================
    // PPU MAPPER INSTANCES
    // =========================================================================
    logic [BANK_ADDR_WIDTH-1:0] mapper_porta_addr  [8];
    logic [DATA_WIDTH-1:0]      mapper_porta_rdata [8];
    logic [BANK_ADDR_WIDTH-1:0] mapper_portb_addr  [8];
    logic [DATA_WIDTH-1:0]      mapper_portb_rdata [8];
    
    logic [BANK_ADDR_WIDTH-1:0] mapper_r0_addr  [8];
    logic                       mapper_r0_we    [8];
    logic [DATA_WIDTH-1:0]      mapper_r0_wdata [8];
    
    logic [BANK_ADDR_WIDTH-1:0] mapper_r1_addr  [8];
    logic                       mapper_r1_we    [8];
    logic [DATA_WIDTH-1:0]      mapper_r1_wdata [8];

    logic mapper_porta_re [8];
    logic mapper_portb_re [8];

    // -------------------------------------------------------------------------
    // PORT A READ PATH (Split into Address generation and Data Multiplexing)
    // -------------------------------------------------------------------------
    // FAST domain: Only responsible for outputting bank_addr and bank_re
    addr_mapper #(.DATA_WIDTH(DATA_WIDTH), .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH)) u_mapper_porta_addr (
        .addr_mode(ppu_addr_mode_rd), .target_id(ppu_src1_id), .base_batch(ppu_rd_batch), .base_batch_rd(ppu_rd_batch), .stage(ppu_next_stage_id), .is_b_side_calc(1'b0),
        .lane_we(dummy_we), .lane_wdata(dummy_wdata), .lane_rdata(),
        .bank_addr(mapper_porta_addr), .bank_we(), .bank_re(mapper_porta_re), .bank_wdata(), .bank_rdata(dummy_rdata_zero)
    );
    
    // SLOW domain: Only responsible for multiplexing bank_rdata into lane_rdata
    addr_mapper #(.DATA_WIDTH(DATA_WIDTH), .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH)) u_mapper_porta_data (
        .addr_mode(ppu_addr_mode_rd), .target_id(ppu_src1_id), .base_batch(ppu_rd_batch_q), .base_batch_rd(ppu_rd_batch_q), .stage(ppu_next_stage_id_q), .is_b_side_calc(1'b0),
        .lane_we(dummy_we), .lane_wdata(dummy_wdata), .lane_rdata(ppu_port_a_out),
        .bank_addr(), .bank_we(), .bank_re(), .bank_wdata(), .bank_rdata(mapper_porta_rdata)
    );

    // -------------------------------------------------------------------------
    // PORT B READ PATH (Split into Address generation and Data Multiplexing)
    // -------------------------------------------------------------------------
    // FAST domain
    addr_mapper #(.DATA_WIDTH(DATA_WIDTH), .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH)) u_mapper_portb_addr (
        .addr_mode(ppu_addr_mode_rd), .target_id(ppu_src2_id), .base_batch(ppu_rd_batch), .base_batch_rd(ppu_rd_batch), .stage(ppu_next_stage_id), .is_b_side_calc(1'b1),
        .lane_we(dummy_we), .lane_wdata(dummy_wdata), .lane_rdata(),
        .bank_addr(mapper_portb_addr), .bank_we(), .bank_re(mapper_portb_re), .bank_wdata(), .bank_rdata(dummy_rdata_zero)
    );
    
    // SLOW domain
    addr_mapper #(.DATA_WIDTH(DATA_WIDTH), .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH)) u_mapper_portb_data (
        .addr_mode(ppu_addr_mode_rd), .target_id(ppu_src2_id), .base_batch(ppu_rd_batch_q), .base_batch_rd(ppu_rd_batch_q), .stage(ppu_next_stage_id_q), .is_b_side_calc(1'b1),
        .lane_we(dummy_we), .lane_wdata(dummy_wdata), .lane_rdata(ppu_port_b_out),
        .bank_addr(), .bank_we(), .bank_re(), .bank_wdata(), .bank_rdata(mapper_portb_rdata)
    );
    
    // -------------------------------------------------------------------------
    // WRITE PATHS (Unchanged)
    // -------------------------------------------------------------------------
    addr_mapper #(.DATA_WIDTH(DATA_WIDTH), .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH), .IS_WRITE_PATH(1)) u_mapper_r0 (
        .addr_mode(ppu_addr_mode_wr), .target_id(ppu_dest_id), .base_batch(ppu_wr_batch), .base_batch_rd(ppu_wr_batch), .stage(ppu_stage_id), .is_b_side_calc(1'b0),
        .lane_we(ppu_we_r0), .lane_wdata(ppu_r0_data), .lane_rdata(),
        .bank_addr(mapper_r0_addr), .bank_we(mapper_r0_we), .bank_re(), .bank_wdata(mapper_r0_wdata), .bank_rdata(dummy_rdata_zero)
    );
    
    addr_mapper #(.DATA_WIDTH(DATA_WIDTH), .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH), .IS_WRITE_PATH(1)) u_mapper_r1 (
        .addr_mode(ppu_addr_mode_wr), .target_id(ppu_dest_id), .base_batch(ppu_wr_batch), .base_batch_rd(ppu_wr_batch), .stage(ppu_stage_id), .is_b_side_calc(1'b1),
        .lane_we(ppu_we_r1), .lane_wdata(ppu_r1_data), .lane_rdata(),
        .bank_addr(mapper_r1_addr), .bank_we(mapper_r1_we), .bank_re(), .bank_wdata(mapper_r1_wdata), .bank_rdata(dummy_rdata_zero)
    );

    // =========================================================================
    // PHYSICAL ADDRESS DECODE & CROSSBAR ROUTER 
    // =========================================================================
    logic [BANK_ADDR_WIDTH-1:0] pgu_bank_addr;
    assign pgu_bank_addr = {is_upper_half(pgu_dest_id), pgu_burst_offset};

    logic [BANK_ADDR_WIDTH-1:0] dma_bank_addr;
    assign dma_bank_addr = {is_upper_half(dma_dest_id), dma_burst_offset};

    always_comb begin
        for (int i = 0; i < 8; i++) begin
            mapper_porta_rdata[i] = is_a_side(ppu_src1_id) ? sram_A_rdata[i] :
                                     is_b_side(ppu_src1_id) ? sram_B_rdata[i] : '0;
            mapper_portb_rdata[i] = is_a_side(ppu_src2_id) ? sram_A_rdata[i] :
                                     is_b_side(ppu_src2_id) ? sram_B_rdata[i] : '0;
            dma_burst_rdata[i]    = is_a_side(dma_src_id)  ? sram_A_rdata[i] :
                                     is_b_side(dma_src_id)  ? sram_B_rdata[i] : '0;
        end

        for (int i = 0; i < 8; i++) begin
            sram_A_we[i]      = 1'b0; 
            sram_A_wdata[i]   = '0; 
            sram_A_wr_addr[i] = '0;
            sram_A_rd_addr[i] = '0;
            sram_B_we[i]      = 1'b0; 
            sram_B_wdata[i]   = '0; 
            sram_B_wr_addr[i] = '0;
            sram_B_rd_addr[i] = '0;

            if (ppu_dest_id == BUF_A0 || ppu_dest_id == BUF_A1) begin
                sram_A_we[i]      = mapper_r0_we[i] | mapper_r1_we[i];
                sram_A_wdata[i]   = mapper_r0_we[i] ? mapper_r0_wdata[i] : mapper_r1_wdata[i];
                sram_A_wr_addr[i] = mapper_r0_we[i] ? mapper_r0_addr[i]  : mapper_r1_addr[i];
            end else if (pgu_burst_valid && is_a_side(pgu_dest_id) && pgu_burst_we[i]) begin
                sram_A_we[i]      = 1'b1;
                sram_A_wdata[i]   = pgu_burst_wdata[i];
                sram_A_wr_addr[i] = pgu_bank_addr;
            end else if (dma_burst_valid && is_a_side(dma_dest_id) && dma_burst_we[i]) begin
                sram_A_we[i]      = 1'b1;
                sram_A_wdata[i]   = dma_burst_wdata[i];
                sram_A_wr_addr[i] = dma_bank_addr;
            end

            if ((ppu_src1_id == BUF_A0 || ppu_src1_id == BUF_A1) && mapper_porta_re[i])
                sram_A_rd_addr[i] = mapper_porta_addr[i];
            else if ((ppu_src2_id == BUF_A0 || ppu_src2_id == BUF_A1) && mapper_portb_re[i])
                sram_A_rd_addr[i] = mapper_portb_addr[i];
            else if (is_a_side(dma_src_id) && dma_read_req)
                sram_A_rd_addr[i] = {is_upper_half(dma_src_id), dma_burst_offset};

            if (ppu_dest_id == BUF_B0 || ppu_dest_id == BUF_B1) begin
                sram_B_we[i]      = mapper_r0_we[i] | mapper_r1_we[i];
                sram_B_wdata[i]   = mapper_r0_we[i] ? mapper_r0_wdata[i] : mapper_r1_wdata[i];
                sram_B_wr_addr[i] = mapper_r0_we[i] ? mapper_r0_addr[i]  : mapper_r1_addr[i];
            end else if (pgu_burst_valid && is_b_side(pgu_dest_id) && pgu_burst_we[i]) begin
                sram_B_we[i]      = 1'b1;
                sram_B_wdata[i]   = pgu_burst_wdata[i];
                sram_B_wr_addr[i] = pgu_bank_addr;
            end else if (dma_burst_valid && is_b_side(dma_dest_id) && dma_burst_we[i]) begin
                sram_B_we[i]      = 1'b1;
                sram_B_wdata[i]   = dma_burst_wdata[i];
                sram_B_wr_addr[i] = dma_bank_addr;
            end

            if ((ppu_src1_id == BUF_B0 || ppu_src1_id == BUF_B1) && mapper_porta_re[i])
                sram_B_rd_addr[i] = mapper_porta_addr[i];
            else if ((ppu_src2_id == BUF_B0 || ppu_src2_id == BUF_B1) && mapper_portb_re[i])
                sram_B_rd_addr[i] = mapper_portb_addr[i];
            else if (is_b_side(dma_src_id) && dma_read_req)
                sram_B_rd_addr[i] = {is_upper_half(dma_src_id), dma_burst_offset};
        end
    end
endmodule