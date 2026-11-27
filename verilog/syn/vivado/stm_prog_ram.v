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
//
// 【解説】(日本語)
//   create_bd.tcl で作るブロックデザインのプログラムメモリ。AXI BRAM Controller の
//   BRAM_PORTA (ブロック RAM 用のポート) につながるスレーブで、32bit x 2^AW 語,
//   バイト単位の書き込み許可付き, 読み出しの遅れは 1 クロック。
//   初期値は INIT_FILE を $readmemh で読むので、tools/mem2hex.py の出力をそのまま使える
//   ("@" の行は語番地)。addr はコントローラからのバイト番地。
//
// 【ネットリスト解説】
//   ・ポートのつながり (ブロックデザインの中):
//       AXI SmartConnect → AXI BRAM Controller (stm_system_bram_ctrl_0)
//         → BRAM_PORTA (clk, rst, en, we[3:0], addr, din, dout) → このモジュール
//     ポートに付いた X_INTERFACE_INFO 属性は、Vivado IP Integrator にこれらの
//     ネットが「BRAM_PORTA という 1 本のインタフェース」であることを教えるもの。
//     この属性があるので、ブロックデザインで 1 本の線としてつなげる。回路には影響しない。
//   ・always の形 (同期書き込み + 同期読み出し, en でまとめて止める) は
//     ブロック RAM の定型なので、Vivado は RAMB36E1 に割り当てる
//     (AW=11 の 8KB なら RAMB36E1 2 個)。we[k] はブロック RAM のバイト書き込み許可
//     (WEA[k]) に直接つながり、dout は RAM の出力ラッチそのもの (別の FF は無い)。
//   ・rst は使っていない (ブロック RAM の内容はリセットで消えない)。
//   ・initial の内容は合成時にブロック RAM の初期値 (INIT_xx 属性) として
//     ビットストリームに埋め込まれる。
//   ・バイトレーン: we[0] / din[7:0] が語の下位バイト。STM はビッグエンディアンで
//     番地 4n のバイトが語の上位 ([31:24]) なので、BYTE_SWAP=0 では
//     AXI のバイト番地とメモリの語の中のバイト位置が逆になる。CPU は語単位でしか
//     バスに出ない (stm_axi_master.v 参照) ので、CPU から使う限り問題にならない。
//
// [Netlist notes]
//   - Port connections (inside the block design):
//       AXI SmartConnect -> AXI BRAM Controller (stm_system_bram_ctrl_0)
//         -> BRAM_PORTA (clk, rst, en, we[3:0], addr, din, dout) -> this module
//     The X_INTERFACE_INFO attributes on the ports tell Vivado IP Integrator that these nets
//     form one interface called BRAM_PORTA. Thanks to them they can be connected as a single
//     line in the block design. They have no effect on the circuit.
//   - The shape of the always block (synchronous write + synchronous read, all stopped by en)
//     is the standard block RAM template, so Vivado maps it to RAMB36E1
//     (2 RAMB36E1 for AW=11, 8 KB). we[k] connects directly to the byte write enables of the
//     block RAM (WEA[k]), and dout is the RAM's own output latch (no separate FF).
//   - rst is not used (the contents of a block RAM are not cleared by reset).
//   - The contents from initial are embedded in the bitstream at synthesis as the block RAM's
//     initial value (the INIT_xx attributes).
//   - Byte lanes: we[0] / din[7:0] are the low byte of the word. STM is big-endian and the byte
//     at address 4n is the top of the word ([31:24]), so with BYTE_SWAP=0 the AXI byte address
//     and the byte position inside the memory word are reversed. The CPU only puts whole words
//     on the bus (see stm_axi_master.v), so this does not matter as long as the CPU uses it.
// =====================================================================
module stm_prog_ram #(                                  // ブロックデザイン用のプログラムメモリ (ブロックRAMとして合成される) / program memory for the block design (synthesized as block RAM)
  parameter AW        = 11,         // 2^AW words (11 = 8KB)  -- 語番地の幅: 2^11語 = 8KB → RAMB36E1 2個 / word-address width: 2^11 words = 8 KB -> 2 RAMB36E1
  parameter INIT_FILE = ""          // $readmemh file, "" = all zeros  -- 初期値のファイル (mem2hex.pyの出力). 合成でRAMのINIT_xx属性になる / initial-contents file (mem2hex.py output); becomes the RAM's INIT_xx attributes
) (                                                     // パラメータの終わり, ポートの始まり / end of parameters, start of ports
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA CLK" *) // 次のclkがBRAM_PORTAのCLKだとIP Integratorに教える属性 (回路は変わらない) / tells IP Integrator the next clk is BRAM_PORTA CLK (no effect on logic)
  (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL,MEM_ECC NONE,MEM_WIDTH 32,READ_WRITE_MODE READ_WRITE,READ_LATENCY 1" *) // インタフェースの性質: 32bit幅, 読み出し遅れ1, ECC無し / interface properties: 32 bits wide, read latency 1, no ECC
  input              clk,                               // クロック → RAMB36E1のCLKARDCLK / clock -> CLKARDCLK of the RAMB36E1
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA RST" *) // 次のrstがBRAM_PORTAのRST / the next rst is BRAM_PORTA RST
  input              rst,                               // リセット: 未使用 (どこにもつながらない) / reset: unused (left unconnected)
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA EN" *) // 次のenがBRAM_PORTAのEN / the next en is BRAM_PORTA EN
  input              en,                                // ポート有効 → RAMのENARDEN (読み書きを止める) / port enable -> ENARDEN of the RAM (stops read and write)
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA WE" *) // 次のweがBRAM_PORTAのWE / the next we is BRAM_PORTA WE
  input      [3:0]   we,                                // バイト書き込み許可 → RAMのWEA[3:0]に直結 / byte write enables -> wired to WEA[3:0] of the RAM
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *) // 次のaddrがBRAM_PORTAのADDR / the next addr is BRAM_PORTA ADDR
  input      [AW+1:0] addr,                             // バイト番地 (コントローラから) / byte address (from the controller)
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA DIN" *) // 次のdinがBRAM_PORTAのDIN / the next din is BRAM_PORTA DIN
  input      [31:0]  din,                               // 書き込みデータ → RAMのDIADI / write data -> DIADI of the RAM
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTA DOUT" *) // 次のdoutがBRAM_PORTAのDOUT / the next dout is BRAM_PORTA DOUT
  output reg [31:0]  dout                               // 読み出しデータ: RAM内蔵の出力ラッチ (別のFFは作られない) / read data: the RAM's built-in output latch (no extra FF)
);                                                      // ポート宣言の終わり / end of ports
  reg [31:0] mem [0:(1<<AW)-1];                         // 2^AW語x32bit → RAMB36E1 (AW=11なら2個) / 2^AW x 32 bits -> RAMB36E1 (2 for AW=11)

  integer k;                                            // 初期化ループの変数 / init loop variable
  initial begin                                         // 初期値: 合成でRAMのINIT_xx属性になりビットストリームに入る / initial contents: become the RAM's INIT_xx attributes in the bitstream
    for (k = 0; k < (1<<AW); k = k + 1) mem[k] = 32'd0; // まず全語0 / first all words 0
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);     // プログラムを読み込む / load the program
  end                                                   // initial の終わり / end of initial

  wire [AW-1:0] a = addr[AW+1:2];                       // 語番地 = バイト番地の下位2bitを捨てる (配線) → RAMのADDRARDADDR / word address = byte address without the low 2 bits (wires) -> ADDRARDADDR

  always @(posedge clk)                                 // 同期書き込み+同期読み出し: ブロックRAMの定型 / synchronous write + read: the block RAM template
    if (en) begin                                       // enが0なら何もしない (RAMのENに対応) / do nothing when en=0 (the RAM's EN)
      if (we[0]) mem[a][ 7: 0] <= din[ 7: 0];           // バイト0 (語の下位, AXIのバイト番地4n+0) を書く / write byte lane 0 (low byte, AXI byte 4n+0)
      if (we[1]) mem[a][15: 8] <= din[15: 8];           // バイトレーン1を書く / write byte lane 1
      if (we[2]) mem[a][23:16] <= din[23:16];           // バイトレーン2を書く / write byte lane 2
      if (we[3]) mem[a][31:24] <= din[31:24];           // バイトレーン3 (語の上位) を書く / write byte lane 3 (high byte)
      dout <= mem[a];                                   // 書き込み前の値を読む (READ_FIRST): 1クロック遅れで出る / read the old value (READ_FIRST): appears one clock later
    end                                                 // if (en) の終わり / end of if (en)
endmodule                                               // モジュールの終わり / end of module
