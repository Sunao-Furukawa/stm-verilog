// =====================================================================
//  100_b_dat.vh  <-  hard/100-b-dat.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】B サイクル: E サイクルへ渡すデータの準備
//
// ・レジスタオペランド (ストアデータ / EX-RM の第 1 オペランド) をレジスタ
//   ファイルから読む。より新しい値がパイプ中にあればそちらを使う (バイパス)
// ・キャッシュから返ったロードデータを受け取る。直前のストアが同じ番地なら
//   そのデータを使う (ストア → ロードのフォワーディング)
// E がインタロック中 (E_INTLK) は値を保持する。
//
// [Note] B cycle: preparing the data passed to the E cycle
//
// - reads the register operand (store data / first operand of EX-RM) from the register
//   file. If a newer value is in the pipe, that is used instead (bypass)
// - receives the load data returned by the cache. If the store just before has the same
//   address, its data is used (store-to-load forwarding)
// While E is interlocked (E_INTLK) the values are held.
//
// 【ネットリスト解説】
//   入力 : B_* (130 の FF), E_* (110 の FF), W_* (090 の FF), STB_* (090 の FF),
//          EE_ALU_OUTPUT (090 の ALU, 組合せ), B_OPCLH / OP_B_INTCODE / OP_LBS_DATA (050),
//          E_INTLK / E_STB_INTLK (070), ポート GR_DT_S (stm_regfile)
//   出力 (FF): E_LS_OPS_DT, E_LS_LD_DT, E_LS_INTCODE -> 090 (ALU の入力と割り込み)
//              E_OPCLH_LCH -> 050, 060, 070, 140 (「E のデータは揃った」)
//   出力 (組合せ): BB_MEM_DATA -> 140 (A へのロードデータのバイパス)
//   回路の形:
//     ・E_LS_OPS_DT_NEW は 32bit の 7:1 優先 MUX。選択条件は 4bit 一致比較器 5 個
//       (B_LS_RADS と B_WAD2 / E_WAD1 / E_WAD2 / W_WAD1 / W_WAD2) から作る。
//       データ入力の 1 つ EE_ALU_OUTPUT は同じサイクルの ALU 出力なので、
//       E の FF → ALU → この MUX → E_LS_OPS_DT の FF が 1 サイクルの経路。
//     ・BB_MEM_DATA は B のロード番地と E のストア番地 / STB 番地を比べる
//       32bit 一致比較器 2 個と 32bit 3:1 MUX。EXT_BUS=1 なら定数の伝搬で
//       OP_LBS_DATA そのもの (配線) になり、比較器は消える。
//     ・E_OPCLH_LCH / E_LS_INTCODE / E_LS_LD_DT は「!E_STB_INTLK のときだけ更新」
//       なので CE 付きの FF。
//
// [Netlist notes]
//   Inputs : B_* (FFs in 130), E_* (FFs in 110), W_* (FFs in 090), STB_* (FFs in 090),
//            EE_ALU_OUTPUT (ALU in 090, combinational), B_OPCLH / OP_B_INTCODE / OP_LBS_DATA (050),
//            E_INTLK / E_STB_INTLK (070), port GR_DT_S (stm_regfile)
//   Outputs (FFs): E_LS_OPS_DT, E_LS_LD_DT, E_LS_INTCODE -> 090 (ALU inputs and interrupt)
//                  E_OPCLH_LCH -> 050, 060, 070, 140 ("the data for E is ready")
//   Outputs (combinational): BB_MEM_DATA -> 140 (load-data bypass to A)
//   Circuit:
//     - E_LS_OPS_DT_NEW is a 32-bit 7:1 priority mux. Its selects come from five 4-bit
//       equality comparators (B_LS_RADS against B_WAD2 / E_WAD1 / E_WAD2 / W_WAD1 / W_WAD2).
//       One data input, EE_ALU_OUTPUT, is the ALU output of the same cycle, so
//       E FFs -> ALU -> this mux -> E_LS_OPS_DT FFs is a one-cycle path.
//     - BB_MEM_DATA is two 32-bit equality comparators (load address in B against the store
//       address in E / the STB address) and a 32-bit 3:1 mux. With EXT_BUS=1, constant
//       propagation turns it into OP_LBS_DATA itself (a wire) and the comparators disappear.
//     - E_OPCLH_LCH / E_LS_INTCODE / E_LS_LD_DT are "updated only when !E_STB_INTLK",
//       so they are FFs with CE.
// ---------------------------------------------------------------------

// b-dat


// Bypass register if B-reg-num matches W-reg-num. (Execute-Execute Bypass)

// This is done even if the current E-cyc will overwrite the data that is
// just bypassed.  In such cases, the new correct data in WDTi is used
// instead of OPi-DT.  No problem.


