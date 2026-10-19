# =====================================================================
#  create_bd.tcl - build a Vivado project with an IP Integrator block
#  design around the STM CPU with AXI4 master (stm_axi_top).
#  Tested with Vivado 2022.2.
#
#  Usage (from this directory):
#      vivado -mode batch -source create_bd.tcl
#      vivado -mode batch -source create_bd.tcl -tclargs <part> <program.hex>
#  or in the Vivado Tcl console:
#      cd <this directory>; set argv {xc7a100tcsg324-1 ../../work/hello.hex}; source create_bd.tcl
#
#    <part>         FPGA part (default xc7a100tcsg324-1)
#    <program.hex>  initial contents of the program memory, as written by
#                   tools/mem2hex.py. Read with $readmemh at synthesis.
#                   Without it the memory starts as all zeros.
#
#  Block design "stm_system":
#
#    sys_clk (100 MHz) -> Clocking Wizard (25 MHz) -> aclk of everything
#    reset_n (low)     -> Clocking Wizard, Processor System Reset -> aresetn
#    Constant 0x300    -> cpu/RESET_PC
#    cpu (stm_axi_top, module reference) --m_axi--> AXI SmartConnect
#        M00 -> AXI BRAM Controller + stm_prog_ram  0x0000_0000 - 0x0000_1FFF
#        M01 -> AXI UART Lite (115200 baud)         0xF000_0000 - 0xF000_FFFF
#    bus_error, uart (rxd / txd) -> top-level ports
#
#  The program memory is stm_prog_ram.v (a module reference) rather than the
#  Block Memory Generator, because the Block Memory Generator does not take
#  an init file when it is driven by an AXI BRAM Controller in a block design.
#
#  The UART is placed in the CPU's I/O region (0xF000_0000-), where loads are
#  not speculative, so reading its RX FIFO is safe. Registers: +0x0 RX FIFO,
#  +0x4 TX FIFO, +0x8 status (bit 3 = TX FIFO full), +0xC control.
#  Write whole words to it (the I/O region does not merge sub-word stores).
#
#  The project is created in ./stm_bd with the HDL wrapper stm_system_wrapper
#  as top. Pin constraints for sys_clk, reset_n, uart_rxd, uart_txd and
#  bus_error depend on the board and must be added before implementation.
#
#  Note: run from a path without non-ASCII characters (see ../README.md).
# =====================================================================
set part    xc7a100tcsg324-1
set hexfile ""
if {[llength $argv] > 0} { set part    [lindex $argv 0] }
if {[llength $argv] > 1} { set hexfile [file normalize [lindex $argv 1]] }

set here     [file dirname [file normalize [info script]]]
set rtl      [file normalize [file join $here .. .. rtl]]
set proj_dir [file join $here stm_bd]

if {$hexfile ne "" && ![file exists $hexfile]} { error "$hexfile not found" }

# ---------------------------------------------------------------------
#  Project and sources
# ---------------------------------------------------------------------
create_project -force stm_bd $proj_dir -part $part

add_files -norecurse [list \
  [file join $rtl stm_axi_top.v]    [file join $rtl stm_icache.v] \
  [file join $rtl stm_axi_master.v] [file join $rtl stm_cntl.v] \
  [file join $rtl stm_exu.v]        [file join $rtl stm_regfile.v] \
  [file join $here stm_prog_ram.v]]

# stm_cntl.v includes "stm_const.vh", "ch/010_d_pre.vh", ... relative to rtl/.
# A module reference needs all include files to be part of the project too.
set vh_ch [glob [file join $rtl ch *.vh]]
set vh    [concat [glob [file join $rtl *.vh]] $vh_ch]
add_files -norecurse $vh
set_property file_type {Verilog Header} [get_files $vh]
# rtl/ch/*.vh are pieces of the body of module stm_cntl. Keep Vivado from
# parsing them on their own (it would report syntax errors); they are still
# read through `include.
set_property used_in {} [get_files $vh_ch]
set_property include_dirs [list $rtl] [current_fileset]
update_compile_order -fileset sources_1

# ---------------------------------------------------------------------
#  Block design
# ---------------------------------------------------------------------
create_bd_design stm_system

