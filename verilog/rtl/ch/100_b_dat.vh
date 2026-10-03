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
assign BB_MEM_DATA = 
	(B_LS_LD_V & E_LS_ST_V & (B_LS_LOG_AD == E_LS_LOG_AD)) ? EE_ALU_OUTPUT :
	(B_LS_LD_V & STB_V & (B_LS_LOG_AD == STB_AD)) ? STB_DT :
	 OP_LBS_DATA;
assign E_LS_LD_DT_NEW = !E_STB_INTLK ? BB_MEM_DATA 	: E_LS_LD_DT;
// ---- #endif ----
