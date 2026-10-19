# =====================================================================
#  stm_axi_top.xdc - timing constraints for the STM CPU with AXI4 master
#  (out of context). Target clock: 25 MHz (40 ns).
# =====================================================================
create_clock -name aclk -period 40.000 [get_ports aclk]

# The AXI4 port connects to an interconnect / slave on the same chip.
# Budget half a cycle for that external logic.
set_input_delay  -clock aclk 20.000 [get_ports -filter {DIRECTION == IN && NAME != aclk}]
set_output_delay -clock aclk 20.000 [get_ports -filter {DIRECTION == OUT}]
