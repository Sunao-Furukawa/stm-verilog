// =====================================================================
//  140_d_dat.vh  <-  hard/140-d-dat.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
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
//
// [Note] Selection of the operands passed from D to A (bypass)
//
// If a value newer than the one read from the register file is in the pipeline,
// that is used. The priority (newest first) is
//   EX result in A > EX result in B > load data (B/E) > ALU result in E
//   > EX result in E > results in W > register file
// While A is interlocked (A_INTLK) the values are basically held, but when the load data /
// ALU result A was waiting for arrives, it is taken in (releasing A_EAB).
//
// 【ネットリスト解説】
//   入力 : DD_RAD1/2/B (030), ポート GR_DT_1/2/B (stm_regfile),
//          各ステージの書き込み番号と有効ビット (A_WAD2/A_WE2, B_WAD*/B_WE*, E_WAD*/E_WE*,
//          W_WAD*/W_WE*), 各ステージの結果 (AA_EX_RES, B_EX_RES, BB_MEM_DATA,
//          EE_ALU_OUTPUT, E_EX_RES, W_WDT1/2), A_INTLK / D_FWD (070),
//          IEX_* / IJB_* (035), DD_DISP / DD_JB_INSN_AD_PART* (040)
//   出力 (FF): A_LS_OPB_DT / A_EX_OP1_DT / A_EX_OP2_DT / A_DISP -> 120 (演算器の入力)
//              A_LS_RADB / A_EX_RAD1 / A_EX_RAD2 / A_EX_OP2_IS_GR -> 060 (A_EAB), 120, 130
//   回路の形: このファイルが CPU でいちばん大きな組合せ回路 (バイパスネットワーク)。
//     ・オペランド 3 本 (B, 1, 2) それぞれに 32bit の優先 MUX がある
//       (入力は B が 9, 1 がリンク番地を足して 10, 2 が即値も足して 11)。
//     ・選択条件を作るため、読み出し番号 (DD_RAD* / A_*_RAD*) と 7 つの書き込み番号
//       (A_WAD2, B_WAD1, B_WAD2, E_WAD1, E_WAD2, W_WAD1, W_WAD2) を比べる
//       4bit 一致比較器が 1 オペランドあたり 10 個並ぶ (D からの番号で 7 個,
//       インタロック中の A の番号で 3 個)。
//     ・データ入力の多くは同じサイクルの演算結果 (AA_EX_RES = A の EXU,
//       EE_ALU_OUTPUT = E の ALU, BB_MEM_DATA = B のロードデータ) なので、
//       「A の FF → EXU → このバイパス MUX → A_*_DT の FF」
//       「E の FF → ALU → このバイパス MUX → A_*_DT の FF」
//       がこの CPU の最長経路の候補 (実際にどこが最長かはタイミングレポートで確かめること)。
//       合成結果では A_EX_OP1_DT[i]_i_2 などの LUT6 がビットごとに何段も並ぶ。
//     ・A_INTLK のときは基本的に保持 (CE) だが、待っていたロードデータ等を取り込む
//       経路があるので、A_*_DT は単純な CE 付き FF にはならず MUX が残る。
//
// [Netlist notes]
//   Inputs : DD_RAD1/2/B (030), ports GR_DT_1/2/B (stm_regfile),
//            write numbers and valid bits of each stage (A_WAD2/A_WE2, B_WAD*/B_WE*, E_WAD*/E_WE*,
//            W_WAD*/W_WE*), results of each stage (AA_EX_RES, B_EX_RES, BB_MEM_DATA,
//            EE_ALU_OUTPUT, E_EX_RES, W_WDT1/2), A_INTLK / D_FWD (070),
//            IEX_* / IJB_* (035), DD_DISP / DD_JB_INSN_AD_PART* (040)
//   Outputs (FFs): A_LS_OPB_DT / A_EX_OP1_DT / A_EX_OP2_DT / A_DISP -> 120 (unit inputs)
//                  A_LS_RADB / A_EX_RAD1 / A_EX_RAD2 / A_EX_OP2_IS_GR -> 060 (A_EAB), 120, 130
//   Circuit: this file is the largest piece of combinational logic in the CPU (the bypass network).
//     - Each of the 3 operands (B, 1, 2) has a 32-bit priority mux
//       (9 inputs for B, 10 for 1 with the link address, 11 for 2 with the immediate too).
//     - To make the selects, 4-bit equality comparators compare the read numbers
//       (DD_RAD* / A_*_RAD*) with the 7 write numbers (A_WAD2, B_WAD1, B_WAD2, E_WAD1, E_WAD2,
//       W_WAD1, W_WAD2): 10 per operand (7 for the numbers from D, 3 for the numbers of A
//       during an interlock).
//     - Many data inputs are results computed in the same cycle (AA_EX_RES = the EXU of A,
//       EE_ALU_OUTPUT = the ALU of E, BB_MEM_DATA = load data in B), so
//       "A FFs -> EXU -> this bypass mux -> A_*_DT FFs" and
//       "E FFs -> ALU -> this bypass mux -> A_*_DT FFs"
//       are candidates for the longest paths of this CPU (check a timing report for which one really is).
//       In the synthesis result, LUT6s such as A_EX_OP1_DT[i]_i_2 line up several levels deep for each bit.
//     - During A_INTLK the values are mostly held (CE), but there is a path that takes in the load
//       data etc. that A was waiting for, so A_*_DT are not simple FFs with CE and a mux remains.
// ---------------------------------------------------------------------

