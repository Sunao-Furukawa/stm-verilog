// =====================================================================
//  130_a_act.vh  <-  hard/130-a-act.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】A → B の状態遷移
//
// 110_b_act.vh と同じ考え方で、A の命令が進めば (A_FWD) タグを B へ移し、
// B がインタロック中なら保持し、それ以外は有効ビットを 0 にする。
//
// [Note] State transition A -> B
//
// Same idea as 110_b_act.vh: if the instruction in A moves on (A_FWD) its tags go to B,
// if B is interlocked they are held, otherwise the valid bits become 0.
//
// 【ネットリスト解説】
//   入力 : A_* (150 / 140 の FF), AA_* (120 の EXU / EAG の出力, 組合せ),
//          A_FWD / B_INTLK / D_FWD (070), G_BC_* (210), DD_ISSUEING_UNSOLVED_BC_ON_A_LS / _B_LS (040)
//   出力 (すべて FF): B_* -> 110 (E へのコピー), 100 (B サイクルのデータ選択),
//                     060 / 070 (B_V, B_WAD1, B_WE1, B_PRIVCODE), 040 (B_*_SETCC, B_EX_CC),
//                     140 (B_EX_RES / B_WAD / B_WE のバイパス)
//   回路の形: A → B のパイプラインレジスタ。110_b_act.vh と同じく
//     有効ビット類 = 3:1 MUX + FF, データ類 = CE (!B_INTLK) 付きの FF。
//     ただし B_LS_LOG_AD / B_EX_RES / B_EX_CC / B_TGT の D 入力は A の FF ではなく
//     120 の演算器の出力 (AA_EAG_OUTPUT, AA_EX_RES, AA_EXU_CC) なので、
//     ここが A サイクルの演算の終点 (FF) になる。B_TGT は AA_EAG_OUTPUT と A_TGT の
//     2:1 MUX (選択 = A_SET_EAG_TO_TGT)。
//     B_EX_RAD2 はどこからも使われないので消える。
//     B_INTCODE_NEW に入るのは DD_INTCODE (0 か INTCODE_OP=1) か AA_EXU_INT (0 か
//     INTCODE_OVF=4) だけなので、bit1 は常に 0。合成ツールはこれを見抜き、
//     B_INTCODE → E_EX_INTCODE → W_EX_INTCODE の bit1 の FF を消す
//     (合成結果には W_EX_INTCODE_reg[1] が無い)。
//
// [Netlist notes]
//   Inputs : A_* (FFs in 150 / 140), AA_* (EXU / EAG outputs in 120, combinational),
//            A_FWD / B_INTLK / D_FWD (070), G_BC_* (210), DD_ISSUEING_UNSOLVED_BC_ON_A_LS / _B_LS (040)
//   Outputs (all FFs): B_* -> 110 (copy to E), 100 (data selection in the B cycle),
//                      060 / 070 (B_V, B_WAD1, B_WE1, B_PRIVCODE), 040 (B_*_SETCC, B_EX_CC),
//                      140 (bypass of B_EX_RES / B_WAD / B_WE)
//   Circuit: the A -> B pipeline register. As in 110_b_act.vh,
//     valid bits = 3:1 mux + FF, data = FF with CE (!B_INTLK).
//     The D inputs of B_LS_LOG_AD / B_EX_RES / B_EX_CC / B_TGT, however, are not A FFs but the
//     outputs of the units in 120 (AA_EAG_OUTPUT, AA_EX_RES, AA_EXU_CC), so this is where the
//     A-cycle computation ends (in FFs). B_TGT is a 2:1 mux of AA_EAG_OUTPUT and A_TGT
//     (select = A_SET_EAG_TO_TGT).
//     B_EX_RAD2 is unused and disappears.
//     B_INTCODE_NEW only ever receives DD_INTCODE (0 or INTCODE_OP=1) or AA_EXU_INT (0 or
//     INTCODE_OVF=4), so bit 1 is always 0. Synthesis sees this and removes the bit-1 FFs of
//     B_INTCODE -> E_EX_INTCODE -> W_EX_INTCODE (there is no W_EX_INTCODE_reg[1] in the result).
// ---------------------------------------------------------------------

// a-act

// 【解説】B の有効ビット: A から来るか, B が留まるか。
// [Note] Valid bit of B: something comes from A, or B stays.
assign B_V_NEW = A_FWD | B_INTLK;                       // Bの有効ビット: Aから来る or Bが留まる (OR, FF1本) / B valid: comes from A or B stays (OR, 1 FF)

