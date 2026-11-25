// =====================================================================
//  210_g_bc.vh  <-  hard/210-g-bc.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】条件分岐 (BC) のグローバル状態
//
// G_BC_PENDING       : 未解決の BC がある (同時に 1 つまで)
// G_BC_MASK          : その BC の条件マスク
// G_BC_TKN_PREDICTED : taken と予測したか
// G_BC_JUST_SOLVED   : 前のサイクルで解決した (1 サイクルだけ 1)
// G_BC_JUST_TAKEN    : 解決した結果 taken だった
// JUST_SOLVED の次のサイクルで、予測と結果が違えば CANCEL_BY_BC (050) で
// 投機的に発行した命令を取り消し、EID (010) でもう一方のキューへ切り替える。
//
// [Note] Global state of conditional branches (BC)
//
// G_BC_PENDING       : there is an unresolved BC (at most one at a time)
// G_BC_MASK          : the condition mask of that BC
// G_BC_TKN_PREDICTED : whether it was predicted taken
// G_BC_JUST_SOLVED   : it was resolved in the previous cycle (1 for one cycle only)
// G_BC_JUST_TAKEN    : the outcome of the resolution was taken
// In the cycle after JUST_SOLVED, if prediction and outcome differ, CANCEL_BY_BC (050)
// cancels the speculatively issued instructions and EID (010) switches to the other queue.
//
// 【ネットリスト解説】
//   入力 : E_FWD / A_FWD / D_FWD (070), E_LS_SOLVING_BC (110), A_EX_SOLVING_BC (150),
//          DD_ISSUEING_UNSOLVED_BC / _ON_E_LS / _ON_A_EX / DD_PREDICTING_TAKEN (040),
//          EE_ALU_CC (090 の ALU), AA_EXU_CC (120 の EXU), IJB_RD_MASK (035),
//          WW_INTERRUPTION (050)
//   出力 (FF, 合計 8 本): G_BC_JUST_SOLVED -> 010, 050, 110, 130, 150, 160
//                         G_BC_JUST_TAKEN  -> 010, 050, 090, 110, 130, 150
//                         G_BC_TKN_PREDICTED -> 010, 050 ;  G_BC_PENDING -> 030, 070, 150
//                         G_BC_MASK (4bit) -> 090
//   回路の形:
//     ・FF はわずか 8 本だが、G_BC_JUST_SOLVED / _TAKEN は全ステージの分岐タグと
//       S ユニットの SUBJECT_TO_BC の更新に入るので、ファンアウトの大きい FF。
//     ・G_BC_JUST_TAKEN_NEW は「ALU / EXU の CC → cc_match (4:1 MUX)」で、
//       E の FF → ALU (加減算) → CC → この FF、という経路が E サイクルにできる。
//     ・解決結果を 1 度 FF (JUST_SOLVED / JUST_TAKEN) に受けてから次のサイクルに
//       取り消し (CANCEL_BY_BC) とキュー切り替え (EID) を行う設計なので、
//       ALU の CC が全ステージの取り消しへ同じサイクルで伝わる長い経路は無い
//       (その代わり、取り消しは解決の 1 サイクル後になる。元ソースに意図の説明は無い)。
//
// [Netlist notes]
//   Inputs : E_FWD / A_FWD / D_FWD (070), E_LS_SOLVING_BC (110), A_EX_SOLVING_BC (150),
//            DD_ISSUEING_UNSOLVED_BC / _ON_E_LS / _ON_A_EX / DD_PREDICTING_TAKEN (040),
//            EE_ALU_CC (ALU in 090), AA_EXU_CC (EXU in 120), IJB_RD_MASK (035),
//            WW_INTERRUPTION (050)
//   Outputs (FFs, 8 in total): G_BC_JUST_SOLVED -> 010, 050, 110, 130, 150, 160
//                              G_BC_JUST_TAKEN  -> 010, 050, 090, 110, 130, 150
//                              G_BC_TKN_PREDICTED -> 010, 050 ;  G_BC_PENDING -> 030, 070, 150
//                              G_BC_MASK (4 bits) -> 090
//   Circuit:
//     - Only 8 FFs, but G_BC_JUST_SOLVED / _TAKEN feed the updates of the branch tags of every
//       stage and of SUBJECT_TO_BC in the S unit, so they are FFs with large fan-out.
//     - G_BC_JUST_TAKEN_NEW is "CC of the ALU / EXU -> cc_match (4:1 mux)", which makes the
//       path E FFs -> ALU (add/sub) -> CC -> this FF in the E cycle.
//     - The resolution is first latched in FFs (JUST_SOLVED / JUST_TAKEN), and cancellation
//       (CANCEL_BY_BC) and queue switching (EID) happen in the next cycle. So there is no long
//       path carrying the ALU's CC to the cancellation of every stage in the same cycle
//       (in exchange, cancellation happens 1 cycle after resolution; the original source does
//       not explain the intent).
// ---------------------------------------------------------------------

