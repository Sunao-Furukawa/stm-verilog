# =====================================================================
#  arty_a7_35.xdc - pin constraints for the block design of create_bd.tcl
#  on the Digilent Arty A7-35 (xc7a35ticsg324-1L). The Arty A7-100
#  (xc7a100tcsg324-1) has the same pins.
#
#  Pins are taken from Digilent's Arty-A7-35-Master.xdc (Rev. D / Rev. E):
#
#    port        board signal   pin   direction
#    sys_clk     CLK100MHZ      E3    in   100 MHz oscillator
#    reset_n     ck_rst         C2    in   RESET button (low when pressed)
#    uart_rxd    uart_txd_in    A9    in   from the USB-UART (PC -> FPGA)
#    uart_txd    uart_rxd_out   D10   out  to the USB-UART   (FPGA -> PC)
#    bus_error   led[0] (LD4)   H5    out  lights on an AXI error response
#
#  Usage:
#    vivado -mode batch -source create_bd.tcl \
#           -tclargs xc7a35ticsg324-1L ../../work/hello_uart.hex arty_a7_35.xdc
#
#  The 100 MHz clock is not created here: the Clocking Wizard in the block
#  design already constrains its input (clk_in1 = sys_clk, 10 ns).
# =====================================================================

set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports sys_clk]
set_property -dict { PACKAGE_PIN C2  IOSTANDARD LVCMOS33 } [get_ports reset_n]
set_property -dict { PACKAGE_PIN A9  IOSTANDARD LVCMOS33 } [get_ports uart_rxd]
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports uart_txd]
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports bus_error]

# The reset button, the UART and the LED are asynchronous to the CPU clock
# (reset_n is synchronised by the Processor System Reset, uart_rxd by the
# UART Lite), so they are not timed.
set_false_path -from [get_ports {reset_n uart_rxd}]
set_false_path -to   [get_ports {uart_txd bus_error}]

# Configuration bank voltage (bank 0 is 3.3 V on the Arty A7)
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
