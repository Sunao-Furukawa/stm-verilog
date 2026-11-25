// =====================================================================
//  stm_memory.v  <-  hard/045-g-ram.ch の Mem 部分
//  命令/データ共用の単純なメモリモデル (シミュレーション用)。
//    * オペランド側: 1 語 (LBS-AD) の読み書き
//    * 命令フェッチ側: 8 バイト境界の 2 語 (IB-AD) を同時に読む
//  C 版と同じく、書き込みは同じサイクルの読み出しに見える (write-through)。
//  サイズは C 版と同じ 1024 語 (4KB) が既定。
//
//  The Mem part of hard/045-g-ram.ch.
//  A simple memory model shared by instructions and data (for simulation).
//    * operand side: read/write of 1 word (LBS-AD)
//    * fetch side: reads the 2 words at an 8-byte boundary (IB-AD) at once
//  As in the C version, a write is visible to reads in the same cycle (write-through).
//  The default size is 1024 words (4 KB), the same as the C version.
//
// 【ネットリスト解説】
//   ・ポートのつながり (stm_sys.v):
//       we / opad / stdt <- LBS_WE / LBS_AD / LBS_DT (S ユニット OP-B の FF, 160)
//       opdt             -> MEM_DT_OP   (050 の OP_LBS_DATA へ)
//       ifad             <- IB_AD       (命令フェッチの FF, 190)
//       ifdth / ifdtl    -> MEM_DT_IF_H / MEM_DT_IF_L (180 へ。番地 8n と 8n+4 の 2 語)
//   ・読み出しは 3 ポートとも非同期 (クロックを待たない) なので、FPGA の
//     ブロック RAM (読み出しは同期) にはならない。シミュレーション用のモデルで、
//     論理合成するのは stm_axi_top の方 (メモリは外の AXI スレーブ)。
//   ・番地は下位 AW+2 bit しか見ない (上位は無視して折り返す)。そのため
//     0xF000_0008 (tb のコンソール) へのストアはメモリの 0x008 にも書かれる。
//   ・ifdth / ifdtl のバイパスは「同じサイクルにストアしている語をフェッチする」
//     場合のためで、C 版の評価順 (書き込みの後に読む) を再現している。
//
// [Netlist notes]
//   - Port connections (stm_sys.v):
//       we / opad / stdt <- LBS_WE / LBS_AD / LBS_DT (FFs of S-unit OP-B, 160)
//       opdt             -> MEM_DT_OP   (to OP_LBS_DATA in 050)
//       ifad             <- IB_AD       (fetch FFs, 190)
//       ifdth / ifdtl    -> MEM_DT_IF_H / MEM_DT_IF_L (to 180; the 2 words at 8n and 8n+4)
//   - All 3 read ports are asynchronous (they don't wait for a clock), so this does not become
//     FPGA block RAM (whose reads are synchronous). It is a model for simulation; what gets
//     synthesized is stm_axi_top (with the memory as an external AXI slave).
//   - Only the low AW+2 address bits are used (the upper bits are ignored and wrap around).
//     So a store to 0xF000_0008 (the console of the tb) is also written to 0x008 of the memory.
//   - The bypass on ifdth / ifdtl is for fetching a word that is being stored in the same
//     cycle, and it reproduces the evaluation order of the C version (read after write).
// =====================================================================
module stm_memory #(
  parameter AW       = 10,          // 語アドレス幅 (2^AW 語)
                                    // word address width (2^AW words)
  parameter INIT_HEX = ""           // $readmemh で読む初期化ファイル
                                    // init file read with $readmemh
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
