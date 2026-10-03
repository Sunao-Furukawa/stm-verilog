// =====================================================================
//  130_a_act.vh  <-  hard/130-a-act.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】A → B の状態遷移
//
// 110_b_act.vh と同じ考え方で、A の命令が進めば (A_FWD) タグを B へ移し、
// B がインタロック中なら保持し、それ以外は有効ビットを 0 にする。
// ---------------------------------------------------------------------

// a-act

// 【解説】B の有効ビット: A から来るか, B が留まるか。
assign B_V_NEW = A_FWD | B_INTLK;

// 【解説】分岐関係のタグ (110_b_act.vh と同じく分岐解決で更新)。
assign B_JB_IS_BC_NEW = A_FWD   ? A_JB_IS_BC & !G_BC_JUST_SOLVED :
			B_INTLK ? B_JB_IS_BC & !G_BC_JUST_SOLVED : 0;
assign B_JB_SUBJECT_TO_BC_NEW = A_FWD   ? A_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED :
			B_INTLK ? B_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED : 0;
assign B_JB_V_NEW = 
    A_FWD   ? A_JB_V & !(A_JB_IS_BC & G_BC_JUST_SOLVED & !G_BC_JUST_TAKEN) :
    B_INTLK ? B_JB_V & !(B_JB_IS_BC & G_BC_JUST_SOLVED & !G_BC_JUST_TAKEN) : 0;
assign B_LS_SOLVING_BC_NEW = 
    A_FWD   ? A_LS_SOLVING_BC | DD_ISSUEING_UNSOLVED_BC_ON_A_LS & D_FWD :
    B_INTLK ? B_LS_SOLVING_BC | DD_ISSUEING_UNSOLVED_BC_ON_B_LS & D_FWD : 0;

// 【解説】割り込みコード: D で検出した不正命令などがあればそれ,
//         なければ EXU のオーバーフロー。
assign B_INTCODE_NEW = B_INTLK ? B_INTCODE : !A_FWD ? 0 :
		   (A_INTCODE != 0) ? A_INTCODE : AA_EXU_INT;

// These tags are just copied unmodified:
// 【解説】以下のタグは変更せずにそのままコピーする。
assign B_PRIVCODE_NEW = A_FWD ?  A_PRIVCODE  : B_INTLK ? B_PRIVCODE  : 0;
assign B_LS_LD_V_NEW = A_FWD ?  A_LS_LD_V   : B_INTLK ? B_LS_LD_V   : 0;
assign B_LS_ST_V_NEW = A_FWD ?  A_LS_ST_V	: B_INTLK ? B_LS_ST_V   : 0;
assign B_WE1_NEW = A_FWD ?  A_WE1  	: B_INTLK ? B_WE1       : 0;
assign B_WE2_NEW = A_FWD ?  A_WE2 	: B_INTLK ? B_WE2       : 0;
assign B_LS_SETCC_NEW = A_FWD ?  A_LS_SETCC  : B_INTLK ? B_LS_SETCC  : 0;
assign B_EX_SETCC_NEW = A_FWD ?  A_EX_SETCC  : B_INTLK ? B_EX_SETCC  : 0;


// Tags that are not 'valid' tags can be copied with CE = !B-INTLK.
// 【解説】L/ST の論理アドレス = A で計算した EAG の出力。
assign B_LS_LOG_AD_NEW = !B_INTLK ? AA_EAG_OUTPUT : B_LS_LOG_AD;

// 【解説】有効ビット以外のタグは B がインタロックでなければコピー。
assign B_WAD1_NEW = !B_INTLK ?  A_WAD1   	: B_WAD1;
assign B_WAD2_NEW = !B_INTLK ?  A_WAD2   	: B_WAD2;
assign B_LS_OPS_IS_GR_NEW = !B_INTLK ?  A_LS_OPS_IS_GR   : B_LS_OPS_IS_GR;
assign B_LS_RADS_NEW = !B_INTLK ?  A_LS_RADS   	: B_LS_RADS;
assign B_LS_OPCODE_NEW = !B_INTLK ?  A_LS_OPCODE   	: B_LS_OPCODE;
assign B_IS_SUPERSCALAR_NEW = !B_INTLK ? A_IS_SUPERSCALAR : B_IS_SUPERSCALAR;
assign B_LATTER_IS_JB_NEW = !B_INTLK ?  A_LATTER_IS_JB   : B_LATTER_IS_JB;
assign B_FIRST_IS_EX_NEW = !B_INTLK ?  A_FIRST_IS_EX   	: B_FIRST_IS_EX;
assign B_EX_RAD2_NEW = !B_INTLK ?  A_EX_RAD2  	: B_EX_RAD2;

// In branch using reg+base, TGT adrs is generated at EAG in A-cyc.
// 【解説】分岐先。レジスタ間接分岐 (A_SET_EAG_TO_TGT) では A の EAG で
//         計算した番地, PC 相対分岐では D で計算済みの番地。
assign B_TGT_NEW = B_INTLK ? B_TGT    : (A_SET_EAG_TO_TGT ? AA_EAG_OUTPUT : A_TGT );

// 【解説】EX パイプの結果と CC を B へ。
assign B_EX_RES_NEW = B_INTLK ? B_EX_RES : AA_EX_RES;
assign B_EX_CC_NEW = !B_INTLK ?  AA_EXU_CC : B_EX_CC;
