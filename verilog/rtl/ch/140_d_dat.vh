// =====================================================================
//  140_d_dat.vh  <-  hard/140-d-dat.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】D → A で渡すオペランドの選択 (バイパス)
//
// レジスタファイルから読んだ値より新しい値がパイプライン中にあれば
// そちらを使う。優先順位 (新しい順) は
//   A の EX 結果 > B の EX 結果 > ロードデータ (B/E) > E の ALU 結果
//   > E の EX 結果 > W の結果 > レジスタファイル
// A がインタロック中 (A_INTLK) は基本的に値を保持するが、待っていた
// ロードデータ / ALU 結果が届いたらそれを取り込む (A_EAB の解除)。
// ---------------------------------------------------------------------

// d-dat

// 【解説】各オペランドがレジスタから来るか。インタロック中のバイパス判定と
//         A_EAB (060_g_srq.vh) に使う。
assign A_LS_OPB_IS_GR_NEW = A_INTLK ? A_LS_OPB_IS_GR  :
	D_FWD ? DD_FIRST_RADB_V | DD_ISSUE_SECOND_INSN & DD_SECOND_RADB_V : 0;
assign A_EX_OP1_IS_GR_NEW = A_INTLK ? A_EX_OP1_IS_GR  :
	D_FWD ? DD_FIRST_RAD1_V | DD_ISSUE_SECOND_INSN & DD_SECOND_RAD1_V : 0;
assign A_EX_OP2_IS_GR_NEW = A_INTLK ? A_EX_OP2_IS_GR  :
	D_FWD ? DD_FIRST_RAD2_V | DD_ISSUE_SECOND_INSN & DD_SECOND_RAD2_V : 0;


// 【解説】リンク付き分岐の戻り番地 = 分岐命令の番地 + 4。
//         PART1 (32bit) と PART2+4 (6bit) に分けて EXU に渡し、AU で足す。
assign DD_JB_INSN_AD_PART2P4 = add4_5(DD_JB_INSN_AD_PART2);   // ... + 4

// ---- #if 0 (元ソースで無効化) ----
// A-LS-OPB-DT	:=   
// 	( !A-INTLK & (DD-RADB == W-WAD1) 
// 	 | A-INTLK & (A-LS-RADB == W-WAD1) & A-LS-OPB-IS-GR ) & W-WE1 ? W-WDT1 :
// 	( !A-INTLK & (DD-RADB == W-WAD2) 
// 	 | A-INTLK & (A-LS-RADB == W-WAD2) & A-LS-OPB-IS-GR ) & W-WE2 ? W-WDT2 :
// 	!A-INTLK ? GR-DT-B : A-LS-OPB-DT  
//
// A-EX-OP1-DT	:=   
//     ( !A-INTLK & (DD-RAD1 == W-WAD1) 
// 	 | A-INTLK & (A-EX-RAD1 == W-WAD1) & A-EX-OP1-IS-GR ) & W-WE1 ? W-WDT1 :
//     ( !A-INTLK & (DD-RAD1 == W-WAD2) 
// 	 | A-INTLK & (A-EX-RAD1 == W-WAD2) & A-EX-OP1-IS-GR ) & W-WE2 ? W-WDT2 :
//      A-INTLK 		? A-EX-OP1-DT :
//     (IJB-V & IJB-LINK)  ? sign_ext_6(DD-JB-INSN-AD-PART2P4) : GR-DT-1 
//
// A-EX-OP2-DT	:=   
//     !A-INTLK & (IEX-OP2MODE == EXMOD-RI)     ? sign-ext-16(IEX-IMM16) :
//     ( !A-INTLK & (DD-RAD2 == W-WAD1) 
// 	 | A-INTLK & (A-EX-RAD2 == W-WAD1) & A-EX-OP2-IS-GR ) & W-WE1 ? W-WDT1 :
//     ( !A-INTLK & (DD-RAD2 == W-WAD2) 
// 	 | A-INTLK & (A-EX-RAD2 == W-WAD2) & A-EX-OP2-IS-GR ) & W-WE2 ? W-WDT2 :
//      A-INTLK 		? A-EX-OP2-DT :
//     (IJB-V & IJB-LINK)  ? DD-JB-INSN-AD-PART1 : GR-DT-2
// ---- #else (有効) ----
// 【解説】LS パイプのベースレジスタの値 (アドレス計算用)。
assign A_LS_OPB_DT_NEW = 
	  !A_INTLK & (DD_RADB == A_WAD2) & A_WE2 ? AA_EX_RES :
	  !A_INTLK & (DD_RADB == B_WAD2) & B_WE2 ?  B_EX_RES :
	( !A_INTLK &
	    (  (DD_RADB == B_WAD1) & B_WE1
	     | (DD_RADB == E_WAD1) & E_WE1 & (E_LS_OPCODE == 0) & !E_OPCLH_LCH )
	 | A_INTLK & A_LS_OPB_IS_GR &
	    (  (A_LS_RADB == B_WAD1) & B_WE1
	     | (A_LS_RADB == E_WAD1) & E_WE1 & (E_LS_OPCODE == 0) & !E_OPCLH_LCH
		 & !((A_LS_RADB == B_WAD2) & B_WE2)  		   )
	)					? BB_MEM_DATA :
	( !A_INTLK & (DD_RADB == E_WAD1) & E_WE1
	 | A_INTLK & A_LS_OPB_IS_GR
	  & (A_LS_RADB == E_WAD1) & ((E_LS_OPCODE !=0) | E_OPCLH_LCH) & E_WE1
	  & !((A_LS_RADB == B_WAD2) & B_WE2)
	)				         ? EE_ALU_OUTPUT:
	  !A_INTLK & (DD_RADB == E_WAD2) & E_WE2 ?  E_EX_RES :
	  !A_INTLK & (DD_RADB == W_WAD1) & W_WE1 ?  W_WDT1   :
	  !A_INTLK & (DD_RADB == W_WAD2) & W_WE2 ?  W_WDT2   :
	  !A_INTLK ? GR_DT_B : A_LS_OPB_DT;

