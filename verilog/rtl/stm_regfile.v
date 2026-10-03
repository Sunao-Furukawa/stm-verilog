// =====================================================================
//  stm_regfile.v  <-  hard/045-g-ram.ch の GR 部分
//  汎用レジスタ GR[0..15] : 書き込み 2 ポート / 読み出し 4 ポート
//
//  C シミュレータでは W サイクルの書き込みが同じサイクルの読み出しに
//  見える (write-through) ので、読み出し側に書き込みデータのバイパスを置く。
//  同じアドレスに 2 ポート同時に書くことは無い (制御側が保証)。
//  万一重なった場合は C 版と同じく WE2 側が勝つ。
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
