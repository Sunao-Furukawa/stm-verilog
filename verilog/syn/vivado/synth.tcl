# =====================================================================
#  synth.tcl - Vivado synthesis script for the STM CPU core
#  Tested with Vivado 2022.2.
#
#  Usage (from this directory):
#      vivado -mode batch -source synth.tcl
#  Another part can be given as an argument:
#      vivado -mode batch -source synth.tcl -tclargs xc7a35tcpg236-1
#
#  Only the CPU core (stm_cntl) is synthesized, in out-of-context mode
#  (no I/O buffers are inserted), because stm_cntl has 480 ports that
#  connect to the register file and memory. Reports are written to
#  ./reports and the checkpoint to ./stm_cntl_synth.dcp.
# =====================================================================
set part xc7a100tcsg324-1
if {[llength $argv] > 0} { set part [lindex $argv 0] }

set here [file dirname [file normalize [info script]]]
set rtl  [file normalize [file join $here .. .. rtl]]
cd $here

read_verilog [list [file join $rtl stm_cntl.v] [file join $rtl stm_exu.v]]
read_xdc -mode out_of_context [file join $here stm_cntl.xdc]

synth_design -top stm_cntl -part $part -mode out_of_context \
             -include_dirs [list $rtl]

file mkdir reports
report_utilization    -file reports/utilization.rpt
report_timing_summary -file reports/timing_summary.rpt
write_checkpoint -force stm_cntl_synth.dcp

puts "Synthesis finished for part $part. See [file join $here reports]."
