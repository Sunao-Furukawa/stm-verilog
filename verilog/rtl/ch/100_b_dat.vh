// =====================================================================
//  100_b_dat.vh  <-  hard/100-b-dat.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
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
// ---------------------------------------------------------------------

// b-dat


// Bypass register if B-reg-num matches W-reg-num. (Execute-Execute Bypass)

// This is done even if the current E-cyc will overwrite the data that is
// just bypassed.  In such cases, the new correct data in WDTi is used
// instead of OPi-DT.  No problem.


// ---- #if 0 (元ソースで無効化) ----
// E-LS-OPS-DT := 
// 	   E-INTLK & (E-LS-OPS-IS-GR & W-WE1 & (E-LS-RADS == W-WAD1)) 
// 	| !E-INTLK & (B-LS-OPS-IS-GR & W-WE1 & (B-LS-RADS == W-WAD1)) ? W-WDT1 :
// 	   E-INTLK & (E-LS-OPS-IS-GR & W-WE2 & (E-LS-RADS == W-WAD2)) 
// 	| !E-INTLK & (B-LS-OPS-IS-GR & W-WE2 & (B-LS-RADS == W-WAD2)) ? W-WDT2 :
// 	  !E-INTLK                                         ? GR-DT-S :
//   		 					     E-LS-OPS-DT
// ---- #else (有効) ----
// 【解説】B → E で渡すレジスタオペランド。新しい順に
//           B の EX 結果 (同じ組で EX が先) > E の ALU 結果 > E の EX 結果
//           > W の結果 > レジスタファイル (GR_DT_S)
//         (#if 0 の旧版は、E インタロック中にも W から取り直す方式だった)
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
assign E_OPCLH_LCH_NEW = !E_STB_INTLK ? B_OPCLH 		: E_OPCLH_LCH;
assign E_LS_INTCODE_NEW = !E_STB_INTLK ? OP_B_INTCODE 	: E_LS_INTCODE;
// ---- #if 0 (元ソースで無効化) ----
// E-LS-LD-DT   := !E-STB-INTLK & (B-LS-LD-V & STB-V & (B-LS-LOG-AD == STB-AD)) ?
//                 	  STB-DT : 
// 		!E-STB-INTLK ? OP-LBS-DATA 	: E-LS-LD-DT
// ---- #else (有効) ----
// 【解説】ロードデータ。B のロードと同じ番地を
//           ・E のストアが書こうとしている → その書き込みデータ (EE_ALU_OUTPUT)
//           ・ストアバッファ STB が持っている → STB_DT
//         ならそちらを使い、そうでなければキャッシュの値。
//         EXT_BUS=1 ではフォワーディングを OP_LBS_DATA (050_op_lb1.vh) で
//         済ませているので、ここでは何もしない。
assign BB_MEM_DATA = EXT_BUS ? OP_LBS_DATA :
	(B_LS_LD_V & E_LS_ST_V & (B_LS_LOG_AD == E_LS_LOG_AD)) ? EE_ALU_OUTPUT :
	(B_LS_LD_V & STB_V & (B_LS_LOG_AD == STB_AD)) ? STB_DT :
	 OP_LBS_DATA;
assign E_LS_LD_DT_NEW = !E_STB_INTLK ? BB_MEM_DATA 	: E_LS_LD_DT;
// ---- #endif ----