// 【解説】分岐関係のタグ (110_b_act.vh と同じく分岐解決で更新)。
// [Note] Branch tags (updated by branch resolution, as in 110_b_act.vh).
assign B_JB_IS_BC_NEW = A_FWD   ? A_JB_IS_BC & !G_BC_JUST_SOLVED : // BのBCが未解決か: Aからの値 ... / is B's BC unsolved: value from A ...
			B_INTLK ? B_JB_IS_BC & !G_BC_JUST_SOLVED : 0; // ...か保持の値を, 解決したら0に (LUT5) / ... or held, cleared once solved (LUT5)
assign B_JB_SUBJECT_TO_BC_NEW = A_FWD   ? A_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED : // 投機中フラグ: 同じ形 ... / speculative flag: same form ...
			B_INTLK ? B_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED : 0; // ...解決したら落とす (LUT5) / ... dropped once solved (LUT5)
assign B_JB_V_NEW =                                     // Bに分岐があるか: ... / branch present in B: ...
    A_FWD   ? A_JB_V & !(A_JB_IS_BC & G_BC_JUST_SOLVED & !G_BC_JUST_TAKEN) : // ...Aから来たBCが不成立と解決したら消す ... / ... drop a BC from A resolved not-taken ...
    B_INTLK ? B_JB_V & !(B_JB_IS_BC & G_BC_JUST_SOLVED & !G_BC_JUST_TAKEN) : 0; // ...留まっている分も同様 (LUT6) / ... same for one held in B (LUT6)
assign B_LS_SOLVING_BC_NEW =                            // このLS命令が未解決BCのCCを作るか: ... / does this LS insn make the unsolved BC's CC: ...
    A_FWD   ? A_LS_SOLVING_BC | DD_ISSUEING_UNSOLVED_BC_ON_A_LS & D_FWD : // ...Aからの値 or 今発行のBCの作り手がA ... / ... value from A, or maker of the BC issued now is in A ...
    B_INTLK ? B_LS_SOLVING_BC | DD_ISSUEING_UNSOLVED_BC_ON_B_LS & D_FWD : 0; // ...保持 or 作り手がB (LUT6) / ... held, or maker is in B (LUT6)

// 【解説】割り込みコード: D で検出した不正命令などがあればそれ,
//         なければ EXU のオーバーフロー。
// [Note] Interrupt code: the one found in D (illegal instruction etc.) if any,
//        otherwise the EXU overflow.
assign B_INTCODE_NEW = B_INTLK ? B_INTCODE : !A_FWD ? 0 : // Bの割り込みコード: 保持 / Aが進まなければ0 / ... / B interrupt code: hold / 0 if A does not move / ...
		   (A_INTCODE != 0) ? A_INTCODE : AA_EXU_INT; // ...Dで検出した例外(1)を優先, なければEXUのオーバーフロー(4). bit1は常に0でFFごと消える / ... D exception (1) first, else EXU overflow (4). Bit 1 is always 0, so its FF is removed

// These tags are just copied unmodified:
// 【解説】以下のタグは変更せずにそのままコピーする。
// [Note] The tags below are copied unchanged.
assign B_PRIVCODE_NEW = A_FWD ?  A_PRIVCODE  : B_INTLK ? B_PRIVCODE  : 0; // 特権命令の種類: 3:1 MUX (A値/保持/0) x2bit / privileged kind: 3:1 mux (A / hold / 0) x 2 bits
assign B_LS_LD_V_NEW = A_FWD ?  A_LS_LD_V   : B_INTLK ? B_LS_LD_V   : 0; // ロードか: 同じ形 (FF+LUT3) / load?: same form (FF + LUT3)
assign B_LS_ST_V_NEW = A_FWD ?  A_LS_ST_V	: B_INTLK ? B_LS_ST_V   : 0; // ストアか: 同じ形 / store?: same
assign B_WE1_NEW = A_FWD ?  A_WE1  	: B_INTLK ? B_WE1       : 0; // LS側GR書き込み: 同じ形 / LS GR write: same
assign B_WE2_NEW = A_FWD ?  A_WE2 	: B_INTLK ? B_WE2       : 0; // EX側GR書き込み: 同じ形 / EX GR write: same
assign B_LS_SETCC_NEW = A_FWD ?  A_LS_SETCC  : B_INTLK ? B_LS_SETCC  : 0; // LSがCCを変える: 同じ形 / LS sets CC: same
assign B_EX_SETCC_NEW = A_FWD ?  A_EX_SETCC  : B_INTLK ? B_EX_SETCC  : 0; // EXがCCを変える: 同じ形 / EX sets CC: same