// 【解説】EX パイプの第 1 オペランド。リンク付き分岐なら
//         戻り番地の下位部分 PART2+4 を符号拡張したもの。
assign A_EX_OP1_DT_NEW = 
	  !A_INTLK & (IJB_V & IJB_LINK)  ? sign_ext_6(DD_JB_INSN_AD_PART2P4) :
	  !A_INTLK & (DD_RAD1 == A_WAD2) & A_WE2 ? AA_EX_RES :
	  !A_INTLK & (DD_RAD1 == B_WAD2) & B_WE2 ?  B_EX_RES :
	( !A_INTLK &
	    (  (DD_RAD1 == B_WAD1) & B_WE1
	     | (DD_RAD1 == E_WAD1) & E_WE1 & (E_LS_OPCODE == 0) & !E_OPCLH_LCH )
	 | A_INTLK & A_EX_OP1_IS_GR &
	    (  (A_EX_RAD1 == B_WAD1) & B_WE1
	     | (A_EX_RAD1 == E_WAD1) & E_WE1 & (E_LS_OPCODE == 0) & !E_OPCLH_LCH
		 & !((A_EX_RAD1 == B_WAD2) & B_WE2)  		   )
	)					? BB_MEM_DATA :
	( !A_INTLK & (DD_RAD1 == E_WAD1) & E_WE1
	 | A_INTLK & A_EX_OP1_IS_GR
	  & (A_EX_RAD1 == E_WAD1) & ((E_LS_OPCODE !=0) | E_OPCLH_LCH) & E_WE1
	  & !((A_EX_RAD1 == B_WAD2) & B_WE2)
	)				         ? EE_ALU_OUTPUT:
	  !A_INTLK & (DD_RAD1 == E_WAD2) & E_WE2 ?  E_EX_RES :
	  !A_INTLK & (DD_RAD1 == W_WAD1) & W_WE1 ?  W_WDT1   :
	  !A_INTLK & (DD_RAD1 == W_WAD2) & W_WE2 ?  W_WDT2   :
	  !A_INTLK ? GR_DT_1 : A_EX_OP1_DT;

// 【解説】EX パイプの第 2 オペランド。RI モードなら即値 (符号拡張),
//         リンク付き分岐なら PART1。
assign A_EX_OP2_DT_NEW = 
	  !A_INTLK & (IEX_OP2MODE == EXMOD_RI)     ? sign_ext_16(IEX_IMM16) :
	  !A_INTLK & (IJB_V & IJB_LINK)  ? DD_JB_INSN_AD_PART1 :
	  !A_INTLK & (DD_RAD2 == A_WAD2) & A_WE2 ? AA_EX_RES :
	  !A_INTLK & (DD_RAD2 == B_WAD2) & B_WE2 ?  B_EX_RES :
	( !A_INTLK &
	    (  (DD_RAD2 == B_WAD1) & B_WE1
	     | (DD_RAD2 == E_WAD1) & E_WE1 & (E_LS_OPCODE == 0) & !E_OPCLH_LCH )
	 | A_INTLK & A_EX_OP2_IS_GR &
	    (  (A_EX_RAD2 == B_WAD1) & B_WE1
	     | (A_EX_RAD2 == E_WAD1) & E_WE1 & (E_LS_OPCODE == 0) & !E_OPCLH_LCH
		 & !((A_EX_RAD2 == B_WAD2) & B_WE2)  		   )
	)					? BB_MEM_DATA :
	( !A_INTLK & (DD_RAD2 == E_WAD1) & E_WE1
	 | A_INTLK & A_EX_OP2_IS_GR
	  & (A_EX_RAD2 == E_WAD1) & ((E_LS_OPCODE !=0) | E_OPCLH_LCH) & E_WE1
	  & !((A_EX_RAD2 == B_WAD2) & B_WE2)
	)				         ? EE_ALU_OUTPUT:
	  !A_INTLK & (DD_RAD2 == E_WAD2) & E_WE2 ?  E_EX_RES :
	  !A_INTLK & (DD_RAD2 == W_WAD1) & W_WE1 ?  W_WDT1   :
	  !A_INTLK & (DD_RAD2 == W_WAD2) & W_WE2 ?  W_WDT2   :
	  !A_INTLK ? GR_DT_2 : A_EX_OP2_DT;
// ---- #endif ----


// 【解説】読んだレジスタ番号を A へ (インタロック中のバイパス判定用)。
assign A_LS_RADB_NEW = A_INTLK ? A_LS_RADB : DD_RADB;

assign A_EX_RAD1_NEW = A_INTLK ? A_EX_RAD1 : DD_RAD1;

assign A_EX_RAD2_NEW = A_INTLK ? A_EX_RAD2 : DD_RAD2;

// 【解説】アドレス計算用の変位。
assign A_DISP_NEW = A_INTLK ? A_DISP    : DD_DISP;
