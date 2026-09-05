module sram_subbank #(
    parameter DATA_WIDTH      = 32,
    parameter BANK_ADDR_WIDTH = 6,  // 64 words deep
    parameter DEPTH           = (1 << BANK_ADDR_WIDTH)
)(
    input  logic                       clk,
    
    // Dedicated Write Port
    input  logic                       we_i,
    input  logic [BANK_ADDR_WIDTH-1:0] wr_addr_i,
    input  logic [DATA_WIDTH-1:0]      wdata_i,
    
    // Dedicated Read Port
    input  logic [BANK_ADDR_WIDTH-1:0] rd_addr_i,
    (* DONT_TOUCH = "TRUE" *) output logic [DATA_WIDTH-1:0]      rdata_o
);

    // Tell Vivado to infer this as Simple Dual-Port memory
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Write Process
    always_ff @(posedge clk) begin
        if (we_i) begin
            mem[wr_addr_i] <= wdata_i;
        end
    end
    
    // Read Process (Synchronous, 1-cycle latency)
    always_ff @(posedge clk) begin
        rdata_o <= mem[rd_addr_i];
    end

endmodule