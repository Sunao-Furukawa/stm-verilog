// =====================================================================
//  050_op_lb1.vh  <-  hard/050-op-lb1.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
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
// ---- #endif ----

// This is actually in IU, but appears here becaused it's referenced here..

// 【解説】W サイクルにある特権命令の種類と、割り込みの有無 (本来は IU 側の信号)。
assign WW_WSR = (W_PRIVCODE == PRIVCODE_WSR);
assign WW_RFE = (W_PRIVCODE == PRIVCODE_RFE);
assign WW_LS_INT_V = (W_LS_INTCODE != 0);
assign WW_EX_INT_V = (W_EX_INTCODE != 0);
// ---- #ifndef VHDL (C シミュレータ版を採用) ----
// 【解説】WSR で PSW / TBR / CMPR (システムレジスタ 0〜3 番) を書いたら、
//         動作状態が変わるのでパイプラインを全部やり直す。
//         (VHDL 版の式は条件が逆になっていたので C 版を採用)
assign WW_STATECHANGE = WW_WSR & ((W_WAD2 & 12) == 0);
// ---- #else (VHDL 版: 参考) ----
// WW-STATECHANGE  = WW-WSR & (W-WAD2[0] | W-WAD2[1])
// ---- #endif ----
assign WW_INTERRUPTION = WW_LS_INT_V | WW_EX_INT_V;
// 【解説】割り込み・RFE・状態変更のときは、パイプライン中の全命令を取り消す。
assign CANCEL_BY_INT = WW_INTERRUPTION | WW_RFE | WW_STATECHANGE;

// Means that branch prediction failed.
// All insns with SUBJECT-TO-BC shall be cancelled by this.

// 【解説】分岐予測ミス。前サイクルで解決した条件分岐の結果が予測と違ったら、
//         予測側で投機的に発行した命令 (SUBJECT_TO_BC が 1 のもの) を取り消す。
assign CANCEL_BY_BC =  G_BC_JUST_SOLVED & (G_BC_JUST_TAKEN ^ G_BC_TKN_PREDICTED);

// Cancel and Valid-after-cancel

// 【解説】S ユニット内の要求の取り消し。ST2 (確定したストアの実書き込み) は
//         割り込みでも取り消さない。
assign OP_B_CANCELLED = (OP_B_OPC != SU_OPC_ST2) & CANCEL_BY_INT
		 | OP_B_SUBJECT_TO_BC & CANCEL_BY_BC;
assign OP_WAIT_CANCELLED = (OP_WAIT_OPC != SU_OPC_ST2) & CANCEL_BY_INT
		 | OP_WAIT_SUBJECT_TO_BC & CANCEL_BY_BC;

// 【解説】取り消されずに有効な要求。
assign OP_B_V_NOCAN = OP_B_V & !OP_B_CANCELLED;
assign OP_WAIT_V_NOCAN = OP_WAIT_V & !OP_WAIT_CANCELLED;

//# Lvl-1. No TLB miss exception yet. Only address-compare exception (which
//# in fact should belong to IU)

// 【解説】アドレス比較割り込み: L/ST のアドレスが CMPR レジスタと一致したら
//         INTCODE_CMP を出す (デバッグ用のブレークポイント)。TLB 例外は未実装。
assign OP_B_CMP_INT = OP_B_V & ((OP_B_OPC == SU_OPC_LD)|(OP_B_OPC == SU_OPC_ST))
			  & (LBS_AD == CMPR);