// g-bc :
// global FF's, whose effects are not limited to any single pipeline stages


// In the cycle where BC is being solved (i.e. cycle with SOLVING-BC),
// G-BC-PENDING is turned off and G-BC-JUST-TAKEN/SOLVED is set.

// If D-cyc is issueing BC, the A- or E-cyc which sets CC for that BC
// is treated just as having SOLVING-BC.


// 【解説】このサイクルに BC が解決するか: CC を作る命令が E (LS パイプ) か
//         A (EX パイプ) から進むとき。D で BC を発行したのと同じサイクルに
//         その命令が A/E にいる場合も含む。
// [Note] Is a BC resolved in this cycle: when the instruction making the CC moves on from E (LS pipe)
//        or A (EX pipe). This includes the case where that instruction is in A/E in the same cycle
//        the BC is issued in D.
assign GG_SOLVING_CASE_ON_E = 
     E_FWD & (E_LS_SOLVING_BC | D_FWD & DD_ISSUEING_UNSOLVED_BC_ON_E_LS);
assign GG_SOLVING_CASE_ON_A = 
     A_FWD & (A_EX_SOLVING_BC | D_FWD & DD_ISSUEING_UNSOLVED_BC_ON_A_EX);
assign GG_SOLVING_CASE = GG_SOLVING_CASE_ON_E | GG_SOLVING_CASE_ON_A;

// 【解説】解決に使うマスクと CC (同じサイクルに発行した BC なら IJB のマスク)。
// [Note] Mask and CC used for the resolution (the mask of IJB for a BC issued in the same cycle).
assign GG_MASK_FOR_BC = (E_LS_SOLVING_BC | A_EX_SOLVING_BC) ? G_BC_MASK : IJB_RD_MASK;
assign GG_CC_FOR_BC = (GG_SOLVING_CASE_ON_E ? EE_ALU_CC : AA_EXU_CC );

// 【解説】D で未解決の BC を発行した。
// [Note] An unresolved BC was issued in D.
assign GG_ISSUEING_CASE = D_FWD & DD_ISSUEING_UNSOLVED_BC;



// 【解説】未解決 BC の有無: 発行で 1, 解決か割り込みで 0。
// [Note] Is there an unresolved BC: 1 on issue, 0 on resolution or interrupt.
assign G_BC_PENDING_NEW = WW_INTERRUPTION | GG_SOLVING_CASE ? 0 : GG_ISSUEING_CASE ? 1 :
							G_BC_PENDING;
// 【解説】解決したサイクルの次に 1 サイクルだけ 1。taken かどうかも記録。
// [Note] 1 for one cycle only, the cycle after resolution. Whether it was taken is recorded too.
assign G_BC_JUST_SOLVED_NEW = WW_INTERRUPTION ? 0 : GG_SOLVING_CASE ? 1 : 0;

assign G_BC_JUST_TAKEN_NEW = WW_INTERRUPTION ? 0 :
		GG_SOLVING_CASE ? cc_match(GG_CC_FOR_BC , GG_MASK_FOR_BC) : 0;

// 【解説】発行時の予測とマスクを覚えておく。
// [Note] Remember the prediction and the mask at issue.
assign G_BC_TKN_PREDICTED_NEW = 
		GG_ISSUEING_CASE ? DD_PREDICTING_TAKEN : G_BC_TKN_PREDICTED;

assign G_BC_MASK_NEW = 	GG_ISSUEING_CASE ? IJB_RD_MASK         : G_BC_MASK;