// Tags that are not 'valid' tags can be copied with CE = !B-INTLK.
// 【解説】L/ST の論理アドレス = A で計算した EAG の出力。
// [Note] Logical address of the L/ST = the EAG output computed in A.
assign B_LS_LOG_AD_NEW = !B_INTLK ? AA_EAG_OUTPUT : B_LS_LOG_AD; // L/ST番地: EAG加算器の出力をCE付きFF32本で受ける (Aサイクルの終点) / L/ST address: EAG adder output into 32 FFs with CE (end of the A cycle)

// 【解説】有効ビット以外のタグは B がインタロックでなければコピー。
// [Note] Tags other than valid bits are copied when B is not interlocked.
assign B_WAD1_NEW = !B_INTLK ?  A_WAD1   	: B_WAD1; // LS側書き込み番号: CE付きFF4本 / LS write number: 4 FFs with CE
assign B_WAD2_NEW = !B_INTLK ?  A_WAD2   	: B_WAD2; // EX側書き込み番号: CE付きFF4本 / EX write number: 4 FFs with CE
assign B_LS_OPS_IS_GR_NEW = !B_INTLK ?  A_LS_OPS_IS_GR   : B_LS_OPS_IS_GR; // RSがGRか: CE付きFF → 100のバイパス判定 / RS is a GR: FF with CE -> bypass check in 100
assign B_LS_RADS_NEW = !B_INTLK ?  A_LS_RADS   	: B_LS_RADS; // RSの番号: CE付きFF4本 → stm_regfileのrads, 100の比較 / RS number: 4 FFs with CE -> rads of stm_regfile, compares in 100
assign B_LS_OPCODE_NEW = !B_INTLK ?  A_LS_OPCODE   	: B_LS_OPCODE; // LSのopcode: CE付きFF5本 / LS opcode: 5 FFs with CE
assign B_IS_SUPERSCALAR_NEW = !B_INTLK ? A_IS_SUPERSCALAR : B_IS_SUPERSCALAR; // 2命令の組か: CE付きFF / pair?: FF with CE
assign B_LATTER_IS_JB_NEW = !B_INTLK ?  A_LATTER_IS_JB   : B_LATTER_IS_JB; // 後の命令が分岐か: CE付きFF / latter is a branch?: FF with CE
assign B_FIRST_IS_EX_NEW = !B_INTLK ?  A_FIRST_IS_EX   	: B_FIRST_IS_EX; // 先の命令がEXか: CE付きFF / first is EX?: FF with CE
assign B_EX_RAD2_NEW = !B_INTLK ?  A_EX_RAD2  	: B_EX_RAD2; // R2の番号: どこからも使われず合成で消える / R2 number: unused, removed by synthesis

// In branch using reg+base, TGT adrs is generated at EAG in A-cyc.
// 【解説】分岐先。レジスタ間接分岐 (A_SET_EAG_TO_TGT) では A の EAG で
//         計算した番地, PC 相対分岐では D で計算済みの番地。
// [Note] Branch target: for a register-indirect branch (A_SET_EAG_TO_TGT) the address computed by the
//        EAG in A, for a PC-relative branch the address already computed in D.
assign B_TGT_NEW = B_INTLK ? B_TGT    : (A_SET_EAG_TO_TGT ? AA_EAG_OUTPUT : A_TGT ); // 分岐先: レジスタ間接ならEAG出力, PC相対ならA_TGT (32bit 2:1 MUX + CE) / target: EAG output if register-indirect, else A_TGT (32-bit 2:1 mux + CE)

// 【解説】EX パイプの結果と CC を B へ。
// [Note] The EX-pipe result and CC go to B.
assign B_EX_RES_NEW = B_INTLK ? B_EX_RES : AA_EX_RES;   // EXの結果: AA_EX_RES (EXU/RSR) をCE付きFF32本で受ける / EX result: AA_EX_RES (EXU / RSR) into 32 FFs with CE
assign B_EX_CC_NEW = !B_INTLK ?  AA_EXU_CC : B_EX_CC;   // EXのCC: EXUのCCをCE付きFF2本で受ける → 040のフォワード / EX CC: EXU CC into 2 FFs with CE -> forwarding in 040
