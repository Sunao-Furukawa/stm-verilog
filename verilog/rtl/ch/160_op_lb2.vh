// =====================================================================
//  160_op_lb2.vh  <-  hard/160-op-lb2.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】S ユニットの次状態
//
// S ユニットには 2 段の要求置き場がある:
//   OP-B    : キャッシュにアクセス中の要求 (LBS_AD/LBS_DT/LBS_WE がメモリへ出る)
//   OP-WAIT : OP-B が終わらないうちに受け付けた次の要求を 1 つ待たせる
// 要求の種類 (OPC) は LD / ST / ST2 (050_op_lb1.vh 参照)。
//
// [Note] Next state of the S unit
//
// The S unit has two slots for requests:
//   OP-B    : the request accessing the cache (LBS_AD/LBS_DT/LBS_WE go out to memory)
//   OP-WAIT : holds one next request accepted before OP-B has finished
// The kinds of request (OPC) are LD / ST / ST2 (see 050_op_lb1.vh).
//
// 【ネットリスト解説】
//   入力 : AA_LD_GO / WW_ST_GO (060), AA_EAG_OUTPUT (120), STB_AD / STB_DT (090),
//          A_LS_ST_V / A_JB_SUBJECT_TO_BC (150), B_OPCLH / OP_*_V_NOCAN (050),
//          G_BC_JUST_SOLVED (210), ポート RANDOM_FOR_OPCLH
//   出力 (FF): LBS_WE / LBS_AD / LBS_DT -> stm_cntl の出力ポート (メモリ / stm_axi_master),
//                                         LBS_AD は 050 (アドレス比較・フォワーディング) にも
//              OP_B_V / OP_B_OPC / OP_B_SUBJECT_TO_BC -> 050, 060
//              OP_WAIT_*                               -> 050, 060
//              OP_B_NEW                                -> stm_cntl の出力ポート (stm_axi_master)
//   回路の形: 深さ 2 の小さな FIFO (OP-WAIT → OP-B)。
//     ・OP-B の FF の D 入力は「留まる / OP-WAIT から移す / 新しく受け付ける」の 3:1 MUX。
//       LBS_AD は 32bit, LBS_DT は 32bit なので、ここで 64 本ぶんの 3:1 MUX になる。
//     ・新しく受け付ける番地 ACCEPTING_AD は AA_EAG_OUTPUT と STB_AD の 2:1 MUX。
//       A の EAG の加算結果がそのまま LBS_AD の FF に入るので、メモリへの番地は
//       A サイクルの終わりに確定し、次のサイクル (B サイクル) にメモリへ出る。
//       これが「B サイクルでキャッシュを引く」の回路上の意味。
//
// [Netlist notes]
//   Inputs : AA_LD_GO / WW_ST_GO (060), AA_EAG_OUTPUT (120), STB_AD / STB_DT (090),
//            A_LS_ST_V / A_JB_SUBJECT_TO_BC (150), B_OPCLH / OP_*_V_NOCAN (050),
//            G_BC_JUST_SOLVED (210), port RANDOM_FOR_OPCLH
//   Outputs (FFs): LBS_WE / LBS_AD / LBS_DT -> output ports of stm_cntl (memory / stm_axi_master);
//                                             LBS_AD also goes to 050 (address compare, forwarding)
//                  OP_B_V / OP_B_OPC / OP_B_SUBJECT_TO_BC -> 050, 060
//                  OP_WAIT_*                               -> 050, 060
//                  OP_B_NEW                                -> output port of stm_cntl (stm_axi_master)
//   Circuit: a small FIFO of depth 2 (OP-WAIT -> OP-B).
//     - The D inputs of the OP-B FFs are 3:1 muxes "stay / move from OP-WAIT / accept new".
//       LBS_AD and LBS_DT are 32 bits each, so this is 64 bits of 3:1 muxes.
//     - The newly accepted address ACCEPTING_AD is a 2:1 mux of AA_EAG_OUTPUT and STB_AD.
//       The sum from the EAG in A goes straight into the LBS_AD FFs, so the memory address is
//       settled at the end of the A cycle and goes out to memory in the next cycle (the B cycle).
//       That is what "the cache is accessed in the B cycle" means in terms of the circuit.
// ---------------------------------------------------------------------

// OP-LBS in S-Unit : determine next state

// SU priority
// B-LS-LOG-AD should be later replaced by LBS-AD, when DAT is implemented.