// d-dat

// 【解説】各オペランドがレジスタから来るか。インタロック中のバイパス判定と
//         A_EAB (060_g_srq.vh) に使う。
// [Note] Does each operand come from a register? Used for the bypass decision during an interlock
//        and for A_EAB (060_g_srq.vh).
assign A_LS_OPB_IS_GR_NEW = A_INTLK ? A_LS_OPB_IS_GR  :
	D_FWD ? DD_FIRST_RADB_V | DD_ISSUE_SECOND_INSN & DD_SECOND_RADB_V : 0;
assign A_EX_OP1_IS_GR_NEW = A_INTLK ? A_EX_OP1_IS_GR  :
	D_FWD ? DD_FIRST_RAD1_V | DD_ISSUE_SECOND_INSN & DD_SECOND_RAD1_V : 0;
assign A_EX_OP2_IS_GR_NEW = A_INTLK ? A_EX_OP2_IS_GR  :
	D_FWD ? DD_FIRST_RAD2_V | DD_ISSUE_SECOND_INSN & DD_SECOND_RAD2_V : 0;


// 【解説】リンク付き分岐の戻り番地 = 分岐命令の番地 + 4。
//         PART1 (32bit) と PART2+4 (6bit) に分けて EXU に渡し、AU で足す。
// [Note] Return address of a branch with link = address of the branch + 4.
//        It is passed to the EXU in two parts, PART1 (32 bits) and PART2+4 (6 bits), and added by AU.
assign DD_JB_INSN_AD_PART2P4 = add4_5(DD_JB_INSN_AD_PART2);   // ... + 4

// ---- #if 0 (元ソースで無効化) ----
//      (#if 0: disabled in the original source)
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
//      (#else: this is the version in effect)
// 【解説】LS パイプのベースレジスタの値 (アドレス計算用)。
// [Note] Value of the LS-pipe base register (for the address computation).
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
// [Note] First operand of the EX pipe. For a branch with link,
//        the low part of the return address, PART2+4, sign-extended.
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
// [Note] Second operand of the EX pipe. The immediate (sign-extended) in RI mode,
//        PART1 for a branch with link.
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
// [Note] The register numbers read are passed to A (for the bypass decision during an interlock).
assign A_LS_RADB_NEW = A_INTLK ? A_LS_RADB : DD_RADB;

assign A_EX_RAD1_NEW = A_INTLK ? A_EX_RAD1 : DD_RAD1;

assign A_EX_RAD2_NEW = A_INTLK ? A_EX_RAD2 : DD_RAD2;

// 【解説】アドレス計算用の変位。
// [Note] Displacement for the address computation.
assign A_DISP_NEW = A_INTLK ? A_DISP    : DD_DISP;
