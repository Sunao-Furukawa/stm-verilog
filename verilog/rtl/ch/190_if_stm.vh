// =====================================================================
//  190_if_stm.vh  <-  hard/190-if-stm.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
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
//
// [Note] The instruction fetch state machine and the NIP update
//
// IB_* is the state of the issued fetch request (Instruction Buffer).
// NIP is the position of the next instruction in the queue (see 010_d_pre.vh), and
//   - advances by the number of instructions issued (EMIT = 0/1/2)
//   - goes back 2 when the queue shifts by 2 words
//   - is cleared to 6 or 7 (empty) when a branch switches / restarts the queue
// As the original comment "if '+' is allowed ..." says, it is written with bit operations instead of additions.
//
// 【ネットリスト解説】
//   入力 : IF_REQ_V / IF_REQ_AD / IF_REQ_ID / CANCEL_IB / IWQ_FULL (170),
//          SU_IF_CLH / SU_IF_RDY (180), EID / NIP_A (010), D_FWD (070),
//          DD_ISSUE_SECOND_INSN / IJB_V (030), DD_ISSUEING_* / DD_PREDICTING_TAKEN (040),
//          A_JB_V / A_SET_EAG_TO_TGT (150), START_TRIGGER (080), CANCEL_BY_INT /
//          WW_INTERRUPTION (050), IWQ_A_V45 / IWQ_B_V45 (200)
//   出力 (FF): IB_V / IB_AD / IB_ID -> 170, 180, 200, ポート IB_AD (メモリ)
//              NIP_A_REG / NIP_B / CUR_IWQ_ID -> 010
//              D_IF_AD_A / D_IF_AD_B -> 040 (分岐命令の番地), 170 (続きのフェッチ番地)
//   出力 (組合せ): SFTUP_A / SFTUP_B / SU_IF_CLH_NOCAN -> 200 (IWQ のシフトと取り込み)
//                  IB_VALID / IB_AD_NXT -> stm_cntl の出力ポート (stm_icache)
//   回路の形:
//     ・NIP は 3bit なので、NIP_A_TMP / NIP_B_NEW はどれも 10 入力程度の小さな論理。
//       ここは加算器を使わない書き方なので CARRY4 は出てこない
//       (add_3_2 も 3bit + 2bit なので LUT だけになる)。
//     ・SFTUP_A / SFTUP_B はそれぞれ 200 の IWQ 6 語 (32bit x 6 = 192 本) の MUX の
//       選択信号になるのでファンアウトが大きい。これは D_FWD → EMIT → NIP_AFTER_EMIT
//       → SFTUP → IWQ の FF とつながるので、インタロックの連鎖 (070) の終点の 1 つ。
//     ・IB_AD の FF の D 入力 IB_AD_NEW (= IF_REQ_AD か保持) が IB_AD_NXT として
//       外へ出る。
//
// [Netlist notes]
//   Inputs : IF_REQ_V / IF_REQ_AD / IF_REQ_ID / CANCEL_IB / IWQ_FULL (170),
//            SU_IF_CLH / SU_IF_RDY (180), EID / NIP_A (010), D_FWD (070),
//            DD_ISSUE_SECOND_INSN / IJB_V (030), DD_ISSUEING_* / DD_PREDICTING_TAKEN (040),
//            A_JB_V / A_SET_EAG_TO_TGT (150), START_TRIGGER (080), CANCEL_BY_INT /
//            WW_INTERRUPTION (050), IWQ_A_V45 / IWQ_B_V45 (200)
//   Outputs (FFs): IB_V / IB_AD / IB_ID -> 170, 180, 200, port IB_AD (memory)
//                  NIP_A_REG / NIP_B / CUR_IWQ_ID -> 010
//                  D_IF_AD_A / D_IF_AD_B -> 040 (address of a branch), 170 (next fetch address)
//   Outputs (combinational): SFTUP_A / SFTUP_B / SU_IF_CLH_NOCAN -> 200 (IWQ shift and load)
//                            IB_VALID / IB_AD_NXT -> output ports of stm_cntl (stm_icache)
//   Circuit:
//     - NIP is 3 bits, so NIP_A_TMP / NIP_B_NEW are small pieces of logic with about 10 inputs.
//       This part is written without adders, so no CARRY4 appears
//       (add_3_2 is only 3 bits + 2 bits, so it is LUTs only).
//     - SFTUP_A / SFTUP_B are each the select of the muxes of 6 IWQ words in 200
//       (32 bits x 6 = 192 bits), so their fan-out is large. They come from
//       D_FWD -> EMIT -> NIP_AFTER_EMIT -> SFTUP -> IWQ FFs, which makes them one of the
//       end points of the interlock chain (070).
//     - IB_AD_NEW, the D input of the IB_AD FFs (= IF_REQ_AD or hold), goes out as IB_AD_NXT.
// ---------------------------------------------------------------------

