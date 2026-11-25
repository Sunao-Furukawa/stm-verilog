// =====================================================================
//  stm_regfile.v  <-  hard/045-g-ram.ch の GR 部分
//  汎用レジスタ GR[0..15] : 書き込み 2 ポート / 読み出し 4 ポート
//
//  C シミュレータでは W サイクルの書き込みが同じサイクルの読み出しに
//  見える (write-through) ので、読み出し側に書き込みデータのバイパスを置く。
//  同じアドレスに 2 ポート同時に書くことは無い (制御側が保証)。
//  万一重なった場合は C 版と同じく WE2 側が勝つ。
//
// 【ネットリスト解説】
//   ・ポートのつながり (stm_sys.v / stm_axi_top.v):
//       we1/wad1/wdt1 <- W_WE1/W_WAD1/W_WDT1 (LS パイプの結果)
//       we2/wad2/wdt2 <- W_WE2/W_WAD2/W_WDT2 (EX パイプの結果)
//       rad1/rdt1, rad2/rdt2, radb/rdtb <- DD_RAD1/2/B -> GR_DT_1/2/B (D サイクル, 140 へ)
//       rads/rdts                       <- B_LS_RADS   -> GR_DT_S     (B サイクル, 100 へ)
//   ・書き込み 2 ポート + 読み出し 4 ポート (非同期読み出し) という形は FPGA の
//     ブロック RAM にも分散 RAM (LUTRAM, 書き込み 1 ポート) にも入らないので、
//     合成すると 16 語 x 32bit = 512 本の FF と、読み出しポートごとの 16:1 MUX
//     (32bit x 4 ポート) になる。Vivado の結果では FDRE 512 個, LUT6 640 個,
//     MUXF7 320 個, MUXF8 64 個 (stm_system_cpu_0_stm_regfile)。
//     FF の名前は gr_reg[番号][ビット]。
//   ・各 FF の D 入力は「we2 && wad2 == k ? wdt2 : we1 && wad1 == k ? wdt1 : 保持」。
//     4bit のデコーダ 2 個で書き込み先を選び、保持は CE になる。
//   ・読み出し側の assign の「書き込み中なら書き込みデータを返す」比較は
//     4bit 一致比較器 2 個 + 32bit 3:1 MUX で、上の 16:1 MUX の後ろに付く。
//     W の FF → この MUX → 140 / 100 のバイパス MUX → A_*_DT / E_LS_OPS_DT の FF。
//   ・initial 文の 0 クリアは FPGA では FF の初期値 (INIT) になる。
//     stm_cntl と違いリセット入力は無い (リセットしてもレジスタの中身は残る)。
// =====================================================================
module stm_regfile (
  input             clk,
  input             we1, we2,
  input      [3:0]  wad1, wad2,
  input      [31:0] wdt1, wdt2,
  input      [3:0]  rad1, rad2, radb, rads,
  output     [31:0] rdt1, rdt2, rdtb, rdts
);
  reg [31:0] gr [0:15];

  integer k;
  initial for (k = 0; k < 16; k = k + 1) gr[k] = 32'd0;

  always @(posedge clk) begin
    if (we1) gr[wad1] <= wdt1;
    if (we2) gr[wad2] <= wdt2;   // 後に書いた方が優先 (C 版と同じ順序)
  end

  assign rdt1 = (we2 && wad2 == rad1) ? wdt2 : (we1 && wad1 == rad1) ? wdt1 : gr[rad1];
  assign rdt2 = (we2 && wad2 == rad2) ? wdt2 : (we1 && wad1 == rad2) ? wdt1 : gr[rad2];
  assign rdtb = (we2 && wad2 == radb) ? wdt2 : (we1 && wad1 == radb) ? wdt1 : gr[radb];
  assign rdts = (we2 && wad2 == rads) ? wdt2 : (we1 && wad1 == rads) ? wdt1 : gr[rads];
endmodule
