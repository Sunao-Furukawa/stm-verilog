# =====================================================================
#  stm_axi_top.sdc - timing constraints for the STM CPU with AXI4 master
#  Target clock: 25 MHz (40 ns), the same as stm_cntl.sdc.
# =====================================================================
create_clock -name aclk -period 40.000 [get_ports aclk]
derive_clock_uncertainty

# The AXI4 port connects to an interconnect / slave on the same chip.
# Budget half a cycle for that external logic.
set_input_delay  -clock aclk 20.000 [remove_from_collection [all_inputs] [get_ports aclk]]
set_output_delay -clock aclk 20.000 [all_outputs]
