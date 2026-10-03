// =====================================================================
//  040_d_bra.vh  <-  hard/040-d-bra.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】D サイクル(6): 分岐命令の処理
//
// ・分岐命令自身のアドレスと分岐先アドレス DD_TGT の計算
// ・分岐の種類 (BA/JA/BL/JL/BC) の判定
// ・条件分岐 (BC) は、必要な CC がもう確定していればこの場で taken/untaken を
//   決める (「解決済み」)。まだ先行命令が CC を計算中なら「未解決」として
//   予測で先に進み、CC が出た所 (A または E サイクル) で答え合わせをする
//   (210_g_bc.vh)。予測は「後方分岐なら taken」という静的予測。
// ---------------------------------------------------------------------

// d-bra: D-cycle, issueing branch insn

// Address of branch insn
//      NIP -+                                                              #
//           v    IWQ-*                                                     #
//       +---+---+---+---+---+---+      D-IF-AD-*                           #
//       |X-16   |   |   |X  |   |     +------+                             #
//       |X-8|   |X  |   |   |   |     |  X   |                             #
//       +---+---+---+---+---+---+     +------+                             #
//        o       o       o               |                                 #
//                A(!V45) A(V45)          |                                 #
//                +-------+---------------+                                 #

// 【解説】分岐命令のアドレスを 2 つに分けて計算する。
//           PART1 : キューに最後に入れた 8 バイトのフェッチ番地 (D_IF_AD_x, 8 バイト境界)
//           PART2 : そこからの相対位置 (6bit 符号付き)
//                     = -(V45 ? 16 : 8) + 4 * NIP + (分岐が 2 命令目なら +4)
//                    (4,5 番が埋まっていれば最後の 8 バイトは 4,5 番, 空なら 2,3 番にある)
assign DD_JB_INSN_AD_PART1 = EID ? D_IF_AD_B & 32'hfffffff8 : D_IF_AD_A & 32'hfffffff8;
//DD-JB-INSN-AD-PART2 = MINUS1*(V45 ? 16 : 8) + 4*NIP + (DD-FIRST-IS-JB ? 0 : 4)
assign DD_JB_INSN_AD_PART2 = add_4_5_3(V45,NIP,DD_FIRST_IS_JB);

// Kind of JB-insn (BA/JA/BL/JL/BC)

// 【解説】分岐の種類:
//           BA : 無条件・PC 相対        JA : 無条件・レジスタ間接
//           BL : リンク付き・PC 相対    JL : リンク付き・レジスタ間接
//           BC : 条件分岐
assign IJB_IS_BA = IJB_V & !IJB_COND & !IJB_LINK & !IJB_REG;
assign IJB_IS_JA = IJB_V & !IJB_COND & !IJB_LINK &  IJB_REG;
assign IJB_IS_BL = IJB_V &   IJB_LINK & !IJB_REG;
assign IJB_IS_JL = IJB_V &   IJB_LINK &  IJB_REG;
assign IJB_IS_BC = IJB_V &   IJB_COND;
//###  IJB-IS-CMP = ...  !!!!!

// If BC, has it been solved?  Which stage decides CC ?

//         D   |   A   |   B   |   E   |    W                       #
//             |       |       |       |                            #
//   LS        |  uns  |  uns  |   +   |                            #
//             |       |       |       |  sol                       #
//   EX        |   +   |  sol  |  sol  |                            #

assign DD_SETCC = DD_FIRST_SETCC;
// 			 | IJB-IS-CMP !!!!!
// 【解説】発行しようとしている BC の CC がもう確定しているか。
//         A (EX/LS), B (LS), E (LS) に CC を変える命令が残っていなければ確定済み。
//         B の EX, E の EX, W の結果はもう計算済みなので下のフォワーディングで使える。
assign DD_ISSUEING_SOLVED_BC = !(A_EX_SETCC | A_LS_SETCC | B_LS_SETCC | E_LS_SETCC
			   | DD_FIRST_SETCC & DD_SECOND_IS_JB) & IJB_IS_BC;