// 【解説】OP-B の要求が終わる (ST2 は 1 サイクルで終わる, L/ST はキャッシュヒットで終わる)。
//         EXT_BUS=1 では ST2 もバスの書き込み完了 (RANDOM_FOR_OPCLH) を待つ。
// [Note] The OP-B request finishes (ST2 finishes in 1 cycle, L/ST on a cache hit).
//        With EXT_BUS=1, ST2 also waits for the bus write to complete (RANDOM_FOR_OPCLH).
assign OP_B_FORWARDING = (OP_B_OPC == SU_OPC_ST2) & (!EXT_BUS | RANDOM_FOR_OPCLH) // OP-Bの要求が終わる: ST2は1サイクル (外部バスなら書き込み完了待ち) ... / the OP-B request finishes: ST2 in 1 cycle (with an external bus, wait for the write) ...
		| B_OPCLH;                              // ...L/STはキャッシュの応答で (LUT4) / ... L/ST on the cache response (LUT4)
// 【解説】このサイクルに受け付ける要求 (A からの L/ST か, STB からの ST2) の種類と番地。
// [Note] Kind and address of the request accepted in this cycle (L/ST from A, or ST2 from the STB).
assign GO_SU = AA_LD_GO|WW_ST_GO;                       // このサイクルに新しい要求を受け付ける (OR) / a new request is accepted this cycle (OR)

assign ACCEPTING_OPC = (WW_ST_GO ? SU_OPC_ST2 : (A_LS_ST_V?SU_OPC_ST:SU_OPC_LD)); // 受け付ける要求の種類: ST2 / ST / LD (2bit, LUT3 x2) / kind of the accepted request: ST2 / ST / LD (2 bits, two LUT3s)
assign ACCEPTING_AD = (WW_ST_GO ? STB_AD : AA_EAG_OUTPUT); // 受け付ける番地: ST2ならSTB_AD, それ以外はAのEAG出力 (32bit 2:1 MUX) / accepted address: STB_AD for ST2, else the A EAG output (32-bit 2:1 mux)

// WAIT state : stay/accept from IU/clear

// 【解説】OP-WAIT の動き:
//           STAYS  : OP-B がまだ終わらず, 待ち中の要求もそのまま待つ
//           ACCEPT : OP-B が終わらないうちに新しい要求を受け付けた → OP-WAIT に入れる
// [Note] What OP-WAIT does:
//          STAYS  : OP-B has not finished, and the waiting request keeps waiting
//          ACCEPT : a new request was accepted before OP-B finished -> put it in OP-WAIT
assign OP_WAIT_STAYS = OP_B_V_NOCAN & !OP_B_FORWARDING & OP_WAIT_V_NOCAN; // OP-WAITが留まる: OP-Bが終わらず待ち要求がある (AND3) / OP-WAIT stays: OP-B not done and a waiting request (AND3)
assign OP_WAIT_ACCEPT = OP_B_V_NOCAN & !OP_B_FORWARDING & GO_SU; // 新要求をOP-WAITへ入れる: OP-Bが終わらないうちに来た (AND3) / put the new request into OP-WAIT: it came while OP-B is busy (AND3)


assign OP_WAIT_V_NEW = OP_WAIT_STAYS ? OP_WAIT_V   : OP_WAIT_ACCEPT ? 1 : 0; // OP-WAITの有効ビット: 留まる/受け付け/空 (FF+LUT) / OP-WAIT valid: stay / accept / empty (FF + LUT)
assign OP_WAIT_OPC_NEW = OP_WAIT_STAYS ? OP_WAIT_OPC : ACCEPTING_OPC; // 要求の種類: 留まるなら保持 (CE), そうでなければ新要求 (2bit) / kind: hold (CE) if staying, else the new one (2 bits)
assign OP_WAIT_WE_NEW = OP_WAIT_STAYS ? OP_WAIT_WE  : OP_WAIT_ACCEPT ? WW_ST_GO : 0; // 書き込みか (ST2なら1) / write? (1 for ST2)
assign OP_WAIT_AD_NEW = OP_WAIT_STAYS ? OP_WAIT_AD  : ACCEPTING_AD; // 番地: CE付きFF32本, D=ACCEPTING_AD / address: 32 FFs with CE, D = ACCEPTING_AD
assign OP_WAIT_DT_NEW = OP_WAIT_STAYS ? OP_WAIT_DT  : STB_DT; // 書き込みデータ: CE付きFF32本, D=STB_DT (LUT無し) / write data: 32 FFs with CE, D = STB_DT (no LUT)

