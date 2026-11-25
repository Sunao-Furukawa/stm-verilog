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
//
// [Note] D cycle (6): branch handling
//
// - computes the address of the branch itself and the branch target DD_TGT
// - decides the kind of branch (BA/JA/BL/JL/BC)
// - a conditional branch (BC) is decided taken/untaken right here if the CC it needs is
//   already settled ("resolved"). If an earlier instruction is still computing the CC, it is
//   "unresolved": execution goes on by prediction, and the answer is checked where the CC
//   comes out (A or E cycle) (210_g_bc.vh). The prediction is static: "backward means taken".
//
// 【ネットリスト解説】
//   入力 : IJB_* / ILS_* (035), IJB_V (030), DD_FIRST_* / DD_SECOND_IS_JB (020),
//          EID / NIP / V45 (010), D_IF_AD_A/B (190 の FF),
//          A/B/E の *_SETCC と B/E の *_EX_CC (130, 110, 150 の FF),
//          W_SETCC / W_CC (090 の FF), PSW_CC (080 の FF)
//   出力 : DD_TGT                         -> 150 (A_TGT), 170 (フェッチ番地)
//          DD_ISSUEING_TAKEN_BRANCH        -> 170
//          DD_ISSUEING_UNSOLVED_BC         -> 070, 150, 170, 190, 210
//          DD_ISSUEING_UNTAKEN_BC          -> 150, 190
//          DD_ISSUEING_UNSOLVED_BC_ON_*    -> 110, 130, 150, 210 (どこで解決するか)
//          DD_PREDICTING_TAKEN             -> 190, 210
//          DD_DISP                         -> 140 (A_DISP)
//          DD_JB_INSN_AD_PART1 / PART2     -> 140 (リンクの戻り番地)
//          IJB_IS_JA / IJB_IS_JL           -> 170
//   回路の形:
//     ・DD_TGT は 32bit の 3 入力加算器 (add_32_5_20)。このファイルで唯一の
//       キャリー連鎖。入力の PART2 は NIP / V45 から LUT で作る 6bit 値。
//     ・DD_CC_FOR_SOLVED_BC は B → E → W → PSW の 4 段の優先 MUX (2bit 幅) で、
//       これが cc_match (4:1 MUX) を通って DD_SOLVED_BC_TAKEN になる。
//       「CC のフォワーディング」をする回路そのもの。
//     ・DD_ISSUEING_* は AND/OR の論理だが、170 のフェッチ要求 (IF_REQ_*) と
//       190 の NIP / キュー切り替えに直接入るので、命令フェッチ側の長い経路になる。
//
// [Netlist notes]
//   Inputs : IJB_* / ILS_* (035), IJB_V (030), DD_FIRST_* / DD_SECOND_IS_JB (020),
//            EID / NIP / V45 (010), D_IF_AD_A/B (FFs in 190),
//            *_SETCC of A/B/E and *_EX_CC of B/E (FFs in 130, 110, 150),
//            W_SETCC / W_CC (FFs in 090), PSW_CC (FF in 080)
//   Outputs: DD_TGT                         -> 150 (A_TGT), 170 (fetch address)
//            DD_ISSUEING_TAKEN_BRANCH        -> 170
//            DD_ISSUEING_UNSOLVED_BC         -> 070, 150, 170, 190, 210
//            DD_ISSUEING_UNTAKEN_BC          -> 150, 190
//            DD_ISSUEING_UNSOLVED_BC_ON_*    -> 110, 130, 150, 210 (where it is resolved)
//            DD_PREDICTING_TAKEN             -> 190, 210
//            DD_DISP                         -> 140 (A_DISP)
//            DD_JB_INSN_AD_PART1 / PART2     -> 140 (return address of a link)
//            IJB_IS_JA / IJB_IS_JL           -> 170
//   Circuit:
//     - DD_TGT is a 32-bit 3-input adder (add_32_5_20), the only carry chain in this file.
//       Its input PART2 is a 6-bit value made with LUTs from NIP / V45.
//     - DD_CC_FOR_SOLVED_BC is a 4-level priority mux (2 bits wide) B -> E -> W -> PSW, and
//       it goes through cc_match (a 4:1 mux) to become DD_SOLVED_BC_TAKEN.
//       This is the circuit that does "CC forwarding".
//     - DD_ISSUEING_* are plain AND/OR logic, but they go straight into the fetch request
//       (IF_REQ_*) in 170 and the NIP / queue switching in 190, so they form the long paths
//       on the instruction-fetch side.
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
//
// [Note] The branch's own address is computed in two parts.
//          PART1 : fetch address of the last 8 bytes put into the queue (D_IF_AD_x, 8-byte aligned)
//          PART2 : the position relative to it (6 bits, signed)
//                    = -(V45 ? 16 : 8) + 4 * NIP + (+4 if the branch is the second instruction)
//                   (if entries 4,5 are filled the last 8 bytes are in 4,5, if empty in 2,3)
assign DD_JB_INSN_AD_PART1 = EID ? D_IF_AD_B & 32'hfffffff8 : D_IF_AD_A & 32'hfffffff8;
//DD-JB-INSN-AD-PART2 = MINUS1*(V45 ? 16 : 8) + 4*NIP + (DD-FIRST-IS-JB ? 0 : 4)
assign DD_JB_INSN_AD_PART2 = add_4_5_3(V45,NIP,DD_FIRST_IS_JB);

