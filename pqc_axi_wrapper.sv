import ppu_pkg::*;
import agu_pkg::*;

module pqc_axi_wrapper (
    // Global signals
    input  logic        clk,
    input  logic        rst_n,

    // ==========================================
    // AXI4-Lite Slave Interface
    // ==========================================
    // 1. Write Address Channel (AW)
    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    // 2. Write Data Channel (W)
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb, // Byte enables
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    // 3. Write Response Channel (B)
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // 4. Read Address Channel (AR)
    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // 5. Read Data Channel (R)
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready
);
 
 // Internal Registers for Write Data
    logic [31:0] slv_ppu_ctrl;
    logic [31:0] slv_dma_ctrl;
    logic [31:0] slv_psu_ctrl;

    // AXI Write Handshake Logic
    logic aw_en;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00; // OKAY response
            aw_en         <= 1'b1;
            
            slv_ppu_ctrl  <= '0;
            slv_dma_ctrl  <= '0;
            slv_psu_ctrl  <= '0;
        end else begin
            // -----------------------------------------------------------
            // PUT THE DEFAULTS HERE! (Right at the start of the else block)
            // -----------------------------------------------------------
            // Every clock cycle, default the start bits back to 0.
            slv_ppu_ctrl[0] <= 1'b0;
            slv_dma_ctrl[0] <= 1'b0;
            slv_psu_ctrl[0] <= 1'b0;
            // -----------------------------------------------------------


            // Accept Write Address
            if (~s_axi_awready && s_axi_awvalid && s_axi_wvalid && aw_en) begin
                s_axi_awready <= 1'b1;
                aw_en         <= 1'b0;
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_awready <= 1'b0;
                aw_en         <= 1'b1;
            end else begin
                s_axi_awready <= 1'b0;
            end

            // Accept Write Data
            if (~s_axi_wready && s_axi_wvalid && s_axi_awvalid && aw_en) begin
                s_axi_wready <= 1'b1;
            end else begin
                s_axi_wready <= 1'b0;
            end

            // Perform the actual register write
            // IF this triggers, it overrides the defaults we set at the top!
            if (s_axi_wready && s_axi_wvalid && s_axi_awready && s_axi_awvalid) begin
                case (s_axi_awaddr[4:2])
                    3'b000: slv_ppu_ctrl <= s_axi_wdata; // Offset 0x00
                    3'b010: slv_dma_ctrl <= s_axi_wdata; // Offset 0x08
                    3'b100: slv_psu_ctrl <= s_axi_wdata; // Offset 0x10
                    default: ; 
                endcase
            end

            // Send Write Response
            if (s_axi_awready && s_axi_awvalid && s_axi_wready && s_axi_wvalid && ~s_axi_bvalid) begin
                s_axi_bvalid <= 1'b1;
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    
// Wires linking from your module's outputs
    logic ppu_busy, ppu_done;
    logic dma_busy, dma_done;
    logic psu_busy;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= '0;
        end else begin
            // Accept Read Address
            if (~s_axi_arready && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
            end else begin
                s_axi_arready <= 1'b0;
            end

            // Provide Read Data
            if (s_axi_arready && s_axi_arvalid && ~s_axi_rvalid) begin
                s_axi_rvalid <= 1'b1;
                
                // Address Decoding for Reads
                case (s_axi_araddr[4:2])
                    3'b000: s_axi_rdata <= slv_ppu_ctrl;
                    3'b001: s_axi_rdata <= {30'b0, ppu_done, ppu_busy}; // Offset 0x04 (PPU_STAT)
                    3'b010: s_axi_rdata <= slv_dma_ctrl;
                    3'b011: s_axi_rdata <= {30'b0, dma_done, dma_busy}; // Offset 0x0C (DMA_STAT)
                    3'b100: s_axi_rdata <= slv_psu_ctrl;
                    3'b101: s_axi_rdata <= {31'b0, psu_busy};           // Offset 0x14 (PSU_STAT)
                    default: s_axi_rdata <= 32'h00000000;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end


    // ==========================================
    // Instantiate the PQC Core
    // ==========================================
    pqc_top #(
        .DATA_WIDTH(32),
        .BANK_ADDR_WIDTH(6),
        .ROM_ROWS(128)
    ) u_pqc_top (
        .clk   (clk),
        .rst_n (rst_n),

        // PPU Control (Mapped from slv_ppu_ctrl)
        .csr_ppu_start        (slv_ppu_ctrl[0]),
        .csr_ppu_algo_mode    (slv_ppu_ctrl[3:1]),
        .csr_ppu_math_mode    (slv_ppu_ctrl[7:4]),
        .csr_ppu_src1         (slv_ppu_ctrl[10:8]),
        .csr_ppu_src2         (slv_ppu_ctrl[13:11]),
        .csr_ppu_dest         (slv_ppu_ctrl[16:14]),
        .csr_ppu_ntt_inverse  (slv_ppu_ctrl[17]),
        // Casting raw bits to your custom Enum types
        .csr_ppu_addr_mode_rd (addr_mode_e'(slv_ppu_ctrl[19:18])),
        .csr_ppu_addr_mode_wr (addr_mode_e'(slv_ppu_ctrl[21:20])),

        // PPU Status outputs
        .csr_ppu_busy         (ppu_busy),
        .csr_ppu_done         (ppu_done),

        // DMA Control (Mapped from slv_dma_ctrl)
        .csr_dma_start        (slv_dma_ctrl[0]),
        .csr_dma_direction    (slv_dma_ctrl[1]),
        .csr_dma_buffer_row   (slv_dma_ctrl[6:2]),
        .csr_dma_buffer_id    (slv_dma_ctrl[9:7]),
        .csr_dma_length       (slv_dma_ctrl[18:10]),
        
        // DMA Status outputs
        .csr_dma_busy         (dma_busy),
        .csr_dma_done         (dma_done),

        // PSU Control (Mapped from slv_psu_ctrl)
        .csr_psu_start        (slv_psu_ctrl[0]),
        .csr_psu_mode         (slv_psu_ctrl[4:1]),
        
        // PSU Status outputs
        .csr_psu_busy         (psu_busy)
    );

endmodule