// ---- #if 0 (元ソースで無効化) ----
//      (#if 0: disabled in the original source)
// E-LS-OPS-DT := 
// 	   E-INTLK & (E-LS-OPS-IS-GR & W-WE1 & (E-LS-RADS == W-WAD1)) 
// 	| !E-INTLK & (B-LS-OPS-IS-GR & W-WE1 & (B-LS-RADS == W-WAD1)) ? W-WDT1 :
// 	   E-INTLK & (E-LS-OPS-IS-GR & W-WE2 & (E-LS-RADS == W-WAD2)) 
// 	| !E-INTLK & (B-LS-OPS-IS-GR & W-WE2 & (B-LS-RADS == W-WAD2)) ? W-WDT2 :
// 	  !E-INTLK                                         ? GR-DT-S :
//   		 					     E-LS-OPS-DT
// ---- #else (有効) ----
//      (#else: this is the version in effect)
// 【解説】B → E で渡すレジスタオペランド。新しい順に
//           B の EX 結果 (同じ組で EX が先) > E の ALU 結果 > E の EX 結果
//           > W の結果 > レジスタファイル (GR_DT_S)
//         (#if 0 の旧版は、E インタロック中にも W から取り直す方式だった)
//
// [Note] The register operand passed from B to E. Newest first:
//          EX result in B (when EX is first in the same pair) > ALU result in E > EX result in E
//          > results in W > register file (GR_DT_S)
//        (the old #if 0 version fetched again from W even during an E interlock)
assign E_LS_OPS_DT_NEW = 
	!E_INTLK & (B_LS_OPS_IS_GR & B_WE2 & (B_LS_RADS == B_WAD2))
		&  B_FIRST_IS_EX ? B_EX_RES :
	!E_INTLK & (B_LS_OPS_IS_GR & E_WE1 & (B_LS_RADS == E_WAD1)) ?
								EE_ALU_OUTPUT :
	!E_INTLK & (B_LS_OPS_IS_GR & E_WE2 & (B_LS_RADS == E_WAD2)) ? E_EX_RES :
	!E_INTLK & (B_LS_OPS_IS_GR & W_WE1 & (B_LS_RADS == W_WAD1)) ? W_WDT1 :
	!E_INTLK & (B_LS_OPS_IS_GR & W_WE2 & (B_LS_RADS == W_WAD2)) ? W_WDT2 :
	!E_INTLK                                         ? GR_DT_S :
  		 					     E_LS_OPS_DT;
// ---- #endif ----

// E-OPCLH-LCH should     be updated when LMD-INTLK,
//             should not be updated when STB-INTLK


// LD-DT : set DT, maybe SLB

// No need to bypass from B-LBS-DT ;  No concurrent LD and ST

// 【解説】キャッシュのヒット/割り込み結果を E 用に保持。ストアバッファ待ち
//         (E_STB_INTLK) の間は上書きしない。
// [Note] Keep the cache hit / interrupt result for E. Not overwritten while waiting for the
//        store buffer (E_STB_INTLK).
assign E_OPCLH_LCH_NEW = !E_STB_INTLK ? B_OPCLH 		: E_OPCLH_LCH;
assign E_LS_INTCODE_NEW = !E_STB_INTLK ? OP_B_INTCODE 	: E_LS_INTCODE;
// ---- #if 0 (元ソースで無効化) ----
//      (#if 0: disabled in the original source)
// E-LS-LD-DT   := !E-STB-INTLK & (B-LS-LD-V & STB-V & (B-LS-LOG-AD == STB-AD)) ?
//                 	  STB-DT : 
// 		!E-STB-INTLK ? OP-LBS-DATA 	: E-LS-LD-DT
// ---- #else (有効) ----
//      (#else: this is the version in effect)
// 【解説】ロードデータ。B のロードと同じ番地を
//           ・E のストアが書こうとしている → その書き込みデータ (EE_ALU_OUTPUT)
//           ・ストアバッファ STB が持っている → STB_DT
//         ならそちらを使い、そうでなければキャッシュの値。
//         EXT_BUS=1 ではフォワーディングを OP_LBS_DATA (050_op_lb1.vh) で
//         済ませているので、ここでは何もしない。
//
// [Note] Load data. If the address of the load in B is
//          - about to be written by the store in E -> that write data (EE_ALU_OUTPUT)
//          - held by the store buffer STB -> STB_DT
//        that is used; otherwise the cache value.
//        With EXT_BUS=1 the forwarding is already done in OP_LBS_DATA (050_op_lb1.vh),
//        so nothing is done here.
assign BB_MEM_DATA = EXT_BUS ? OP_LBS_DATA :
	(B_LS_LD_V & E_LS_ST_V & (B_LS_LOG_AD == E_LS_LOG_AD)) ? EE_ALU_OUTPUT :
	(B_LS_LD_V & STB_V & (B_LS_LOG_AD == STB_AD)) ? STB_DT :
	 OP_LBS_DATA;
assign E_LS_LD_DT_NEW = !E_STB_INTLK ? BB_MEM_DATA 	: E_LS_LD_DT;
// ---- #endif ----
