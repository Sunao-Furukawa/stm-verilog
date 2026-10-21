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
#    sw_tri_i[0] sw[0]  (SW0)   A8    in   slide switches (AXI GPIO, 0xF001_0000)
#    sw_tri_i[1] sw[1]  (SW1)   C11   in
#    sw_tri_i[2] sw[2]  (SW2)   C10   in
#    sw_tri_i[3] sw[3]  (SW3)   A10   in
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
set_property -dict { PACKAGE_PIN A8  IOSTANDARD LVCMOS33 } [get_ports {sw_tri_i[0]}]
set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports {sw_tri_i[1]}]
set_property -dict { PACKAGE_PIN C10 IOSTANDARD LVCMOS33 } [get_ports {sw_tri_i[2]}]
set_property -dict { PACKAGE_PIN A10 IOSTANDARD LVCMOS33 } [get_ports {sw_tri_i[3]}]

# The reset button, the UART, the switches and the LED are asynchronous to
# the CPU clock (reset_n is synchronised by the Processor System Reset,
# uart_rxd by the UART Lite, sw_tri_i by the GPIO), so they are not timed.
set_false_path -from [get_ports {reset_n uart_rxd sw_tri_i[*]}]
set_false_path -to   [get_ports {uart_txd bus_error}]

# Configuration bank voltage (bank 0 is 3.3 V on the Arty A7)
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
