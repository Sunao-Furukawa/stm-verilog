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
assign GG_SOLVING_CASE_ON_E = 
     E_FWD & (E_LS_SOLVING_BC | D_FWD & DD_ISSUEING_UNSOLVED_BC_ON_E_LS);
assign GG_SOLVING_CASE_ON_A = 
     A_FWD & (A_EX_SOLVING_BC | D_FWD & DD_ISSUEING_UNSOLVED_BC_ON_A_EX);
assign GG_SOLVING_CASE = GG_SOLVING_CASE_ON_E | GG_SOLVING_CASE_ON_A;

// 【解説】解決に使うマスクと CC (同じサイクルに発行した BC なら IJB のマスク)。
assign GG_MASK_FOR_BC = (E_LS_SOLVING_BC | A_EX_SOLVING_BC) ? G_BC_MASK : IJB_RD_MASK;
assign GG_CC_FOR_BC = (GG_SOLVING_CASE_ON_E ? EE_ALU_CC : AA_EXU_CC );

// 【解説】D で未解決の BC を発行した。
assign GG_ISSUEING_CASE = D_FWD & DD_ISSUEING_UNSOLVED_BC;



// 【解説】未解決 BC の有無: 発行で 1, 解決か割り込みで 0。
assign G_BC_PENDING_NEW = WW_INTERRUPTION | GG_SOLVING_CASE ? 0 : GG_ISSUEING_CASE ? 1 :
							G_BC_PENDING;
// 【解説】解決したサイクルの次に 1 サイクルだけ 1。taken かどうかも記録。
assign G_BC_JUST_SOLVED_NEW = WW_INTERRUPTION ? 0 : GG_SOLVING_CASE ? 1 : 0;

assign G_BC_JUST_TAKEN_NEW = WW_INTERRUPTION ? 0 :
		GG_SOLVING_CASE ? cc_match(GG_CC_FOR_BC , GG_MASK_FOR_BC) : 0;

// 【解説】発行時の予測とマスクを覚えておく。
assign G_BC_TKN_PREDICTED_NEW = 
		GG_ISSUEING_CASE ? DD_PREDICTING_TAKEN : G_BC_TKN_PREDICTED;

assign G_BC_MASK_NEW = 	GG_ISSUEING_CASE ? IJB_RD_MASK         : G_BC_MASK;