// if-stm
// Next State of Insn Fetch State Machine

// IB-AD,ID,V     -- After IF-REQ is issued, set them.  Otherwise,
//                        AD,ID -> stay      V -> 0 .  (For lvl-0)

// 【解説】フェッチ要求を出したら IB を有効にし、届いたか取り消されたら無効にする。
// [Note] IB becomes valid when a fetch request is issued, and invalid when it arrives or is cancelled.
assign IB_V_NEW = IF_REQ_V & SU_IF_RDY ? 1 :   SU_IF_CLH | CANCEL_IB ? 0 : IB_V; // 要求中フラグ: 要求を受け付けたら1, 届いたか取り消しで0, それ以外は保持 (FF+LUT5) / pending flag: 1 when accepted, 0 when arrived or cancelled, else hold (FF + LUT5)
assign IB_AD_NEW = IF_REQ_V & SU_IF_RDY ? IF_REQ_AD : IB_AD; // 要求中の番地: 受け付けたらIF_REQ_AD, それ以外は保持 (CE付きFF32本) → メモリの番地 / pending address: IF_REQ_AD when accepted, else hold (32 FFs with CE) -> memory address
assign IB_ID_NEW = IF_REQ_V & SU_IF_RDY ? IF_REQ_ID : IB_ID; // 要求中のフェッチの宛先キュー (CE付きFF) / destination queue of the pending fetch (FF with CE)
// 【解説】(Verilog 版で追加) 外部バス用: IB_V と、次のサイクルの IB_AD。
//         命令キャッシュ (stm_icache) は IB_AD_NXT で RAM を 1 サイクル先に引き、
//         ヒットなら元のメモリと同じく要求の次のサイクルに命令を返す。
// [Note] (added in the Verilog version) For the external bus: IB_V, and IB_AD of the next cycle.
//        The instruction cache (stm_icache) reads its RAM one cycle ahead with IB_AD_NXT, and on a hit
//        returns the instructions in the cycle after the request, just like the original memory.
assign IB_VALID   = IB_V;                               // 出力ポート用の別名 (stm_icacheへ) / alias for the output port (to stm_icache)
assign IB_AD_NXT  = IB_AD_NEW;                          // 次のサイクルのIB_AD = FFのD入力そのもの: icacheのBRAM番地へ (FFを通さない組合せ出力) / next-cycle IB_AD = the FF's D input: to the icache BRAM address (combinational output)

// CUR-ID         -- Change if (BC-issue & predict TKN) | (just after BC-cancel)