// 【解説】(Verilog 版で追加, EXT_BUS=1) バスがエラー応答 (SLVERR/DECERR) を返した
//         L/ST の読み出しは、データアクセス例外にする。コードは未実装だった
//         INTCODE_TLB を使うので、W で XLA に番地が保存される (090_e_act.vh)。
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
// ---- EXT_BUS=0 : 元の式 ----
// B-OPCLH = OP-B-V & ((OP-B-OPC==SU-OPC-LD)|(OP-B-OPC==SU-OPC-ST))
//    & ( RANDOM-FOR-OPCLH | (STB-V & (LBS-AD == STB-AD))
//       | (E-LS-ST-V & E-OPCLH-LCH & (LBS-AD == E-LS-LOG-AD))
//       | (OP-B-INTCODE != 0)  )
// ---- EXT_BUS=1 : Verilog 版で追加 ----
// 【解説】外部バスでは RANDOM_FOR_OPCLH は「バスの読み出しが終わった」の意味になる。
//         STB / E のストアと同じ番地なら、バスを待たずにそのストアのデータを
//         使ってヒット扱いにする (ストア→ロードのフォワーディング, OP_LBS_DATA)。
//         元の式もこの 2 条件でヒットにしていたが、データはメモリの値
//         (MEM_DT_OP) を使い、ロードについては B サイクルのバイパス
//         (100_b_dat.vh の BB_MEM_DATA) で補っていた。外部バスでは要求が
//         OP-B で何サイクルも待つので、命令が B にいるとは限らず、B サイクルの
//         バイパスでは間に合わない。そこで OP-B の番地 (LBS_AD) で直接選ぶ。
assign OP_FWD_E   = E_LS_ST_V & E_OPCLH_LCH & (LBS_AD == E_LS_LOG_AD);
assign OP_FWD_STB = STB_V & (LBS_AD == STB_AD);
// 【解説】(Verilog 版で追加, EXT_BUS=1) I/O 領域へのストアは B サイクルの読み出しを
//         しない (読むと状態が変わるデバイスがあるため)。読んだことにしてすぐ
//         ヒットを返し、データは 0。I/O 領域へはワード単位でストアすること
//         (サブワードのストアは残りのバイトが 0 になる)。
assign OP_B_IO_ST = OP_B_V & (OP_B_OPC == SU_OPC_ST) & is_io(LBS_AD);
assign B_OPCLH = OP_B_V & ((OP_B_OPC==SU_OPC_LD)|(OP_B_OPC==SU_OPC_ST))
	   & ( RANDOM_FOR_OPCLH | OP_FWD_STB | OP_FWD_E | OP_B_IO_ST
	      | (OP_B_INTCODE != 0)  );
// 【解説】OP-B の要求にバスアクセスが要るか (stm_axi_master へ)。
//         ST2 は書き込み, LD/ST は読み出し。フォワーディングで済む場合,
//         アドレス比較割り込みの場合, I/O 領域へのストアの読み出し,
//         取り消された場合は要らない。
assign OP_B_BUSREQ = OP_B_V_NOCAN
	   & ( (OP_B_OPC == SU_OPC_ST2)
	     | ((OP_B_OPC==SU_OPC_LD)|(OP_B_OPC==SU_OPC_ST))
	       & !OP_FWD_STB & !OP_FWD_E & !OP_B_IO_ST & !OP_B_CMP_INT );
// 【解説】S ユニットが新しい要求を受け付けられるか (待ち行列 OP-WAIT が空き)。
assign SU_OP_RDY = !OP_WAIT_V;
assign SU_ST_RDY = !OP_WAIT_V;

// LD-DT : set DT, maybe SLB

// No need to bypass from B-LBS-DT ;  No concurrent LD and ST

//# Lvl-1. Do DAT later!!

// 【解説】キャッシュから読んだデータ。ミス時は目印のダミー値 0xdead0a0a。
// 【解説】EXT_BUS=1 では上で説明したフォワーディングもここで行う
//         (E のストアの方が STB より新しいので優先)。
assign OP_LBS_DATA =  !B_OPCLH ? 32'hdead0a0a :
		 !EXT_BUS   ? MEM_DT_OP     :
		 OP_B_IO_ST ? 32'd0         :
		 OP_FWD_E   ? EE_ALU_OUTPUT :
		 OP_FWD_STB ? STB_DT        : MEM_DT_OP;
