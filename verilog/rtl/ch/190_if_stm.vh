// =====================================================================
//  190_if_stm.vh  <-  hard/190-if-stm.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】命令フェッチの状態機械と NIP の更新
//
// IB_* は発行済みのフェッチ要求 (Instruction Buffer) の状態。
// NIP はキュー内の次の命令の位置 (010_d_pre.vh 参照) で、
//   ・命令を発行した数 (EMIT = 0/1/2) だけ進む
//   ・キューを 2 語シフトしたら 2 戻る
//   ・分岐でキューを切り替える/やり直すときはクリアして 6 か 7 (空) にする
// 元コメントの「'+' が使えれば…」の通り、加算を使わずビット操作で書かれている。
// ---------------------------------------------------------------------

// if-stm
// Next State of Insn Fetch State Machine

// IB-AD,ID,V     -- After IF-REQ is issued, set them.  Otherwise,
//                        AD,ID -> stay      V -> 0 .  (For lvl-0)

// 【解説】フェッチ要求を出したら IB を有効にし、届いたか取り消されたら無効にする。
assign IB_V_NEW = IF_REQ_V & SU_IF_RDY ? 1 :   SU_IF_CLH | CANCEL_IB ? 0 : IB_V;
assign IB_AD_NEW = IF_REQ_V & SU_IF_RDY ? IF_REQ_AD : IB_AD;
assign IB_ID_NEW = IF_REQ_V & SU_IF_RDY ? IF_REQ_ID : IB_ID;

// CUR-ID         -- Change if (BC-issue & predict TKN) | (just after BC-cancel)

// 【解説】現在のキュー。未解決 BC を taken と予測して発行したら、分岐先を入れる
//         もう一方のキューへ切り替える。予測ミスの切り替えは EID (010) で行う。
//         割り込み時は 0 (キュー A) に戻す。
assign CUR_IWQ_ID_NEW = (EID ^ (DD_PREDICTING_TAKEN & D_FWD)) & !WW_INTERRUPTION;

// NIP :
// 【解説】届いた命令をキューに入れてよいか (取り消されていない, 空きがある)。
assign SU_IF_CLH_NOCAN = SU_IF_CLH & !CANCEL_IB & !IWQ_FULL;
// 【解説】このサイクルに D から発行した命令の数 (0/1/2)。
assign EMIT = !D_FWD ? 0 : DD_ISSUE_SECOND_INSN ? 2 : 1;

// if '+' is allowed, I would write as follows :
//SFTUP-A   = IWQ-A-V45 & (NIP-A + (!EID ? EMIT : 0) >= 2)
//SFTUP-B   = IWQ-B-V45 & (NIP-B + ( EID ? EMIT : 0) >= 2)

// 【解説】発行はどちらか一方のキュー (EID 側) からだけ。発行後の NIP を計算。
assign EMIT_FOR_A = (!EID ? EMIT : 0);
assign NIP_AFTER_EMIT_A = add_3_2(NIP_A,EMIT_FOR_A);

assign EMIT_FOR_B = ( EID ? EMIT : 0);
assign NIP_AFTER_EMIT_B = add_3_2(NIP_B,EMIT_FOR_B);
// ---- #ifndef VHDL (C シミュレータ版を採用) ----
// 【解説】キューを 2 語前へシフトするか: 4,5 番が埋まっていて, 発行後の NIP が
//         2 以上 (0,1 番がもう不要) のとき。
assign SFTUP_A = IWQ_A_V45 & ((NIP_AFTER_EMIT_A & 6) != 0);
assign SFTUP_B = IWQ_B_V45 & ((NIP_AFTER_EMIT_B & 6) != 0);
// ---- #else (VHDL 版: 参考) ----
// SFTUP-A   = IWQ-A-V45 & (NIP-AFTER-EMIT-A[0] | NIP-AFTER-EMIT-A[1])
// SFTUP-B   = IWQ-B-V45 & (NIP-AFTER-EMIT-B[0] | NIP-AFTER-EMIT-B[1])
// ---- #endif ----

// 【解説】D で発行した分岐が taken 確定 (未解決でも untaken でもない)。
assign DD_JB_TKN = IJB_V & !DD_ISSUEING_UNSOLVED_BC & !DD_ISSUEING_UNTAKEN_BC;

// 【解説】キューをクリアして分岐先から入れ直す条件:
//           ・このキューで taken の分岐を発行した
//           ・もう一方のキューで未解決 BC を発行した (このキューに分岐先を入れる)
//           ・レジスタ間接分岐, 再スタート, 割り込み
assign CLEAR_NIP_A = IJB_V & D_FWD & (EID&DD_ISSUEING_UNSOLVED_BC | !EID & DD_JB_TKN)
	      | !EID & A_JB_V & A_SET_EAG_TO_TGT | START_TRIGGER | CANCEL_BY_INT;