// 【解説】現在のキュー。未解決 BC を taken と予測して発行したら、分岐先を入れる
//         もう一方のキューへ切り替える。予測ミスの切り替えは EID (010) で行う。
//         割り込み時は 0 (キュー A) に戻す。
// [Note] The current queue. When an unresolved BC is issued predicted taken, switch to the other
//        queue, which will receive the target. Switching on a misprediction is done by EID (010).
//        On an interrupt, go back to 0 (queue A).
assign CUR_IWQ_ID_NEW = (EID ^ (DD_PREDICTING_TAKEN & D_FWD)) & !WW_INTERRUPTION; // 現在のキュー: 成立と予測したBCを発行したら反転, 割り込みで0 (FF+LUT4) / current queue: flips when a BC predicted taken issues, 0 on interrupt (FF + LUT4)

// NIP :
// 【解説】届いた命令をキューに入れてよいか (取り消されていない, 空きがある)。
// [Note] May the arrived instructions be put into the queue (not cancelled, there is room)?
assign SU_IF_CLH_NOCAN = SU_IF_CLH & !CANCEL_IB & !IWQ_FULL; // 届いた命令をキューに入れてよい: 取り消されず満杯でない (AND3) / arrived insns may enter the queue: not cancelled and not full (AND3)
// 【解説】このサイクルに D から発行した命令の数 (0/1/2)。
// [Note] Number of instructions issued from D in this cycle (0/1/2).
assign EMIT = !D_FWD ? 0 : DD_ISSUE_SECOND_INSN ? 2 : 1; // このサイクルに発行した命令数 0/1/2 (2bit, LUT2本) / insns issued this cycle 0/1/2 (2 bits, 2 LUTs)

// if '+' is allowed, I would write as follows :
//SFTUP-A   = IWQ-A-V45 & (NIP-A + (!EID ? EMIT : 0) >= 2)
//SFTUP-B   = IWQ-B-V45 & (NIP-B + ( EID ? EMIT : 0) >= 2)

// 【解説】発行はどちらか一方のキュー (EID 側) からだけ。発行後の NIP を計算。
// [Note] Instructions issue from only one queue (the EID side). Compute NIP after the issue.
assign EMIT_FOR_A = (!EID ? EMIT : 0);                  // キューAから発行した数 (Bが使用中なら0): 2bit AND / insns issued from queue A (0 when B is used): 2-bit AND
assign NIP_AFTER_EMIT_A = add_3_2(NIP_A,EMIT_FOR_A);    // 発行後のNIP_A = NIP_A + EMIT: 3bit+2bitの加算 → LUT3本 (CARRY4は使わない) / NIP_A after issue = NIP_A + EMIT: 3-bit + 2-bit add -> 3 LUTs (no CARRY4)

assign EMIT_FOR_B = ( EID ? EMIT : 0);                  // キューBから発行した数 / insns issued from queue B
assign NIP_AFTER_EMIT_B = add_3_2(NIP_B,EMIT_FOR_B);    // 発行後のNIP_B (LUT3本) / NIP_B after issue (3 LUTs)
// ---- #ifndef VHDL (C シミュレータ版を採用) ----
//      (#ifndef VHDL: the C-simulator version is used)
// 【解説】キューを 2 語前へシフトするか: 4,5 番が埋まっていて, 発行後の NIP が
//         2 以上 (0,1 番がもう不要) のとき。
// [Note] Shift the queue forward by 2 words: when entries 4,5 are filled and NIP after the issue
//        is 2 or more (entries 0,1 are no longer needed).
assign SFTUP_A = IWQ_A_V45 & ((NIP_AFTER_EMIT_A & 6) != 0); // キューAを2語シフト: 4,5番が有効で発行後のNIP>=2 (LUT) → 200の192本のCE / shift queue A by 2 words: 4,5 valid and NIP after issue >= 2 (LUT) -> CE of 192 FFs in 200
assign SFTUP_B = IWQ_B_V45 & ((NIP_AFTER_EMIT_B & 6) != 0); // キューBを2語シフト (同じ形, 高ファンアウト) / shift queue B by 2 words (same form, high fan-out)
// ---- #else (VHDL 版: 参考) ----
//      (#else: the VHDL version, for reference)
// SFTUP-A   = IWQ-A-V45 & (NIP-AFTER-EMIT-A[0] | NIP-AFTER-EMIT-A[1])
// SFTUP-B   = IWQ-B-V45 & (NIP-AFTER-EMIT-B[0] | NIP-AFTER-EMIT-B[1])
// ---- #endif ----

