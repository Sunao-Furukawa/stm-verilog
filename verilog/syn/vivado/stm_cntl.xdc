# =====================================================================
#  stm_cntl.xdc - timing constraints for the STM CPU core (out of context)
#  Target clock: 25 MHz (40 ns).
# =====================================================================
create_clock -name clk -period 40.000 [get_ports clk]

# stm_cntl is synthesized alone; its I/O connect to the register file and
# memory outside. Budget half a cycle for that external logic.
set_input_delay  -clock clk 20.000 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk 20.000 [get_ports -filter {DIRECTION == OUT}]

# IB_AD_NXT (next-cycle fetch address, used only with EXT_BUS=1) goes straight
# to the address register of the instruction-cache RAM, and it is combinational
# from the fetch handshake inputs (RANDOM_FOR_IFCLH / IFRDY). Half a cycle at
# both ends would leave no time for that path, so budget only 5 ns after it.
set_output_delay -clock clk  5.000 [get_ports {IB_AD_NXT[*]}]