// Kind of JB-insn (BA/JA/BL/JL/BC)

// 【解説】分岐の種類:
//           BA : 無条件・PC 相対        JA : 無条件・レジスタ間接
//           BL : リンク付き・PC 相対    JL : リンク付き・レジスタ間接
//           BC : 条件分岐
//
// [Note] Kinds of branch:
//          BA : unconditional, PC-relative      JA : unconditional, register-indirect
//          BL : with link, PC-relative          JL : with link, register-indirect
//          BC : conditional branch
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
// [Note] Is the CC for the BC being issued already settled?
//        It is if no instruction that changes CC is left in A (EX/LS), B (LS) or E (LS).
//        The EX result in B, the EX result in E and W are already computed, so the forwarding below can use them.
assign DD_ISSUEING_SOLVED_BC = !(A_EX_SETCC | A_LS_SETCC | B_LS_SETCC | E_LS_SETCC
			   | DD_FIRST_SETCC & DD_SECOND_IS_JB) & IJB_IS_BC;
// 【解説】確定済みの最新 CC (新しい順に B の EX 結果 → E → W → PSW)。
// [Note] The latest settled CC (newest first: EX result in B -> E -> W -> PSW).
assign DD_CC_FOR_SOLVED_BC = (B_EX_SETCC ? B_EX_CC :
			  (E_EX_SETCC ? E_EX_CC : (W_SETCC ? W_CC : PSW_CC) ) );
assign DD_SOLVED_BC_TAKEN = cc_match(DD_CC_FOR_SOLVED_BC,IJB_RD_MASK);
// 【解説】D サイクルで taken が確定する分岐 (解決済み BC で成立, BA, BL)。
// [Note] Branches known to be taken in the D cycle (a resolved BC that holds, BA, BL).
assign DD_ISSUEING_TAKEN_BRANCH = DD_SOLVED_BC_TAKEN & DD_ISSUEING_SOLVED_BC
               | IJB_IS_BA | IJB_IS_BL;
assign DD_ISSUEING_UNTAKEN_BC = !DD_SOLVED_BC_TAKEN & DD_ISSUEING_SOLVED_BC;

// 【解説】未解決の条件分岐 (予測で進める)。
// [Note] An unresolved conditional branch (goes on by prediction).
assign DD_ISSUEING_UNSOLVED_BC =  !DD_ISSUEING_SOLVED_BC & IJB_IS_BC;

// 【解説】未解決 BC の CC を作る命令がどこにいるか (そこで解決される):
//           ON_D_EX / ON_D_LS : 同時発行した 1 命令目 (EX / LS パイプ)
//           ON_A_EX / ON_A_LS / ON_B_LS / ON_E_LS : 先行してそのステージにいる命令
// [Note] Where is the instruction that makes the CC of the unresolved BC (it is resolved there):
//          ON_D_EX / ON_D_LS : the first instruction issued together with it (EX / LS pipe)
//          ON_A_EX / ON_A_LS / ON_B_LS / ON_E_LS : an earlier instruction in that stage
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
// [Note] Static branch prediction: a backward branch (negative displacement) is predicted taken (good for loops).
assign DD_PREDICTING_TAKEN = DD_ISSUEING_UNSOLVED_BC & IJB_BACKWARD;
// 【解説】A サイクルのアドレス加算器 (EAG) に渡す変位 16bit。
//         LS 命令は DISP16, EX-RM は DISP12 を符号拡張, レジスタ間接分岐は IMM16。
// [Note] The 16-bit displacement given to the address adder (EAG) of the A cycle.
//        DISP16 for LS instructions, DISP12 sign-extended for EX-RM, IMM16 for register-indirect branches.
assign DD_DISP = ILS_LS_FMT   ? ILS_DISP16 :
		ILS_EXRM_FMT ? sign_ext_12(ILS_DISP12) : IJB_IMM16;
// ---- #ifndef VHDL (C シミュレータ版を採用) ----
// 【解説】PC 相対分岐の分岐先 = 分岐命令のアドレス (PART1+PART2) + IMM20 (符号拡張)。
// [Note] Target of a PC-relative branch = address of the branch (PART1+PART2) + IMM20 (sign-extended).
assign DD_TGT = add_32_5_20(DD_JB_INSN_AD_PART1,DD_JB_INSN_AD_PART2,IJB_IMM20);
//# + (IJB-CMP ? sign-ext(12,IJB-IMM12) : sign-ext(20,jb-imm20(IJB)))
// ---- #endif ----