// 【解説】D で発行した分岐が taken 確定 (未解決でも untaken でもない)。
// [Note] The branch issued in D is surely taken (neither unresolved nor untaken).
assign DD_JB_TKN = IJB_V & !DD_ISSUEING_UNSOLVED_BC & !DD_ISSUEING_UNTAKEN_BC; // Dで発行した分岐が成立確定 (未解決でも不成立でもない) (AND3) / branch issued in D is surely taken (neither unsolved nor untaken) (AND3)

// 【解説】キューをクリアして分岐先から入れ直す条件:
//           ・このキューで taken の分岐を発行した
//           ・もう一方のキューで未解決 BC を発行した (このキューに分岐先を入れる)
//           ・レジスタ間接分岐, 再スタート, 割り込み
//
// [Note] Conditions to clear the queue and refill it from the target:
//          - a taken branch was issued from this queue
//          - an unresolved BC was issued from the other queue (this queue receives the target)
//          - register-indirect branch, restart, interrupt
assign CLEAR_NIP_A = IJB_V & D_FWD & (EID&DD_ISSUEING_UNSOLVED_BC | !EID & DD_JB_TKN) // キューAをクリア: Aで成立分岐 / Bで未解決BC (Aに分岐先) ... / clear queue A: taken branch on A / unsolved BC on B (target into A) ...
	      | !EID & A_JB_V & A_SET_EAG_TO_TGT | START_TRIGGER | CANCEL_BY_INT; // ...Aのレジスタ間接分岐, 再スタート, 割り込み (LUT2段) / ... register-indirect branch in A, restart, interrupt (2 LUT levels)
assign CLEAR_NIP_B = IJB_V & D_FWD & (!EID&DD_ISSUEING_UNSOLVED_BC | EID & DD_JB_TKN) // キューBをクリア (Aと対称) ... / clear queue B (symmetric to A) ...
	      |  EID & A_JB_V & A_SET_EAG_TO_TGT | START_TRIGGER | CANCEL_BY_INT; // ...(LUT2段) / ... (2 LUT levels)

// if '+' is allowed, I would write as follows :
//NIP-A := ( CLEAR-NIP-A  ? 6+((IF-REQ-AD&4)>>2) :
//         ( (NIP-A >= 6) ? NIP-A + MINUS2 * (SU-IF-CLH-NOCAN & ! IB-ID) :
// 		NIP-A + (!EID ? EMIT : 0) + MINUS2 * SFTUP-A   ))
//NIP-B := ( CLEAR-NIP-B  ? 6+((IF-REQ-AD&4)>>2) :
//         ( (NIP-B >= 6) ? NIP-B + MINUS2 * (SU-IF-CLH-NOCAN &   IB-ID) :
// 		NIP-B + ( EID ? EMIT : 0) + MINUS2 * SFTUP-B   ))

