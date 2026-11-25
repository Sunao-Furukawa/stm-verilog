// =====================================================================
//  050_op_lb1.vh  <-  hard/050-op-lb1.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】S ユニット (オペランド側キャッシュ) の出力と、取り消し信号
//
// LBS はオペランド用のキャッシュ (このモデルでは stm_memory)。
// S ユニットは IU (命令実行部) から L/ST の要求を受け、パイプライン段 OP-B で
// キャッシュを引く。要求が詰まったときは OP-WAIT に 1 つ待たせる (160_op_lb2.vh)。
// ストアは 2 回アクセスする:
//   ST  : B サイクルでのアクセス (キャッシュラインを確保し、サブワードなら元データを読む)
//   ST2 : W サイクルの後、ストアバッファ STB から実際に書き込む
// このファイルでは、全体で使う取り消し信号 (割り込み / 分岐予測ミス) も作っている。
//
// [Note] Outputs of the S unit (operand-side cache) and the cancel signals
//
// LBS is the cache for operands (in this model, stm_memory).
// The S unit takes L/ST requests from the IU (instruction unit) and accesses the cache in its
// pipeline stage OP-B. When requests pile up, one waits in OP-WAIT (160_op_lb2.vh).
// A store accesses it twice:
//   ST  : the access in the B cycle (reserves the cache line; for a sub-word store, reads the old data)
//   ST2 : after the W cycle, the actual write from the store buffer STB
// This file also makes the cancel signals used everywhere (interrupt / branch misprediction).
//
// 【ネットリスト解説】
//   入力 : W_PRIVCODE / W_WAD2 / W_LS_INTCODE / W_EX_INTCODE (090 の FF),
//          G_BC_JUST_SOLVED / _TAKEN / _TKN_PREDICTED (210 の FF),
//          OP_B_* / OP_WAIT_* / LBS_AD (160 の FF), CMPR (080 の FF),
//          STB_V / STB_AD / STB_DT (090 の FF), E_LS_ST_V / E_LS_LOG_AD (110 の FF),
//          E_OPCLH_LCH (100 の FF), EE_ALU_OUTPUT (090 の ALU, 組合せ),
//          ポート MEM_DT_OP / MEM_OP_ERR / RANDOM_FOR_OPCLH
//   出力 : CANCEL_BY_INT  -> 060, 070, 190 (全ステージの取り消し)
//          CANCEL_BY_BC   -> 060          (投機中の命令の取り消し)
//          WW_*           -> 080 (W サイクルの処理), 190 / 210 (WW_INTERRUPTION)
//          B_OPCLH        -> 100, 160 (キャッシュの応答)
//          OP_LBS_DATA    -> 100 (ロードデータ)
//          OP_B_INTCODE   -> 100 (S ユニットの例外)
//          OP_B_V_NOCAN / OP_WAIT_V_NOCAN -> 160
//          SU_OP_RDY / SU_ST_RDY -> 060
//          OP_B_BUSREQ    -> stm_cntl の出力ポート (stm_axi_master)
//   回路の形:
//     ・CANCEL_BY_INT / CANCEL_BY_BC はどちらも W / G の FF から 1〜2 段の浅い論理だが、
//       各ステージの xx_V_NOCAN → xx_FWD → ほぼ全 FF の更新 MUX と配られるので、
//       ネットリスト上はファンアウトが非常に大きい (合成ツールが複製することもある)。
//     ・OP_B_CMP_INT は LBS_AD と CMPR の 32bit 一致比較器。
//       OP_FWD_E / OP_FWD_STB も 32bit 一致比較器で、EXT_BUS=0 では OP_LBS_DATA の
//       選択に使われないが B_OPCLH には入るので残る。
//     ・OP_LBS_DATA は 32bit の 5:1 優先 MUX。EXT_BUS=0 なら定数の伝搬で
//       「!B_OPCLH ? 0xdead0a0a : MEM_DT_OP」の 2:1 MUX まで縮む。
//
// [Netlist notes]
//   Inputs : W_PRIVCODE / W_WAD2 / W_LS_INTCODE / W_EX_INTCODE (FFs in 090),
//            G_BC_JUST_SOLVED / _TAKEN / _TKN_PREDICTED (FFs in 210),
//            OP_B_* / OP_WAIT_* / LBS_AD (FFs in 160), CMPR (FF in 080),
//            STB_V / STB_AD / STB_DT (FFs in 090), E_LS_ST_V / E_LS_LOG_AD (FFs in 110),
//            E_OPCLH_LCH (FF in 100), EE_ALU_OUTPUT (ALU in 090, combinational),
//            ports MEM_DT_OP / MEM_OP_ERR / RANDOM_FOR_OPCLH
//   Outputs: CANCEL_BY_INT  -> 060, 070, 190 (cancels every stage)
//            CANCEL_BY_BC   -> 060          (cancels speculative instructions)
//            WW_*           -> 080 (W-cycle work), 190 / 210 (WW_INTERRUPTION)
//            B_OPCLH        -> 100, 160 (cache response)
//            OP_LBS_DATA    -> 100 (load data)
//            OP_B_INTCODE   -> 100 (S-unit exception)
//            OP_B_V_NOCAN / OP_WAIT_V_NOCAN -> 160
//            SU_OP_RDY / SU_ST_RDY -> 060
//            OP_B_BUSREQ    -> output port of stm_cntl (stm_axi_master)
//   Circuit:
//     - CANCEL_BY_INT / CANCEL_BY_BC are both shallow (1-2 levels from the W / G FFs), but they
//       reach xx_V_NOCAN of every stage -> xx_FWD -> the update muxes of almost every FF, so their
//       fan-out in the netlist is very large (synthesis may duplicate them).
//     - OP_B_CMP_INT is a 32-bit equality comparator of LBS_AD and CMPR.
//       OP_FWD_E / OP_FWD_STB are 32-bit equality comparators too. With EXT_BUS=0 they do not
//       select OP_LBS_DATA, but they still feed B_OPCLH, so they stay.
//     - OP_LBS_DATA is a 32-bit 5-input priority mux. With EXT_BUS=0, constant propagation
//       shrinks it to the 2:1 mux "!B_OPCLH ? 0xdead0a0a : MEM_DT_OP".
// ---------------------------------------------------------------------