# Top-level ports
set sys_clk [create_bd_port -dir I -type clk -freq_hz 100000000 sys_clk]
set reset_n [create_bd_port -dir I -type rst reset_n]
set_property CONFIG.POLARITY ACTIVE_LOW $reset_n

# Clock: 100 MHz in -> 25 MHz (the frequency the CPU was checked at)
set clk_wiz [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz]
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ {100.000} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
  CONFIG.RESET_TYPE {ACTIVE_LOW} \
  CONFIG.RESET_PORT {resetn}] $clk_wiz

# Reset synchronised to the 25 MHz clock (the polarity of ext_reset_in is
# taken from the reset_n port)
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst

# CPU (module reference to the RTL)
create_bd_cell -type module -reference stm_axi_top cpu

# Start address 0x300
set reset_pc [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 reset_pc]
set_property -dict [list CONFIG.CONST_WIDTH {32} CONFIG.CONST_VAL {768}] $reset_pc

# Interconnect: 1 master -> 2 slaves
set sc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $sc

# Program memory: 8KB (2^11 words)
set bram_ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 bram_ctrl]
set_property -dict [list CONFIG.SINGLE_PORT_BRAM {1} CONFIG.DATA_WIDTH {32} \
                         CONFIG.PROTOCOL {AXI4}] $bram_ctrl
set ram [create_bd_cell -type module -reference stm_prog_ram ram]
set_property CONFIG.AW {11} $ram
if {$hexfile ne ""} { set_property CONFIG.INIT_FILE $hexfile $ram }

# UART
set uart [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite:2.0 uart]
set_property CONFIG.C_BAUDRATE {115200} $uart

# ---- Connections
connect_bd_net $sys_clk [get_bd_pins clk_wiz/clk_in1]
connect_bd_net $reset_n [get_bd_pins clk_wiz/resetn] [get_bd_pins rst/ext_reset_in]
connect_bd_net [get_bd_pins clk_wiz/locked] [get_bd_pins rst/dcm_locked]

connect_bd_net [get_bd_pins clk_wiz/clk_out1] \
  [get_bd_pins rst/slowest_sync_clk] [get_bd_pins cpu/aclk] \
  [get_bd_pins smartconnect/aclk] [get_bd_pins bram_ctrl/s_axi_aclk] \
  [get_bd_pins uart/s_axi_aclk]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] \
  [get_bd_pins cpu/aresetn] [get_bd_pins smartconnect/aresetn] \
  [get_bd_pins bram_ctrl/s_axi_aresetn] [get_bd_pins uart/s_axi_aresetn]

connect_bd_net [get_bd_pins reset_pc/dout] [get_bd_pins cpu/RESET_PC]

connect_bd_intf_net [get_bd_intf_pins cpu/m_axi] [get_bd_intf_pins smartconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect/M00_AXI] [get_bd_intf_pins bram_ctrl/S_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect/M01_AXI] [get_bd_intf_pins uart/S_AXI]
connect_bd_intf_net [get_bd_intf_pins bram_ctrl/BRAM_PORTA] [get_bd_intf_pins ram/BRAM_PORTA]

make_bd_intf_pins_external [get_bd_intf_pins uart/UART]
set_property name uart [get_bd_intf_ports UART_0]
make_bd_pins_external [get_bd_pins cpu/bus_error]
set_property name bus_error [get_bd_ports bus_error_0]

# ---- Address map (seen from the CPU)
assign_bd_address -target_address_space [get_bd_addr_spaces cpu/m_axi] \
  -offset 0x00000000 -range 8K [get_bd_addr_segs bram_ctrl/S_AXI/Mem0]
assign_bd_address -target_address_space [get_bd_addr_spaces cpu/m_axi] \
  -offset 0xF0000000 -range 64K [get_bd_addr_segs uart/S_AXI/Reg]

regenerate_bd_layout
validate_bd_design
save_bd_design

# ---------------------------------------------------------------------
#  HDL wrapper as the top
# ---------------------------------------------------------------------
set bd_file [get_files stm_system.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper
set_property top stm_system_wrapper [current_fileset]
update_compile_order -fileset sources_1

if {$hexfile ne ""} { puts "Program memory initialised from $hexfile" }
puts "Block design created: [file join $proj_dir stm_bd.xpr]"
