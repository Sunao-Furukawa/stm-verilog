//  g-ram : RAM and Register File   (<- hard/045-g-ram.ch)
//
//  元ソースは全体が #ifndef VHDL で囲まれた C シミュレータ専用の記述:
//
//    if (W-WE1) { GR[W-WAD1] := W-WDT1 }
//    if (W-WE2) { GR[W-WAD2] := W-WDT2 }
//    GR-DT-1 = GR[DD-RAD1]       GR-DT-2 = GR[DD-RAD2]
//    GR-DT-B = GR[DD-RADB]       GR-DT-S = GR[B-LS-RADS]
//
//    if (LBS-WE)  { Mem[LBS-AD >> 2] := LBS-DT }
//    MEM-DT-OP   = Mem[LBS-AD >> 2]
//    MEM-DT-IF-H = Mem[(IB-AD >> 2) & ~1]
//    MEM-DT-IF-L = Mem[(IB-AD >> 2) |  1]
//
//  Verilog 版ではレジスタファイルとメモリは制御回路の外に出し、
//    stm_regfile.v (GR[0..15])  /  stm_memory.v (Mem)
//  として別モジュールにした (VHDL 版の regfile.vbe / memory.vbe と同じ分け方)。
//  stm_cntl のポート
//    出力: DD_RAD1, DD_RAD2, DD_RADB, B_LS_RADS, W_WE1/2, W_WAD1/2, W_WDT1/2,
//          LBS_WE, LBS_AD, LBS_DT, IB_AD
//    入力: GR_DT_1, GR_DT_2, GR_DT_B, GR_DT_S, MEM_DT_OP, MEM_DT_IF_H, MEM_DT_IF_L
//  が上記の配列アクセスに相当する。
//
//  注意: C 版では GR[..] := / Mem[..] := は「_NEW を介さず即座に」書き込まれ、
//        同じサイクルの後続の読み出しは書き込んだ値を見る (write-through)。
//        stm_regfile.v / stm_memory.v はこの動作を読み出しバイパスで再現している。
