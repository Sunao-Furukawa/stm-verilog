# =====================================================================
#  stm_cntl.xdc - timing constraints for the STM CPU core (out of context)
#  Target clock: 25 MHz (40 ns).
# =====================================================================
create_clock -name clk -period 40.000 [get_ports clk]

# stm_cntl is synthesized alone; its I/O connect to the register file and
# memory outside. Budget half a cycle for that external logic.
set_input_delay  -clock clk 20.000 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk 20.000 [get_ports -filter {DIRECTION == OUT}]
