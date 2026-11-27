// =====================================================================
//  170_if_req.vh  <-  hard/170-if-req.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
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
//
// [Note] Generating instruction fetch (IF) requests
//
// Instructions are fetched 8 bytes (2 instructions) at a time, and the ID (0=A, 1=B)
// tells which queue A/B they go into. The reasons for a request (IF_CASE_*), in priority order:
//   START  : restart after an interrupt etc. -> from PC
//   J      : register-indirect branch -> the address produced by the EAG in the A cycle
//   NULL   : a register-indirect branch is being issued in D (address unknown yet, no request)
//   BA/BC  : PC-relative branch -> the target DD_TGT (an unresolved BC goes to "the other" queue)
//   normal : if the queue has room, the next 8 bytes
//
// 【ネットリスト解説】
//   入力 : PC / START_TRIGGER (080), AA_EAG_OUTPUT (120), DD_TGT / DD_ISSUEING_* /
//          IJB_IS_JA/JL (040), A_V_NOCAN (060), A_SET_EAG_TO_TGT (150), A_FWD / D_FWD (070),
//          EID / NIP_0..5 / V01 / V23 / V45 (010), IB_V / IB_AD / IB_ID / D_IF_AD_A/B (190 の FF)
//   出力 : IF_REQ_V / IF_REQ_AD / IF_REQ_ID -> 180 (SU_IF_RDY), 190 (IB_* の FF)
//          CANCEL_IB -> 190 ;  IWQ_FULL -> 190
//   回路の形:
//     ・IF_REQ_AD は 32bit の 4:1 優先 MUX (PC / AA_EAG_OUTPUT / DD_TGT / IF_INCR_OUT)。
//       IF_INCR_OUT は 32bit 加算器 (add_32_4, +8 か +0)。
//     ・この MUX の入力に A の EAG (加算器) と D の DD_TGT (加算器) が来るので、
//       「A の FF → EAG → IF_REQ_AD → IB_AD の FF」「IWQ → … → DD_TGT → IF_REQ_AD →
//       IB_AD の FF」がフェッチ側の長い経路。EXT_BUS=1 ではさらに IB_AD_NXT として
//       stm_icache のブロック RAM の番地入力まで伸びる。
//
// [Netlist notes]
//   Inputs : PC / START_TRIGGER (080), AA_EAG_OUTPUT (120), DD_TGT / DD_ISSUEING_* /
//            IJB_IS_JA/JL (040), A_V_NOCAN (060), A_SET_EAG_TO_TGT (150), A_FWD / D_FWD (070),
//            EID / NIP_0..5 / V01 / V23 / V45 (010), IB_V / IB_AD / IB_ID / D_IF_AD_A/B (FFs in 190)
//   Outputs: IF_REQ_V / IF_REQ_AD / IF_REQ_ID -> 180 (SU_IF_RDY), 190 (IB_* FFs)
//            CANCEL_IB -> 190 ;  IWQ_FULL -> 190
//   Circuit:
//     - IF_REQ_AD is a 32-bit 4:1 priority mux (PC / AA_EAG_OUTPUT / DD_TGT / IF_INCR_OUT).
//       IF_INCR_OUT is a 32-bit adder (add_32_4, +8 or +0).
//     - The inputs of this mux include the EAG of A (an adder) and DD_TGT of D (an adder), so
//       "A FFs -> EAG -> IF_REQ_AD -> IB_AD FFs" and "IWQ -> ... -> DD_TGT -> IF_REQ_AD ->
//       IB_AD FFs" are the long paths on the fetch side. With EXT_BUS=1 they extend further,
//       as IB_AD_NXT, to the address input of the block RAMs in stm_icache.
// ---------------------------------------------------------------------

// if-req


// Insn Fetch Request


// IWQ-FULL

// 【解説】キューが満杯 (6 語とも有効で, まだ先頭付近を実行中)。
// [Note] The queue is full (all 6 words valid, still executing near the front).
assign IWQ_FULL = (NIP_0 | NIP_1) & V01 & V23 & V45;    // キュー満杯: NIP<=1で6語すべて有効 (LUT5) → 続きのフェッチを止める / queue full: NIP<=1 and all 6 words valid (LUT5) -> stop sequential fetch

// IF-REQ-V/AD/ID decision

// 【解説】続きのフェッチ番地 = 最後に要求した番地 + 8。
//         要求中のもの (IB) がこのキュー宛てならその番地から, なければキュー末尾の番地から。
// [Note] Next fetch address = last requested address + 8.
//        From the pending request (IB) if it is for this queue, otherwise from the address at the end of the queue.
assign IF_INCR_1 = IB_V & (EID == IB_ID) ? IB_AD : EID ? D_IF_AD_B : D_IF_AD_A; // 続きのフェッチの基準番地: 要求中IBの番地かキュー末尾の番地 (32bit 3:1 MUX) / base of the next sequential fetch: pending IB address or queue-tail address (32-bit 3:1 mux)
assign IF_INCR_2 = IB_V & (EID == IB_ID)                // 増分: 要求中がこのキュー宛てか ... / increment: pending fetch is for this queue ...
		 | NIP_0 | NIP_1 | NIP_2 | NIP_3 | NIP_4 | NIP_5  ? 8 : 0; // ...キューに命令が残っていれば+8, 空(NIP=6,7)なら+0 (分岐先の8バイトを読み直す) / ... or insns remain: +8; empty (NIP 6,7): +0 (refetch the target's 8 bytes)
