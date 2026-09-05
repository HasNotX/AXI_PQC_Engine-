module tcm_mem #(
    parameter DATA_WIDTH = 32,
    parameter NUM_POLYS  = 16,
    parameter POLY_WORDS = 256,
    parameter DEPTH      = NUM_POLYS * POLY_WORDS,   // 4096
    parameter ADDR_WIDTH = $clog2(DEPTH)             // 12
)(
    input  logic                  clk,
    // Single port. These signals must stay entirely inside the engine --
    // only dma_adapter should ever drive/read this module. Do not route
    // tcm_* signals to any top-level or external-bus port.
    input  logic                  we,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic [DATA_WIDTH-1:0] rdata
);

    logic [DATA_WIDTH-1:0] mem [DEPTH];

    always_ff @(posedge clk) begin
        if (we)
            mem[addr] <= wdata;
        rdata <= mem[addr]; // registered read, 1-cycle latency assumed
    end

endmodule