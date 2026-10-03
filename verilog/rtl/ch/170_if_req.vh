// =====================================================================
//  170_if_req.vh  <-  hard/170-if-req.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】命令フェッチ要求 (IF) の生成
//
// 命令は 8 バイト (2 命令) 単位でフェッチし、キュー A/B のどちらに入れるかを
// ID (0=A, 1=B) で区別する。要求の理由 (IF_CASE_*) は優先順に
//   START : 割り込み等からの再スタート → PC から
//   J     : レジスタ間接分岐 → A サイクルの EAG が出した番地
//   NULL  : レジスタ間接分岐を D で発行中 (番地はまだ不明なので要求しない)
//   BA/BC : PC 相対分岐 → 分岐先 DD_TGT (未解決 BC は「もう一方の」キューへ)
//   通常  : キューに空きがあれば続きの 8 バイト
// ---------------------------------------------------------------------

// if-req


// Insn Fetch Request


// IWQ-FULL

// 【解説】キューが満杯 (6 語とも有効で, まだ先頭付近を実行中)。
assign IWQ_FULL = (NIP_0 | NIP_1) & V01 & V23 & V45;

// IF-REQ-V/AD/ID decision

// 【解説】続きのフェッチ番地 = 最後に要求した番地 + 8。
//         要求中のもの (IB) がこのキュー宛てならその番地から, なければキュー末尾の番地から。
assign IF_INCR_1 = IB_V & (EID == IB_ID) ? IB_AD : EID ? D_IF_AD_B : D_IF_AD_A;
assign IF_INCR_2 = IB_V & (EID == IB_ID)
		 | NIP_0 | NIP_1 | NIP_2 | NIP_3 | NIP_4 | NIP_5  ? 8 : 0;
// ---- #ifndef VHDL (C シミュレータ版を採用) ----
assign IF_INCR_OUT = add_32_4(IF_INCR_1,IF_INCR_2);
// ---- #endif ----

// 【解説】フェッチ要求の理由 (上の説明を参照)。
assign IF_CASE_START = START_TRIGGER;
assign IF_CASE_J = A_V_NOCAN & A_SET_EAG_TO_TGT;
assign IF_CASE_BA = DD_ISSUEING_TAKEN_BRANCH;
assign IF_CASE_BC = DD_ISSUEING_UNSOLVED_BC;
assign IF_CASE_NULL = IJB_IS_JA | IJB_IS_JL;

// 【解説】フェッチ要求を出すか (分岐系は D/A が進めるときだけ)。
assign IF_REQ_V = IF_CASE_START ? 1 : IF_CASE_J ? A_FWD : IF_CASE_NULL ? 0 :
	    IF_CASE_BA | IF_CASE_BC ? D_FWD : ! IWQ_FULL;

// 【解説】フェッチ番地。
assign IF_REQ_AD = IF_CASE_START ? PC : IF_CASE_J ? AA_EAG_OUTPUT :
	    IF_CASE_BA | IF_CASE_BC ? DD_TGT : IF_INCR_OUT;

// 【解説】どちらのキューへ入れるか。未解決 BC の分岐先はもう一方のキューへ。
assign IF_REQ_ID = IF_CASE_START ?  0 : IF_CASE_BC ? !EID  : EID;

// 【解説】要求中のフェッチが無駄になったので取り消す (分岐した, 再スタート)。
assign CANCEL_IB = IF_CASE_START | (IF_CASE_BA | IF_CASE_NULL) & (IB_ID == EID);
