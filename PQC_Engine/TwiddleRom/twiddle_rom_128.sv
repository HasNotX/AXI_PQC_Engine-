module twiddle_rom_128 #(
    parameter ROWS       = 128,
    parameter ADDR_WIDTH = $clog2(ROWS)
)(
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic [127:0]          data_o
);
logic [127:0] rom [ROWS];

    initial begin
        $readmemh("twiddles.mem", rom);
    end

    assign data_o = rom[addr];

endmodule