// op-lb1 : OP-LBS in S-Unit :  generate output for other units
// Unit Interface Signals :
// in CANCEL-BY-BC 	<- ? , in CANCEL-BY-INT 	<- ?
// out SU-OP-RDY,SU-ST-RDY  -> g-srq ; B-OPCLH,OP-LBS-DATA<0:31>  -> b-dat
// out OP-B-INTCODE	-> ?

// For cache miss simulation
// ---- #ifndef VHDL ----
// RANDOM-FOR-OPCLH = random_clh ? ((random()&0xf)>=8) : 1
//   -> Verilog 版では stm_cntl の入力ポート RANDOM_FOR_OPCLH にした。
//      常に 1 ならキャッシュ常時ヒット、テストベンチから乱数を入れると
//      C 版の 'stmsiml -r' と同じキャッシュミス模擬になる。
//   -> In the Verilog version this became the input port RANDOM_FOR_OPCLH of stm_cntl.
//      Always 1 means the cache always hits; feeding random values from the testbench
//      gives the same cache-miss simulation as 'stmsiml -r' of the C version.
// ---- #endif ----

// This is actually in IU, but appears here becaused it's referenced here..

// 【解説】W サイクルにある特権命令の種類と、割り込みの有無 (本来は IU 側の信号)。
// [Note] Kind of privileged instruction in the W cycle, and whether there is an interrupt (really IU signals).
assign WW_WSR = (W_PRIVCODE == PRIVCODE_WSR);
assign WW_RFE = (W_PRIVCODE == PRIVCODE_RFE);
assign WW_LS_INT_V = (W_LS_INTCODE != 0);
assign WW_EX_INT_V = (W_EX_INTCODE != 0);
// ---- #ifndef VHDL (C シミュレータ版を採用) ----
//      (#ifndef VHDL: the C-simulator version is used)
// 【解説】WSR で PSW / TBR / CMPR (システムレジスタ 0〜3 番) を書いたら、
//         動作状態が変わるのでパイプラインを全部やり直す。
//         (VHDL 版の式は条件が逆になっていたので C 版を採用)
// [Note] When WSR writes PSW / TBR / CMPR (system registers 0-3), the operating state changes,
//        so the whole pipeline is restarted.
//        (the VHDL version had the condition reversed, so the C version is used)
assign WW_STATECHANGE = WW_WSR & ((W_WAD2 & 12) == 0);
// ---- #else (VHDL 版: 参考) ----
//      (#else: the VHDL version, for reference)
// WW-STATECHANGE  = WW-WSR & (W-WAD2[0] | W-WAD2[1])
// ---- #endif ----
assign WW_INTERRUPTION = WW_LS_INT_V | WW_EX_INT_V;
// 【解説】割り込み・RFE・状態変更のときは、パイプライン中の全命令を取り消す。
// [Note] On an interrupt, RFE or state change, every instruction in the pipeline is cancelled.
assign CANCEL_BY_INT = WW_INTERRUPTION | WW_RFE | WW_STATECHANGE;

// Means that branch prediction failed.
// All insns with SUBJECT-TO-BC shall be cancelled by this.