// ---- #ifndef VHDL (C シミュレータ版を採用) ----
//      (#ifndef VHDL: the C-simulator version is used)
// 【解説】次の NIP:
//           クリア         : 6 + (分岐先が 8 バイトの後半なら 1)
//           NIP が 6/7 (空) : 命令が届いたら 4/5 に (6→4, 7→5)
//           シフトする     : 発行後の NIP - 2
//           それ以外       : 発行後の NIP
//
// [Note] Next NIP:
//          clear              : 6 + (1 if the target is in the second half of the 8 bytes)
//          NIP is 6/7 (empty) : 4/5 when instructions arrive (6->4, 7->5)
//          shift              : NIP after the issue - 2
//          otherwise          : NIP after the issue
assign NIP_A_TMP = CLEAR_NIP_A       ? 6 | ((IF_REQ_AD & 4) ? 1 : 0)                 : // 次のNIP_A (3bit): クリアなら6+(分岐先が後半なら1) ... / next NIP_A (3 bits): on clear 6 + (1 if the target is the second word) ...
         ((NIP_A & 6) == 6) ? NIP_A & ((SU_IF_CLH_NOCAN & ! IB_ID) ? 5 : 7) : // ...空(6/7)なら命令が届いたら4/5に ... / ... empty (6/7): becomes 4/5 when insns arrive ...
	 SFTUP_A ? ( ((NIP_AFTER_EMIT_A & 2)!=0) ? (NIP_AFTER_EMIT_A & 5) : // ...シフトするなら発行後のNIP-2 ... / ... shifting: NIP after issue - 2 ...
	  					   2 | (NIP_AFTER_EMIT_A & 1) ): // ...(ビット操作で書いた引き算) ... / ... (the subtraction written as bit operations) ...
	 NIP_AFTER_EMIT_A;                              // ...それ以外は発行後のNIP. 入力10本程度 → 3bitそれぞれLUT6 1~2個 / ... else NIP after issue. ~10 inputs -> 1-2 LUT6s per bit

assign NIP_B_NEW = CLEAR_NIP_B        ? 6 | ((IF_REQ_AD & 4) ? 1 : 0)                 : // 次のNIP_B (NIP_Aと同じ形) ... / next NIP_B (same as NIP_A) ...
         ((NIP_B & 6) == 6) ? NIP_B & ((SU_IF_CLH_NOCAN &   IB_ID) ? 5 : 7) : // ...空なら届いた時に4/5 ... / ... empty: 4/5 on arrival ...
	 SFTUP_B ? ( ((NIP_AFTER_EMIT_B & 2)!=0) ? (NIP_AFTER_EMIT_B & 5) : // ...シフトなら-2 ... / ... shifting: -2 ...
	  					   2 | (NIP_AFTER_EMIT_B & 1) ): // ...(ビット操作) ... / ... (bit operations) ...
	 NIP_AFTER_EMIT_B;                              // ...それ以外は発行後のNIP → NIP_BのFF3本 / ... else NIP after issue -> 3 NIP_B FFs
// ---- #else (VHDL 版: 参考) ----
//      (#else: the VHDL version, for reference)
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
// [Note] NIP_A is stored after ^6 (see 010_d_pre.vh).
assign NIP_A_REG_NEW = NIP_A_TMP ^ 6;                   // NIP_Aは^6して格納 (bit1,2の反転はLUTに吸収) → リセット0で空(6) / NIP_A stored ^6 (inversion of bits 1,2 absorbed in LUTs) -> reset 0 means empty (6)

// 【解説】キュー末尾 (4,5 番) に入っている 8 バイトのフェッチ番地。分岐命令の番地計算 (040) に使う。
// [Note] Fetch address of the 8 bytes at the end of the queue (entries 4,5). Used for the branch address (040).
assign D_IF_AD_A_NEW = CLEAR_NIP_A 	       ? IF_REQ_AD : // キューA末尾の8バイトの番地: クリア時はフェッチ番地 ... / address of the last 8 bytes of queue A: fetch address on clear ...
	     SU_IF_CLH_NOCAN & ! IB_ID ? IB_AD     : D_IF_AD_A; // ...Aに命令が届いたらその番地, 他は保持 (32bit 2:1 MUX + CE) / ... the arriving address for A, else hold (32-bit 2:1 mux + CE)
assign D_IF_AD_B_NEW = CLEAR_NIP_B 	       ? IF_REQ_AD : // キューB末尾の番地 ... / address of the tail of queue B ...
	     SU_IF_CLH_NOCAN &   IB_ID ? IB_AD     : D_IF_AD_B; // ...(Aと同じ形) → 040, 170 / ... (same as A) -> 040, 170
