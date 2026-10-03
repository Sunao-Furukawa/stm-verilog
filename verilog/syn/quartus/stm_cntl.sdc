# =====================================================================
#  stm_cntl.sdc - timing constraints for the STM CPU core
#  Target clock: 25 MHz (40 ns), met with margin by Quartus II 13.0sp1 on
#  EP4CE115F29C7. With a 50 MHz constraint the fitter reached Fmax = 38.6 MHz
#  (slow 85C model); the reported Fmax depends on the constraint because the
#  fitter stops optimizing once timing is met. See the TimeQuest report.
# =====================================================================
create_clock -name clk -period 40.000 [get_ports clk]
derive_clock_uncertainty

# stm_cntl is synthesized alone; its I/O connect to the register file and
# memory outside. Budget half a cycle for that external logic.
set_input_delay  -clock clk 20.000 [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay -clock clk 20.000 [all_outputs]
