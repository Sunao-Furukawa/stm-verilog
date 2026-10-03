// =====================================================================
//  stm_memory.v  <-  hard/045-g-ram.ch の Mem 部分
//  命令/データ共用の単純なメモリモデル (シミュレーション用)。
//    * オペランド側: 1 語 (LBS-AD) の読み書き
//    * 命令フェッチ側: 8 バイト境界の 2 語 (IB-AD) を同時に読む
//  C 版と同じく、書き込みは同じサイクルの読み出しに見える (write-through)。
//  サイズは C 版と同じ 1024 語 (4KB) が既定。
// =====================================================================
module stm_memory #(
  parameter AW       = 10,          // 語アドレス幅 (2^AW 語)
  parameter INIT_HEX = ""           // $readmemh で読む初期化ファイル
) (
  input             clk,
  input             we,
  input      [31:0] opad,           // LBS-AD
  input      [31:0] stdt,           // LBS-DT
  input      [31:0] ifad,           // IB-AD
  output     [31:0] opdt,           // MEM-DT-OP
  output     [31:0] ifdth,          // MEM-DT-IF-H
  output     [31:0] ifdtl           // MEM-DT-IF-L
);
  reg [31:0] mem [0:(1<<AW)-1];

  integer k;
  initial begin
    for (k = 0; k < (1<<AW); k = k + 1) mem[k] = 32'd0;
    if (INIT_HEX != "") $readmemh(INIT_HEX, mem);
  end

  wire [AW-1:0] op_w = opad[AW+1:2];                 // LBS-AD >> 2
  wire [AW-1:0] ih_w = {ifad[AW+1:3], 1'b0};         // (IB-AD >> 2) & ~1
  wire [AW-1:0] il_w = {ifad[AW+1:3], 1'b1};         // (IB-AD >> 2) |  1

  always @(posedge clk)
    if (we) mem[op_w] <= stdt;

  assign opdt  = we ? stdt : mem[op_w];
  assign ifdth = (we && op_w == ih_w) ? stdt : mem[ih_w];
  assign ifdtl = (we && op_w == il_w) ? stdt : mem[il_w];
endmodule
