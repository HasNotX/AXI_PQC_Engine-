create_project -force pqc_synth ./synth_project -part xczu7ev-ffvc1156-2-e

# Packages first
read_verilog -sv ./PQC_Engine/AGU/agu_pkg.sv
read_verilog -sv ./PQC_Engine/PPU/ppu_pkg.sv

# Add modules
read_verilog -sv [glob ./PQC_Engine/AGU/*.sv]
read_verilog -sv [glob ./PQC_Engine/PPU/*.sv]
read_verilog -sv [glob ./PQC_Engine/TwiddleRom/*.sv]
read_verilog -sv ./PQC_Engine/MCU/mcu.sv
read_verilog -sv ./PQC_Engine/Buffers/sram_subbank.sv
read_verilog -sv ./PQC_Engine/pqc_top.sv
read_verilog -sv ./pqc_axi_wrapper.sv

# Ignore testbenches
set tbs [get_files -quiet "*tb*.sv"]
if {[llength $tbs] > 0} {
    set_property used_in_synthesis false $tbs
}

# Ignore unneeded stuff like tb_dump, etc.
set_property used_in_synthesis false [get_files -quiet "*tb_dump.sv"]
set_property used_in_synthesis false [get_files -quiet "*tb_ppu_top_patched.sv"]

# Create timing constraints
set out [open "synth.xdc" w]
puts $out "create_clock -period 3.33 -name clk \[get_ports clk\]"
close $out
read_xdc synth.xdc

synth_design -top pqc_axi_wrapper -part xczu7ev-ffvc1156-2-e -retiming

report_utilization -file util.rpt
report_timing_summary -file timing.rpt
exit
