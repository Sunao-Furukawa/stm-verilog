// =====================================================================
//  stm_prog_ram.v - program memory for the block design (create_bd.tcl)
//
//  A BRAM_PORTA slave for the AXI BRAM Controller: 2^AW words of 32 bits,
//  byte write enables, read latency 1. Vivado infers block RAM from it.
//  The initial contents are read with $readmemh from INIT_FILE, so the
//  output of tools/mem2hex.py can be used as it is ("@" lines are word
//  addresses). ADDR is the byte address from the controller.
//
//  With BYTE_SWAP=0 on stm_axi_top the CPU's words go to the bus unchanged,
//  so the word image of mem2hex.py is also the image the CPU sees.
// =====================================================================
module stm_prog_ram #(
  parameter AW        = 11,         // 2^AW words (11 = 8KB)
  parameter INIT_FILE = ""          // $readmemh file, "" = all zeros
) (
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA CLK" *)
  (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL,MEM_ECC NONE,MEM_WIDTH 32,READ_WRITE_MODE READ_WRITE,READ_LATENCY 1" *)
  input              clk,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA RST" *)
  input              rst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA EN" *)
  input              en,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA WE" *)
  input      [3:0]   we,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *)
  input      [AW+1:0] addr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA DIN" *)
  input      [31:0]  din,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA DOUT" *)
  output reg [31:0]  dout
);
  reg [31:0] mem [0:(1<<AW)-1];

  integer k;
  initial begin
    for (k = 0; k < (1<<AW); k = k + 1) mem[k] = 32'd0;
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

  wire [AW-1:0] a = addr[AW+1:2];

  always @(posedge clk)
    if (en) begin
      if (we[0]) mem[a][ 7: 0] <= din[ 7: 0];
      if (we[1]) mem[a][15: 8] <= din[15: 8];
      if (we[2]) mem[a][23:16] <= din[23:16];
      if (we[3]) mem[a][31:24] <= din[31:24];
      dout <= mem[a];
    end
endmodule
