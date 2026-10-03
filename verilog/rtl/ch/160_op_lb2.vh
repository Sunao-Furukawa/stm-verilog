// =====================================================================
//  160_op_lb2.vh  <-  hard/160-op-lb2.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】S ユニットの次状態
//
// S ユニットには 2 段の要求置き場がある:
//   OP-B    : キャッシュにアクセス中の要求 (LBS_AD/LBS_DT/LBS_WE がメモリへ出る)
//   OP-WAIT : OP-B が終わらないうちに受け付けた次の要求を 1 つ待たせる
// 要求の種類 (OPC) は LD / ST / ST2 (050_op_lb1.vh 参照)。
// ---------------------------------------------------------------------

// OP-LBS in S-Unit : determine next state

// SU priority
// B-LS-LOG-AD should be later replaced by LBS-AD, when DAT is implemented.

// 【解説】OP-B の要求が終わる (ST2 は 1 サイクルで終わる, L/ST はキャッシュヒットで終わる)。
assign OP_B_FORWARDING = (OP_B_OPC == SU_OPC_ST2) | B_OPCLH;
// 【解説】このサイクルに受け付ける要求 (A からの L/ST か, STB からの ST2) の種類と番地。
assign GO_SU = AA_LD_GO|WW_ST_GO;

assign ACCEPTING_OPC = (WW_ST_GO ? SU_OPC_ST2 : (A_LS_ST_V?SU_OPC_ST:SU_OPC_LD));
assign ACCEPTING_AD = (WW_ST_GO ? STB_AD : AA_EAG_OUTPUT);

// WAIT state : stay/accept from IU/clear

// 【解説】OP-WAIT の動き:
//           STAYS  : OP-B がまだ終わらず, 待ち中の要求もそのまま待つ
//           ACCEPT : OP-B が終わらないうちに新しい要求を受け付けた → OP-WAIT に入れる
assign OP_WAIT_STAYS = OP_B_V_NOCAN & !OP_B_FORWARDING & OP_WAIT_V_NOCAN;
assign OP_WAIT_ACCEPT = OP_B_V_NOCAN & !OP_B_FORWARDING & GO_SU;


assign OP_WAIT_V_NEW = OP_WAIT_STAYS ? OP_WAIT_V   : OP_WAIT_ACCEPT ? 1 : 0;
assign OP_WAIT_OPC_NEW = OP_WAIT_STAYS ? OP_WAIT_OPC : ACCEPTING_OPC;
assign OP_WAIT_WE_NEW = OP_WAIT_STAYS ? OP_WAIT_WE  : OP_WAIT_ACCEPT ? WW_ST_GO : 0;
assign OP_WAIT_AD_NEW = OP_WAIT_STAYS ? OP_WAIT_AD  : ACCEPTING_AD;
assign OP_WAIT_DT_NEW = OP_WAIT_STAYS ? OP_WAIT_DT  : STB_DT;

// 【解説】投機的な (予測ミスで取り消される) 要求かどうか。
assign OP_WAIT_SUBJECT_TO_BC_NEW = OP_WAIT_STAYS ?
				OP_WAIT_SUBJECT_TO_BC & !G_BC_JUST_SOLVED :
	OP_WAIT_ACCEPT ?  AA_LD_GO & A_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED : 0;


//  OP-B state : stay/accept from IU/shift from WAIT/clear

// 【解説】OP-B の動き: 終わらなければ留まる / OP-WAIT から移す /
//         新しく受け付けた要求を入れる。
assign OP_B_STAYS = OP_B_V_NOCAN & !OP_B_FORWARDING;
//OP-B-ACCEPT	= GO-SU
assign OP_B_SHIFT = OP_WAIT_V_NOCAN;


assign OP_B_V_NEW = OP_B_STAYS ? OP_B_V   : OP_B_SHIFT ? 1           : GO_SU;
assign OP_B_OPC_NEW = OP_B_STAYS ? OP_B_OPC : OP_B_SHIFT ? OP_WAIT_OPC : ACCEPTING_OPC;
// 【解説】メモリ (キャッシュ) への書き込み許可・番地・データ。
assign LBS_WE_NEW = OP_B_STAYS ? LBS_WE   : OP_B_SHIFT ? OP_WAIT_WE  : WW_ST_GO;
assign LBS_AD_NEW = OP_B_STAYS ? LBS_AD   : OP_B_SHIFT ? OP_WAIT_AD  :
	    GO_SU      ? ACCEPTING_AD : 0;
assign LBS_DT_NEW = OP_B_STAYS ? LBS_DT   : OP_B_SHIFT ? OP_WAIT_DT  : STB_DT;

assign OP_B_SUBJECT_TO_BC_NEW = 
	    OP_B_STAYS ? OP_B_SUBJECT_TO_BC & !G_BC_JUST_SOLVED    :
	    OP_B_SHIFT ? OP_WAIT_SUBJECT_TO_BC & !G_BC_JUST_SOLVED :
			 AA_LD_GO & A_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED;