// 【解説】確定済みの最新 CC (新しい順に B の EX 結果 → E → W → PSW)。
assign DD_CC_FOR_SOLVED_BC = (B_EX_SETCC ? B_EX_CC :
			  (E_EX_SETCC ? E_EX_CC : (W_SETCC ? W_CC : PSW_CC) ) );
assign DD_SOLVED_BC_TAKEN = cc_match(DD_CC_FOR_SOLVED_BC,IJB_RD_MASK);
// 【解説】D サイクルで taken が確定する分岐 (解決済み BC で成立, BA, BL)。
assign DD_ISSUEING_TAKEN_BRANCH = DD_SOLVED_BC_TAKEN & DD_ISSUEING_SOLVED_BC
               | IJB_IS_BA | IJB_IS_BL;
assign DD_ISSUEING_UNTAKEN_BC = !DD_SOLVED_BC_TAKEN & DD_ISSUEING_SOLVED_BC;

// 【解説】未解決の条件分岐 (予測で進める)。
assign DD_ISSUEING_UNSOLVED_BC =  !DD_ISSUEING_SOLVED_BC & IJB_IS_BC;

// 【解説】未解決 BC の CC を作る命令がどこにいるか (そこで解決される):
//           ON_D_EX / ON_D_LS : 同時発行した 1 命令目 (EX / LS パイプ)
//           ON_A_EX / ON_A_LS / ON_B_LS / ON_E_LS : 先行してそのステージにいる命令
assign DD_ISSUEING_UNSOLVED_BC_ON_D_EX =  DD_FIRST_SETCC & DD_SECOND_IS_JB
				  & DD_FIRST_IS_EX & IJB_IS_BC;
// 				 | IJB-IS-CMP  !!!!!
assign DD_ISSUEING_UNSOLVED_BC_ON_D_LS =  DD_FIRST_SETCC & DD_SECOND_IS_JB
				  & DD_FIRST_IS_LS & IJB_IS_BC;
assign DD_ISSUEING_UNSOLVED_BC_ON_A_EX =  !DD_SETCC & A_EX_SETCC & IJB_IS_BC;
assign DD_ISSUEING_UNSOLVED_BC_ON_A_LS =  !DD_SETCC & A_LS_SETCC & IJB_IS_BC;
assign DD_ISSUEING_UNSOLVED_BC_ON_B_LS =  !DD_SETCC & !A_LS_SETCC & !A_EX_SETCC
					& B_LS_SETCC & IJB_IS_BC;
assign DD_ISSUEING_UNSOLVED_BC_ON_E_LS =  !DD_SETCC & !A_LS_SETCC & !A_EX_SETCC
					& !B_LS_SETCC & E_LS_SETCC & IJB_IS_BC;
// branch prediction : backward branch <-> TKN predicted
// 【解説】静的分岐予測: 後方分岐 (変位が負) なら taken と予測する (ループ向け)。
assign DD_PREDICTING_TAKEN = DD_ISSUEING_UNSOLVED_BC & IJB_BACKWARD;
// 【解説】A サイクルのアドレス加算器 (EAG) に渡す変位 16bit。
//         LS 命令は DISP16, EX-RM は DISP12 を符号拡張, レジスタ間接分岐は IMM16。
assign DD_DISP = ILS_LS_FMT   ? ILS_DISP16 :
		ILS_EXRM_FMT ? sign_ext_12(ILS_DISP12) : IJB_IMM16;
// ---- #ifndef VHDL (C シミュレータ版を採用) ----
// 【解説】PC 相対分岐の分岐先 = 分岐命令のアドレス (PART1+PART2) + IMM20 (符号拡張)。
assign DD_TGT = add_32_5_20(DD_JB_INSN_AD_PART1,DD_JB_INSN_AD_PART2,IJB_IMM20);
//# + (IJB-CMP ? sign-ext(12,IJB-IMM12) : sign-ext(20,jb-imm20(IJB)))
// ---- #endif ----
