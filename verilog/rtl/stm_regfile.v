// =====================================================================
//  stm_regfile.v  <-  hard/045-g-ram.ch の GR 部分
//  汎用レジスタ GR[0..15] : 書き込み 2 ポート / 読み出し 4 ポート
//
//  C シミュレータでは W サイクルの書き込みが同じサイクルの読み出しに
//  見える (write-through) ので、読み出し側に書き込みデータのバイパスを置く。
//  同じアドレスに 2 ポート同時に書くことは無い (制御側が保証)。
//  万一重なった場合は C 版と同じく WE2 側が勝つ。
//
//  The GR part of hard/045-g-ram.ch.
//  General registers GR[0..15] : 2 write ports / 4 read ports
//
//  In the C simulator a write in the W cycle is visible to reads in the same cycle
//  (write-through), so a bypass of the write data is put on the read side.
//  Two ports never write the same address at once (guaranteed by the control).
//  If they ever did, WE2 wins, as in the C version.
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
//
// [Netlist notes]
//   - Port connections (stm_sys.v / stm_axi_top.v):
//       we1/wad1/wdt1 <- W_WE1/W_WAD1/W_WDT1 (result of the LS pipe)
//       we2/wad2/wdt2 <- W_WE2/W_WAD2/W_WDT2 (result of the EX pipe)
//       rad1/rdt1, rad2/rdt2, radb/rdtb <- DD_RAD1/2/B -> GR_DT_1/2/B (D cycle, to 140)
//       rads/rdts                       <- B_LS_RADS   -> GR_DT_S     (B cycle, to 100)
//   - 2 write ports + 4 read ports (asynchronous reads) fit neither FPGA block RAM nor
//     distributed RAM (LUTRAM, 1 write port), so synthesis makes 16 words x 32 bits = 512 FFs
//     and a 16:1 mux per read port (32 bits x 4 ports). The Vivado result has 512 FDRE,
//     640 LUT6, 320 MUXF7 and 64 MUXF8 (stm_system_cpu_0_stm_regfile).
//     The FFs are named gr_reg[number][bit].
//   - The D input of each FF is "we2 && wad2 == k ? wdt2 : we1 && wad1 == k ? wdt1 : hold".
//     Two 4-bit decoders select the destination, and the hold becomes CE.
//   - The "return the write data while writing" compares in the read assigns are two 4-bit
//     equality comparators + a 32-bit 3:1 mux after the 16:1 mux above.
//     W FFs -> this mux -> bypass muxes of 140 / 100 -> A_*_DT / E_LS_OPS_DT FFs.
//   - The 0-clear in the initial block becomes the FFs' initial value (INIT) on an FPGA.
//     Unlike stm_cntl there is no reset input (the register contents survive a reset).
// =====================================================================
module stm_regfile (                                    // 汎用レジスタ16本 (書き込み2/読み出し4ポート) / 16 general registers (2 write / 4 read ports)
  input             clk,                                // クロック: 512本のFFのC端子へ / clock: to the C pin of the 512 FFs
  input             we1, we2,                           // 書き込み許可 (1=LSパイプ, 2=EXパイプ) ← W_WE1/2のFF / write enables (1 LS pipe, 2 EX pipe) <- W_WE1/2 FFs
  input      [3:0]  wad1, wad2,                         // 書き込み番号 → 4→16のデコーダ2個 / write numbers -> two 4-to-16 decoders
  input      [31:0] wdt1, wdt2,                         // 書き込みデータ → 各FFのD入力の2:1 MUX / write data -> 2:1 mux on every FF's D
  input      [3:0]  rad1, rad2, radb, rads,             // 読み出し番号: rad1/2/bはDの組合せ(030), radsはBのFF(130) / read numbers: rad1/2/b combinational from D (030), rads an FF of B (130)
  output     [31:0] rdt1, rdt2, rdtb, rdts              // 読み出しデータ (非同期読み出し = 組合せ出力) / read data (asynchronous = combinational outputs)
);                                                      // ポート宣言の終わり / end of ports
  reg [31:0] gr [0:15];                                 // 16語x32bitの配列 → FDRE 512個 (gr_reg[番号][ビット]) / 16 x 32-bit array -> 512 FDREs (gr_reg[n][bit])

  integer k;                                            // initial文のループ変数 (回路にならない) / loop variable of the initial block (no hardware)
  initial for (k = 0; k < 16; k = k + 1) gr[k] = 32'd0; // 全レジスタを0で始める → FFの初期値INIT=0 (リセットでは消えない) / start every register at 0 -> FF INIT=0 (not cleared by reset)

  always @(posedge clk) begin                           // 書き込み: クロックの立ち上がりで / writes: on the rising clock edge
    if (we1) gr[wad1] <= wdt1;                          // LS側の書き込み: wad1デコード&we1 がそのFFのCE / LS write: decoded wad1 & we1 is that FF's CE
    if (we2) gr[wad2] <= wdt2;   // 後に書いた方が優先 (C 版と同じ順序)
                                 // the later write wins (same order as the C version)
  end                                                   // always の終わり / end of always

  assign rdt1 = (we2 && wad2 == rad1) ? wdt2 : (we1 && wad1 == rad1) ? wdt1 : gr[rad1]; // R1読み出し: 同じサイクルの書き込みを優先 (4bit比較器2個+32bit 3:1 MUX) + 16:1 MUX / R1 read: same-cycle write wins (2 comparators + 32-bit 3:1 mux) + 16:1 mux
  assign rdt2 = (we2 && wad2 == rad2) ? wdt2 : (we1 && wad1 == rad2) ? wdt1 : gr[rad2]; // R2読み出し (同じ形) → GR_DT_2 → 140 / R2 read (same form) -> GR_DT_2 -> 140
  assign rdtb = (we2 && wad2 == radb) ? wdt2 : (we1 && wad1 == radb) ? wdt1 : gr[radb]; // RB読み出し → GR_DT_B → 140 / RB read -> GR_DT_B -> 140
  assign rdts = (we2 && wad2 == rads) ? wdt2 : (we1 && wad1 == rads) ? wdt1 : gr[rads]; // RS読み出し (Bサイクル) → GR_DT_S → 100 / RS read (B cycle) -> GR_DT_S -> 100
endmodule                                               // モジュールの終わり / end of module