assign CLEAR_NIP_B = IJB_V & D_FWD & (!EID&DD_ISSUEING_UNSOLVED_BC | EID & DD_JB_TKN)
	      |  EID & A_JB_V & A_SET_EAG_TO_TGT | START_TRIGGER | CANCEL_BY_INT;

// if '+' is allowed, I would write as follows :
//NIP-A := ( CLEAR-NIP-A  ? 6+((IF-REQ-AD&4)>>2) :
//         ( (NIP-A >= 6) ? NIP-A + MINUS2 * (SU-IF-CLH-NOCAN & ! IB-ID) :
// 		NIP-A + (!EID ? EMIT : 0) + MINUS2 * SFTUP-A   ))
//NIP-B := ( CLEAR-NIP-B  ? 6+((IF-REQ-AD&4)>>2) :
//         ( (NIP-B >= 6) ? NIP-B + MINUS2 * (SU-IF-CLH-NOCAN &   IB-ID) :
// 		NIP-B + ( EID ? EMIT : 0) + MINUS2 * SFTUP-B   ))

// ---- #ifndef VHDL (C シミュレータ版を採用) ----
// 【解説】次の NIP:
//           クリア         : 6 + (分岐先が 8 バイトの後半なら 1)
//           NIP が 6/7 (空) : 命令が届いたら 4/5 に (6→4, 7→5)
//           シフトする     : 発行後の NIP - 2
//           それ以外       : 発行後の NIP
assign NIP_A_TMP = CLEAR_NIP_A       ? 6 | ((IF_REQ_AD & 4) ? 1 : 0)                 :
         ((NIP_A & 6) == 6) ? NIP_A & ((SU_IF_CLH_NOCAN & ! IB_ID) ? 5 : 7) :
	 SFTUP_A ? ( ((NIP_AFTER_EMIT_A & 2)!=0) ? (NIP_AFTER_EMIT_A & 5) :
	  					   2 | (NIP_AFTER_EMIT_A & 1) ):
	 NIP_AFTER_EMIT_A;

assign NIP_B_NEW = CLEAR_NIP_B        ? 6 | ((IF_REQ_AD & 4) ? 1 : 0)                 :
         ((NIP_B & 6) == 6) ? NIP_B & ((SU_IF_CLH_NOCAN &   IB_ID) ? 5 : 7) :
	 SFTUP_B ? ( ((NIP_AFTER_EMIT_B & 2)!=0) ? (NIP_AFTER_EMIT_B & 5) :
	  					   2 | (NIP_AFTER_EMIT_B & 1) ):
	 NIP_AFTER_EMIT_B;
// ---- #else (VHDL 版: 参考) ----
// NIP-A-TMP = CLEAR-NIP-A        ? B"11" . IF-REQ-AD[29] :
//          (NIP-A[0]&NIP-A[1]) ? B"1" . !(SU-IF-CLH-NOCAN & ! IB-ID) . NIP-A[2] : 
// 	 SFTUP-A ? B"0" . NIP-AFTER-EMIT-A[0] . NIP-AFTER-EMIT-A[2] :
// 	 NIP-AFTER-EMIT-A
// NIP-B := CLEAR-NIP-B        ? B"11" . IF-REQ-AD[29] :
//          (NIP-B[0]&NIP-B[1]) ? B"1" . !(SU-IF-CLH-NOCAN &   IB-ID) . NIP-B[2] : 
// 	 SFTUP-B ? B"0" . NIP-AFTER-EMIT-B[0] . NIP-AFTER-EMIT-B[2] :
// 	 NIP-AFTER-EMIT-B
// ---- #endif ----

// 【解説】NIP_A は ^6 して保存する (010_d_pre.vh 参照)。
assign NIP_A_REG_NEW = NIP_A_TMP ^ 6;

// 【解説】キュー末尾 (4,5 番) に入っている 8 バイトのフェッチ番地。分岐命令の番地計算 (040) に使う。
assign D_IF_AD_A_NEW = CLEAR_NIP_A 	       ? IF_REQ_AD :
	     SU_IF_CLH_NOCAN & ! IB_ID ? IB_AD     : D_IF_AD_A;
assign D_IF_AD_B_NEW = CLEAR_NIP_B 	       ? IF_REQ_AD :
	     SU_IF_CLH_NOCAN &   IB_ID ? IB_AD     : D_IF_AD_B;
