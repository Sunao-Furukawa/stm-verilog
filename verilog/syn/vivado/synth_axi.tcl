# =====================================================================
#  synth_axi.tcl - Vivado synthesis script for the STM CPU with an AXI4
#  master interface (stm_axi_top = stm_cntl + stm_regfile + stm_axi_master).
#  Tested with Vivado 2022.2.
#
#  Usage (from this directory):
#      vivado -mode batch -source synth_axi.tcl
#  Another part can be given as an argument:
#      vivado -mode batch -source synth_axi.tcl -tclargs xc7a35tcpg236-1
#
#  Synthesized out of context, because the AXI4 port is meant to connect to
#  an interconnect inside the FPGA. Reports are written to ./reports_axi and
#  the checkpoint to ./stm_axi_top_synth.dcp.
# =====================================================================
set part xc7a100tcsg324-1
if {[llength $argv] > 0} { set part [lindex $argv 0] }

set here [file dirname [file normalize [info script]]]
set rtl  [file normalize [file join $here .. .. rtl]]
cd $here

read_verilog [list [file join $rtl stm_axi_top.v] [file join $rtl stm_axi_master.v]                    [file join $rtl stm_cntl.v] [file join $rtl stm_exu.v]                    [file join $rtl stm_regfile.v]]
read_xdc -mode out_of_context [file join $here stm_axi_top.xdc]

synth_design -top stm_axi_top -part $part -mode out_of_context              -include_dirs [list $rtl]

file mkdir reports_axi
report_utilization    -file reports_axi/utilization.rpt
report_timing_summary -file reports_axi/timing_summary.rpt
write_checkpoint -force stm_axi_top_synth.dcp

puts "Synthesis finished for part $part. See [file join $here reports_axi]."