// 【解説】分岐予測ミス。前サイクルで解決した条件分岐の結果が予測と違ったら、
//         予測側で投機的に発行した命令 (SUBJECT_TO_BC が 1 のもの) を取り消す。
// [Note] Branch misprediction. If the outcome of the conditional branch resolved in the previous cycle
//        differs from the prediction, the instructions issued speculatively on the predicted side
//        (those with SUBJECT_TO_BC = 1) are cancelled.
assign CANCEL_BY_BC =  G_BC_JUST_SOLVED & (G_BC_JUST_TAKEN ^ G_BC_TKN_PREDICTED);

// Cancel and Valid-after-cancel

// 【解説】S ユニット内の要求の取り消し。ST2 (確定したストアの実書き込み) は
//         割り込みでも取り消さない。
// [Note] Cancelling requests inside the S unit. ST2 (the actual write of a committed store)
//        is not cancelled even by an interrupt.
assign OP_B_CANCELLED = (OP_B_OPC != SU_OPC_ST2) & CANCEL_BY_INT
		 | OP_B_SUBJECT_TO_BC & CANCEL_BY_BC;
assign OP_WAIT_CANCELLED = (OP_WAIT_OPC != SU_OPC_ST2) & CANCEL_BY_INT
		 | OP_WAIT_SUBJECT_TO_BC & CANCEL_BY_BC;

// 【解説】取り消されずに有効な要求。
// [Note] Requests that are valid and not cancelled.
assign OP_B_V_NOCAN = OP_B_V & !OP_B_CANCELLED;
assign OP_WAIT_V_NOCAN = OP_WAIT_V & !OP_WAIT_CANCELLED;

//# Lvl-1. No TLB miss exception yet. Only address-compare exception (which
//# in fact should belong to IU)

// 【解説】アドレス比較割り込み: L/ST のアドレスが CMPR レジスタと一致したら
//         INTCODE_CMP を出す (デバッグ用のブレークポイント)。TLB 例外は未実装。
// [Note] Address-compare interrupt: if the address of an L/ST equals the CMPR register,
//        raise INTCODE_CMP (a breakpoint for debugging). TLB exceptions are not implemented.
assign OP_B_CMP_INT = OP_B_V & ((OP_B_OPC == SU_OPC_LD)|(OP_B_OPC == SU_OPC_ST))
			  & (LBS_AD == CMPR);
// 【解説】(Verilog 版で追加, EXT_BUS=1) バスがエラー応答 (SLVERR/DECERR) を返した
//         L/ST の読み出しは、データアクセス例外にする。コードは未実装だった
//         INTCODE_TLB を使うので、W で XLA に番地が保存される (090_e_act.vh)。
// [Note] (added in the Verilog version, EXT_BUS=1) An L/ST read that got an error response from the bus
//        (SLVERR/DECERR) becomes a data access exception. It uses INTCODE_TLB, the code that
//        was unimplemented, so W saves the address in XLA (090_e_act.vh).
assign OP_B_BUS_ERR = EXT_BUS & OP_B_V
		  & ((OP_B_OPC == SU_OPC_LD)|(OP_B_OPC == SU_OPC_ST))
		  & RANDOM_FOR_OPCLH & MEM_OP_ERR;
assign OP_B_INTCODE = OP_B_CMP_INT ? INTCODE_CMP :
		      OP_B_BUS_ERR ? INTCODE_TLB : 0;

// From the cycle ST passes B-cyc to the cyc its ST2 passes, access to the
// same address will never  miss-hit, because cache line is held during that
// time.

