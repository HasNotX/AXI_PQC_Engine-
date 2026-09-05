`timescale 1ns/1ps
import agu_pkg::*;
import ppu_pkg::*;

module tb_axi_wrapper;
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    // AXI4-Lite signals
    logic [31:0] s_axi_awaddr;
    logic        s_axi_awvalid;
    logic        s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic [3:0]  s_axi_wstrb;
    logic        s_axi_wvalid;
    logic        s_axi_wready;
    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;
    logic [31:0] s_axi_araddr;
    logic        s_axi_arvalid;
    logic        s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [1:0]  s_axi_rresp;
    logic        s_axi_rvalid;
    logic        s_axi_rready;

    pqc_axi_wrapper u_wrapper (
        .clk(clk),
        .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready)
    );

    wire [3:0] math_mode_val = u_wrapper.u_pqc_top.csr_ppu_math_mode;
    wire [5:0] ppu_wr_batch = u_wrapper.u_pqc_top.u_delay_line.delayed_batch_out;
    wire [2:0] ppu_wr_stage = u_wrapper.u_pqc_top.u_delay_line.delayed_stage_out;
    wire [5:0] current_batch_out = u_wrapper.u_pqc_top.u_ppu.current_batch_out;
    wire [2:0] current_stage_raw = u_wrapper.u_pqc_top.u_ppu.current_stage_out;
    wire we_r0 [4] = u_wrapper.u_pqc_top.u_ppu.we_r0;
    wire we_r1 [4] = u_wrapper.u_pqc_top.u_ppu.we_r1;
    wire [31:0] r0_data [4] = u_wrapper.u_pqc_top.u_ppu.r0_out;
    wire [31:0] r1_data [4] = u_wrapper.u_pqc_top.u_ppu.r1_out;
    wire [31:0] port_a [4] = u_wrapper.u_pqc_top.u_ppu.port_a_in;
    wire [31:0] port_b [4] = u_wrapper.u_pqc_top.u_ppu.port_b_in;

    always_ff @(posedge clk) begin
        if (u_wrapper.u_pqc_top.u_ppu.gen_ppu_lanes[0].u_butterfly.u_fsm.current_state == 2) begin
            for (int l = 0; l < 4; l++) begin
                $display("[%0d] AGU_FETCH: stage=%0d rd_batch=%0d lane=%0d fetched_a=%0d fetched_b=%0d", math_mode_val, 
                         current_stage_raw, current_batch_out, l, port_a[l], port_b[l]);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (we_r0[0]) begin 
            for (int l = 0; l < 4; l++) begin
                $display("[%0d] PPU_WRITE: stage=%0d wr_batch=%0d lane=%0d r0=%0d r1=%0d", math_mode_val, 
                         ppu_wr_stage, ppu_wr_batch, l, r0_data[l], r1_data[l]);
            end
        end
    end

    // AXI tasks
    task axi_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wvalid  <= 1'b1;
            s_axi_wstrb   <= 4'hf;
            s_axi_bready  <= 1'b1;
            
            fork
                begin
                    wait(s_axi_awready == 1'b1);
                    @(posedge clk);
                    s_axi_awvalid <= 1'b0;
                end
                begin
                    wait(s_axi_wready == 1'b1);
                    @(posedge clk);
                    s_axi_wvalid <= 1'b0;
                end
            join
            
            wait(s_axi_bvalid == 1'b1);
            @(posedge clk);
            s_axi_bready <= 1'b0;
        end
    endtask

    task axi_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b1;
            
            wait(s_axi_arready == 1'b1);
            @(posedge clk);
            s_axi_arvalid <= 1'b0;
            
            wait(s_axi_rvalid == 1'b1);
            data = s_axi_rdata;
            @(posedge clk);
            s_axi_rready <= 1'b0;
        end
    endtask

    logic [31:0] read_data;

    initial begin
        $dumpfile("dump_axi.vcd");
        $dumpvars(0, tb_axi_wrapper);
        rst_n = 0;
        
        s_axi_awaddr = 0;
        s_axi_awvalid = 0;
        s_axi_wdata = 0;
        s_axi_wstrb = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_araddr = 0;
        s_axi_arvalid = 0;
        s_axi_rready = 0;

        // Add a timeout to prevent infinite hangs
        fork
            begin
                #1000000;
                $display("SIMULATION TIMEOUT! Testbench hung.");
                $finish;
            end
        join_none

        // Assert reset
        rst_n = 0;
        
        // Deassert reset safely away from posedge clk
        #22;
        rst_n = 1;
        #20;
        
        $display("=== STARTING AXI TESTBENCH ===");
        
        $readmemh("sram_init_0.hex", u_wrapper.u_pqc_top.gen_sram_A[0].u_sram_A.mem);
        $readmemh("sram_init_1.hex", u_wrapper.u_pqc_top.gen_sram_A[1].u_sram_A.mem);
        $readmemh("sram_init_2.hex", u_wrapper.u_pqc_top.gen_sram_A[2].u_sram_A.mem);
        $readmemh("sram_init_3.hex", u_wrapper.u_pqc_top.gen_sram_A[3].u_sram_A.mem);
        $readmemh("sram_init_4.hex", u_wrapper.u_pqc_top.gen_sram_A[4].u_sram_A.mem);
        $readmemh("sram_init_5.hex", u_wrapper.u_pqc_top.gen_sram_A[5].u_sram_A.mem);
        $readmemh("sram_init_6.hex", u_wrapper.u_pqc_top.gen_sram_A[6].u_sram_A.mem);
        $readmemh("sram_init_7.hex", u_wrapper.u_pqc_top.gen_sram_A[7].u_sram_A.mem);

        $display("\n--- RUNNING FWD NTT (BUF_A0) VIA AXI ---");
        axi_write(32'h00000000, 32'h00240001);

        read_data = 0;
        // Wait until busy bit (bit 0) goes high
        while ((read_data & 32'h1) == 0) begin
            axi_read(32'h00000004, read_data);
        end
        $display("NTT IS RUNNING. busy bit is set.");

        // Wait until busy bit (bit 0) goes low
        while ((read_data & 32'h1) != 0) begin
            axi_read(32'h00000004, read_data);
        end
        $display("NTT DONE. busy bit cleared.");
        #10;
        
        $writememh("sram_out_fwd_0.hex", u_wrapper.u_pqc_top.gen_sram_A[0].u_sram_A.mem);
        $writememh("sram_out_fwd_1.hex", u_wrapper.u_pqc_top.gen_sram_A[1].u_sram_A.mem);
        $writememh("sram_out_fwd_2.hex", u_wrapper.u_pqc_top.gen_sram_A[2].u_sram_A.mem);
        $writememh("sram_out_fwd_3.hex", u_wrapper.u_pqc_top.gen_sram_A[3].u_sram_A.mem);
        $writememh("sram_out_fwd_4.hex", u_wrapper.u_pqc_top.gen_sram_A[4].u_sram_A.mem);
        $writememh("sram_out_fwd_5.hex", u_wrapper.u_pqc_top.gen_sram_A[5].u_sram_A.mem);
        $writememh("sram_out_fwd_6.hex", u_wrapper.u_pqc_top.gen_sram_A[6].u_sram_A.mem);
        $writememh("sram_out_fwd_7.hex", u_wrapper.u_pqc_top.gen_sram_A[7].u_sram_A.mem);

        $finish;
    end
endmodule
