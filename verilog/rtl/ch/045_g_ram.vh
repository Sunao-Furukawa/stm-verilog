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
//
//  The whole original source is surrounded by #ifndef VHDL; it is code for the C simulator only
//  (shown above).
//  In the Verilog version the register file and the memory are moved out of the control
//  circuit into separate modules,
//    stm_regfile.v (GR[0..15])  /  stm_memory.v (Mem)
//  (the same split as regfile.vbe / memory.vbe of the VHDL version).
//  The ports of stm_cntl
//    outputs: DD_RAD1, DD_RAD2, DD_RADB, B_LS_RADS, W_WE1/2, W_WAD1/2, W_WDT1/2,
//             LBS_WE, LBS_AD, LBS_DT, IB_AD
//    inputs : GR_DT_1, GR_DT_2, GR_DT_B, GR_DT_S, MEM_DT_OP, MEM_DT_IF_H, MEM_DT_IF_L
//  correspond to the array accesses above.
//
//  Note: in the C version GR[..] := / Mem[..] := are written "at once, not through _NEW",
//        and later reads in the same cycle see the written value (write-through).
//        stm_regfile.v / stm_memory.v reproduce this with read bypasses.
//
// 【ネットリスト解説】このファイルには回路が無い (assign が 1 つも無い)。
//   上の配列アクセスは、stm_cntl のポートを通して次のネットとして実現されている
//   (つなぐのは stm_sys.v / stm_axi_top.v):
//     GR の書き込み : W_WE1/2, W_WAD1/2, W_WDT1/2 (090 の FF)  -> stm_regfile
//     GR の読み出し : DD_RAD1/2/B (030, 組合せ), B_LS_RADS (130 の FF) -> stm_regfile
//                     -> GR_DT_1/2/B (140 へ), GR_DT_S (100 へ)
//     Mem の読み書き: LBS_WE/AD/DT (160 の FF) -> stm_memory -> MEM_DT_OP (050 へ)
//     命令フェッチ  : IB_AD (190 の FF) -> stm_memory -> MEM_DT_IF_H/L (180 へ)
//   AXI4 版 (stm_axi_top) では Mem の代わりに stm_axi_master / stm_icache がつながり、
//   応答が遅れてもよいように RANDOM_FOR_OPCLH / RANDOM_FOR_IFCLH が「データが揃った」
//   合図になる。
//
// [Netlist notes] This file has no circuit (not a single assign).
//   The array accesses above are realised as the following nets through the ports of
//   stm_cntl (connected in stm_sys.v / stm_axi_top.v):
//     GR write  : W_WE1/2, W_WAD1/2, W_WDT1/2 (FFs in 090)  -> stm_regfile
//     GR read   : DD_RAD1/2/B (030, combinational), B_LS_RADS (FF in 130) -> stm_regfile
//                 -> GR_DT_1/2/B (to 140), GR_DT_S (to 100)
//     Mem access: LBS_WE/AD/DT (FFs in 160) -> stm_memory -> MEM_DT_OP (to 050)
//     Fetch     : IB_AD (FF in 190) -> stm_memory -> MEM_DT_IF_H/L (to 180)
//   In the AXI4 version (stm_axi_top), stm_axi_master / stm_icache are connected instead of
//   Mem, and RANDOM_FOR_OPCLH / RANDOM_FOR_IFCLH become "the data is ready" signals so that
//   responses may be late.