// ---- #ifndef VHDL (C シミュレータ版を採用) ----
//      (#ifndef VHDL: the C-simulator version is used)
assign IF_INCR_OUT = add_32_4(IF_INCR_1,IF_INCR_2);     // 次のフェッチ番地 = 基準 + 0/8: 32bit加算器 (下位3bitは素通し, CARRY4 x8) / next fetch address = base + 0/8: 32-bit adder (low 3 bits pass through, 8 CARRY4s)
// ---- #endif ----

// 【解説】フェッチ要求の理由 (上の説明を参照)。
// [Note] Reasons for a fetch request (see the explanation above).
assign IF_CASE_START = START_TRIGGER;                   // 理由1: 再スタート (PCから) / reason 1: restart (from PC)
assign IF_CASE_J = A_V_NOCAN & A_SET_EAG_TO_TGT;        // 理由2: Aのレジスタ間接分岐 (EAGの番地へ) / reason 2: register-indirect branch in A (to the EAG address)
assign IF_CASE_BA = DD_ISSUEING_TAKEN_BRANCH;           // 理由3: Dで成立が確定した分岐 (DD_TGTへ) / reason 3: branch known taken in D (to DD_TGT)
assign IF_CASE_BC = DD_ISSUEING_UNSOLVED_BC;            // 理由4: 未解決BC (分岐先をもう一方のキューへ) / reason 4: unsolved BC (target into the other queue)
assign IF_CASE_NULL = IJB_IS_JA | IJB_IS_JL;            // 理由5: JA/JL発行中 (分岐先がAで出るまで要求しない) / reason 5: JA/JL issuing (no request until A has the target)

// 【解説】フェッチ要求を出すか (分岐系は D/A が進めるときだけ)。
// [Note] Issue a fetch request? (branch cases only when D/A can move on)
assign IF_REQ_V = IF_CASE_START ? 1 : IF_CASE_J ? A_FWD : IF_CASE_NULL ? 0 : // フェッチ要求を出すか: 再スタートは必ず, Jは A_FWD ... / issue a fetch: always on restart, J needs A_FWD ...
	    IF_CASE_BA | IF_CASE_BC ? D_FWD : ! IWQ_FULL; // ...分岐はD_FWD, それ以外はキューに空きがあれば (LUT6) / ... branches need D_FWD, else when the queue has room (LUT6)

// 【解説】フェッチ番地。
// [Note] Fetch address.
assign IF_REQ_AD = IF_CASE_START ? PC : IF_CASE_J ? AA_EAG_OUTPUT : // フェッチ番地: PC / EAG出力 / ... / fetch address: PC / EAG output / ...
	    IF_CASE_BA | IF_CASE_BC ? DD_TGT : IF_INCR_OUT; // ...DD_TGT / 続き: 32bit 4:1優先MUX, 加算器2つの後ろなのでフェッチ側の長い経路 / ... DD_TGT / sequential: 32-bit 4:1 priority mux behind two adders (a long fetch path)

// 【解説】どちらのキューへ入れるか。未解決 BC の分岐先はもう一方のキューへ。
// [Note] Which queue it goes into. The target of an unresolved BC goes into the other queue.
assign IF_REQ_ID = IF_CASE_START ?  0 : IF_CASE_BC ? !EID  : EID; // 入れるキュー: 再スタートはA(0), 未解決BCは反対側, それ以外は今のキュー (LUT3) / target queue: A (0) on restart, the other one for an unsolved BC, else current (LUT3)

// 【解説】要求中のフェッチが無駄になったので取り消す (分岐した, 再スタート)。
// [Note] Cancel the pending fetch because it became useless (branched, restarted).
// 【解説】(Verilog 版で追加, EXT_BUS=1 のときだけ)
//         未解決 BC を発行したとき、分岐先を入れる側のキュー (!EID) 宛てのフェッチが
//         まだ届いていなければ、それも取り消す。
//         元の設計ではフェッチは要求の次のサイクルに必ず届くので、この BC の
//         分岐先の要求 (IF_CASE_BC) は必ず受け付けられる。外部バスではフェッチが
//         何サイクルも残るので、要求が受け付けられずに消え、次のサイクルからは
//         残っていた古いフェッチ (IB_AD) の続きを分岐先のキューに入れてしまう。
//         取り消せば IB が空き、次のサイクルに D_IF_AD (= 分岐先) から要求し直す。
//         取り消したフェッチのデータは、そのキューをクリア (CLEAR_NIP) するので元々使わない。
//
// [Note] (added in the Verilog version, only with EXT_BUS=1)
//        When an unresolved BC is issued and a fetch for the queue that will take the target (!EID)
//        has not arrived yet, cancel that too.
//        In the original design a fetch always arrives in the cycle after the request, so the
//        request for this BC's target (IF_CASE_BC) is always accepted. On an external bus a
//        fetch can stay pending for many cycles, so the request is not accepted and is lost,
//        and from the next cycle the continuation of the old fetch (IB_AD) would be put into the target queue.
//        Cancelling frees IB, and in the next cycle the request is made again from D_IF_AD (= the target).
//        The data of the cancelled fetch is never used, because that queue is cleared (CLEAR_NIP).
assign CANCEL_IB = IF_CASE_START | (IF_CASE_BA | IF_CASE_NULL) & (IB_ID == EID) // 要求中のフェッチを捨てる: 再スタート, または同じキュー宛てで分岐した ... / drop the pending fetch: restart, or a branch on the same queue ...
		 | EXT_BUS & IF_CASE_BC & D_FWD & (IB_ID != EID); // ...外部バスでは未解決BCの反対側キュー宛ても (EXT_BUS=0なら項ごと消える) / ... with an external bus also a fetch for the BC's other queue (term removed when EXT_BUS=0)