// 【解説】投機的な (予測ミスで取り消される) 要求かどうか。
// [Note] Is the request speculative (cancelled on a misprediction)?
assign OP_WAIT_SUBJECT_TO_BC_NEW = OP_WAIT_STAYS ?      // 投機的な要求か: 留まるなら保持し解決で0 ... / speculative request: held, 0 once solved ...
				OP_WAIT_SUBJECT_TO_BC & !G_BC_JUST_SOLVED : // ...(留まる場合) / ... (when staying)
	OP_WAIT_ACCEPT ?  AA_LD_GO & A_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED : 0; // ...受け付けたAのL/STが投機中なら1 (LUT6) / ... 1 if the accepted A L/ST is speculative (LUT6)


//  OP-B state : stay/accept from IU/shift from WAIT/clear

// 【解説】OP-B の動き: 終わらなければ留まる / OP-WAIT から移す /
//         新しく受け付けた要求を入れる。
// [Note] What OP-B does: stays if not finished / takes the one from OP-WAIT /
//        takes the newly accepted request.
assign OP_B_STAYS = OP_B_V_NOCAN & !OP_B_FORWARDING;    // OP-Bが留まる: 有効で終わらない (AND) / OP-B stays: valid and not finished (AND)
//OP-B-ACCEPT	= GO-SU
assign OP_B_SHIFT = OP_WAIT_V_NOCAN;                    // OP-WAITからOP-Bへ移す (別名) / move OP-WAIT into OP-B (alias)


assign OP_B_V_NEW = OP_B_STAYS ? OP_B_V   : OP_B_SHIFT ? 1           : GO_SU; // OP-Bの有効ビット: 留まる/移す/新要求 (FF+LUT) / OP-B valid: stay / shift / new (FF + LUT)
assign OP_B_OPC_NEW = OP_B_STAYS ? OP_B_OPC : OP_B_SHIFT ? OP_WAIT_OPC : ACCEPTING_OPC; // OP-Bの種類: 保持はCEに, 残りがLUT4 (NETLIST.mdの例) / OP-B kind: hold goes to CE, the rest is a LUT4 (the NETLIST.md example)
// 【解説】メモリ (キャッシュ) への書き込み許可・番地・データ。
// [Note] Write enable, address and data to the memory (cache).
assign LBS_WE_NEW = OP_B_STAYS ? LBS_WE   : OP_B_SHIFT ? OP_WAIT_WE  : WW_ST_GO; // メモリ書き込み許可 → stm_memory / stm_axi_master (FF) / memory write enable -> stm_memory / stm_axi_master (FF)
assign LBS_AD_NEW = OP_B_STAYS ? LBS_AD   : OP_B_SHIFT ? OP_WAIT_AD  : // メモリ番地: 保持 / OP-WAITから / ... / memory address: hold / from OP-WAIT / ...
	    GO_SU      ? ACCEPTING_AD : 0;              // ...新要求の番地 / 0 (32bit 3:1 MUX+CE). AのEAG→このFF→Bでメモリへ / ... new address / 0 (32-bit 3:1 mux + CE). A EAG -> this FF -> memory in B
assign LBS_DT_NEW = OP_B_STAYS ? LBS_DT   : OP_B_SHIFT ? OP_WAIT_DT  : STB_DT; // メモリ書き込みデータ: 32bit 2:1 MUX (OP-WAIT/STB) + CE / memory write data: 32-bit 2:1 mux (OP-WAIT / STB) + CE

assign OP_B_SUBJECT_TO_BC_NEW =                         // OP-Bの要求が投機的か: ... / is the OP-B request speculative: ...
	    OP_B_STAYS ? OP_B_SUBJECT_TO_BC & !G_BC_JUST_SOLVED    : // ...留まるなら保持 (解決で0) ... / ... held while staying (0 once solved) ...
	    OP_B_SHIFT ? OP_WAIT_SUBJECT_TO_BC & !G_BC_JUST_SOLVED : // ...OP-WAITから移すならその値 ... / ... OP-WAIT's value when shifting ...
			 AA_LD_GO & A_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED; // ...新要求ならAの投機フラグ (LUT6) / ... A's speculative flag for a new one (LUT6)

// 【解説】(Verilog 版で追加) OP-B に新しい要求が入る (留まる以外で有効になる)。
//         stm_axi_master はこれで要求の切れ目を知る。
// [Note] (added in the Verilog version) A new request enters OP-B (becomes valid other than by staying).
//        stm_axi_master uses this to know where one request ends and the next begins.
assign OP_B_NEW_NEW = OP_B_V_NEW & !OP_B_STAYS;         // OP-Bに新しい要求が入った (1サイクルのパルス) → stm_axi_masterの開始合図 / a new request entered OP-B (1-cycle pulse) -> start strobe of stm_axi_master