// 【解説】OPCLH = オペランドキャッシュがデータを返した (ヒット)。
//         次の場合はヒット扱い:
//           ・乱数 (キャッシュミス模擬が無効なら常に 1)
//           ・STB や E のストアが同じアドレスを持っている (ラインを確保中なのでミスしない)
//           ・割り込みが出た (データは使わないので待たない)
//
// [Note] OPCLH = the operand cache returned the data (hit).
//        Treated as a hit when:
//          - the random input says so (always 1 when cache-miss simulation is off)
//          - the STB or the store in E has the same address (the line is reserved, so no miss)
//          - an interrupt was raised (the data is not used, so don't wait)
// ---- EXT_BUS=0 : 元の式 ----
//      (EXT_BUS=0: the original expression)
// B-OPCLH = OP-B-V & ((OP-B-OPC==SU-OPC-LD)|(OP-B-OPC==SU-OPC-ST))
//    & ( RANDOM-FOR-OPCLH | (STB-V & (LBS-AD == STB-AD))
//       | (E-LS-ST-V & E-OPCLH-LCH & (LBS-AD == E-LS-LOG-AD))
//       | (OP-B-INTCODE != 0)  )
// ---- EXT_BUS=1 : Verilog 版で追加 ----
//      (EXT_BUS=1: added in the Verilog version)
// 【解説】外部バスでは RANDOM_FOR_OPCLH は「バスの読み出しが終わった」の意味になる。
//         STB / E のストアと同じ番地なら、バスを待たずにそのストアのデータを
//         使ってヒット扱いにする (ストア→ロードのフォワーディング, OP_LBS_DATA)。
//         元の式もこの 2 条件でヒットにしていたが、データはメモリの値
//         (MEM_DT_OP) を使い、ロードについては B サイクルのバイパス
//         (100_b_dat.vh の BB_MEM_DATA) で補っていた。外部バスでは要求が
//         OP-B で何サイクルも待つので、命令が B にいるとは限らず、B サイクルの
//         バイパスでは間に合わない。そこで OP-B の番地 (LBS_AD) で直接選ぶ。
//
// [Note] On the external bus, RANDOM_FOR_OPCLH means "the bus read has finished".
//        If the address equals that of the store in STB / E, the data of that store is used
//        without waiting for the bus, and it counts as a hit (store-to-load forwarding, OP_LBS_DATA).
//        The original expression also made these two cases hits, but used the memory value
//        (MEM_DT_OP) as data and, for loads, patched it with the B-cycle bypass
//        (BB_MEM_DATA in 100_b_dat.vh). On the external bus a request may wait many cycles
//        in OP-B, so the instruction is not necessarily in B, and the B-cycle bypass is too late.
//        So the data is selected directly by the OP-B address (LBS_AD).
assign OP_FWD_E   = E_LS_ST_V & E_OPCLH_LCH & (LBS_AD == E_LS_LOG_AD);
assign OP_FWD_STB = STB_V & (LBS_AD == STB_AD);
// 【解説】(Verilog 版で追加, EXT_BUS=1) I/O 領域へのストアは B サイクルの読み出しを
//         しない (読むと状態が変わるデバイスがあるため)。読んだことにしてすぐ
//         ヒットを返し、データは 0。I/O 領域へはワード単位でストアすること
//         (サブワードのストアは残りのバイトが 0 になる)。
//
// [Note] (added in the Verilog version, EXT_BUS=1) A store to the I/O region does not do the B-cycle read
//        (some devices change state when read). It pretends to have read and returns a hit at once,
//        with data 0. Store to the I/O region in whole words
//        (a sub-word store would set the other bytes to 0).
assign OP_B_IO_ST = OP_B_V & (OP_B_OPC == SU_OPC_ST) & is_io(LBS_AD);
assign B_OPCLH = OP_B_V & ((OP_B_OPC==SU_OPC_LD)|(OP_B_OPC==SU_OPC_ST))
	   & ( RANDOM_FOR_OPCLH | OP_FWD_STB | OP_FWD_E | OP_B_IO_ST
	      | (OP_B_INTCODE != 0)  );
// 【解説】OP-B の要求にバスアクセスが要るか (stm_axi_master へ)。
//         ST2 は書き込み, LD/ST は読み出し。フォワーディングで済む場合,
//         アドレス比較割り込みの場合, I/O 領域へのストアの読み出し,
//         取り消された場合は要らない。
//
// [Note] Does the OP-B request need a bus access (to stm_axi_master)?
//        ST2 is a write, LD/ST are reads. Not needed when forwarding is enough,
//        on an address-compare interrupt, for the read of a store to the I/O region,
//        or when the request was cancelled.
assign OP_B_BUSREQ = OP_B_V_NOCAN
	   & ( (OP_B_OPC == SU_OPC_ST2)
	     | ((OP_B_OPC==SU_OPC_LD)|(OP_B_OPC==SU_OPC_ST))
	       & !OP_FWD_STB & !OP_FWD_E & !OP_B_IO_ST & !OP_B_CMP_INT );
// 【解説】S ユニットが新しい要求を受け付けられるか (待ち行列 OP-WAIT が空き)。
// [Note] Can the S unit accept a new request (the waiting slot OP-WAIT is free)?
assign SU_OP_RDY = !OP_WAIT_V;
assign SU_ST_RDY = !OP_WAIT_V;

// LD-DT : set DT, maybe SLB

// No need to bypass from B-LBS-DT ;  No concurrent LD and ST

//# Lvl-1. Do DAT later!!

// 【解説】キャッシュから読んだデータ。ミス時は目印のダミー値 0xdead0a0a。
// [Note] Data read from the cache. On a miss, the marker dummy value 0xdead0a0a.
// 【解説】EXT_BUS=1 では上で説明したフォワーディングもここで行う
//         (E のストアの方が STB より新しいので優先)。
// [Note] With EXT_BUS=1 the forwarding explained above is also done here
//        (the store in E is newer than the STB, so it has priority).
assign OP_LBS_DATA =  !B_OPCLH ? 32'hdead0a0a :
		 !EXT_BUS   ? MEM_DT_OP     :
		 OP_B_IO_ST ? 32'd0         :
		 OP_FWD_E   ? EE_ALU_OUTPUT :
		 OP_FWD_STB ? STB_DT        : MEM_DT_OP;
