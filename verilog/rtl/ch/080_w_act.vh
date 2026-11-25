// =====================================================================
//  080_w_act.vh  <-  hard/080-w-act.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】W サイクル: 命令の完了処理
//
// ・WSR によるシステムレジスタの書き込み
// ・PC の更新 (完了した命令数だけ進める / 分岐先 / 割り込み / RFE)
// ・PSW (CC, ユーザーモード, 割り込み種別) の更新
// ・割り込み時は XPSW / XPC / XLA に状態を退避して、TBR の番地へ飛ぶ
// GR への書き込みはレジスタファイル (stm_regfile) が W_WE1/2 を見て行う。
//
// [Note] W cycle: completion of instructions
//
// - writes system registers by WSR
// - updates PC (advance by the number of completed instructions / branch target / interrupt / RFE)
// - updates PSW (CC, user mode, interrupt type)
// - on an interrupt, saves the state in XPSW / XPC / XLA and jumps to the address in TBR
// GR writes are done by the register file (stm_regfile), which looks at W_WE1/2.
//
// 【ネットリスト解説】
//   入力 : W_* (090 で作る W サイクルの FF), WW_* (050 で W の FF から作る組合せ)
//   出力 (すべて FF): PC          -> 170 (再スタートのフェッチ番地), stm_cntl の出力ポート
//                     PSW_CC      -> 040 (解決済み BC の CC), 120 (RSR)
//                     PSW_USER    -> 015 (特権命令の合法性), 120
//                     TBR / CMPR / XPSW / XPC / XLA / SVR0 / SVR1 / PSW_TYPE -> 120 (RSR)
//                     CMPR        -> 050 (アドレス比較)
//                     START_TRIGGER (START_TRIGGER_BAR の反転) -> 170, 180, 190
//   回路の形:
//     ・システムレジスタ (TBR, CMPR, SVR0/1, XPSW, XPC, XLA) は 32bit の FF で、
//       D 入力は「WSR で自分の番号なら W_WDT2, それ以外は保持」。保持の分岐は
//       FF の CE 端子になり、W_WAD2 の 4bit 比較が CE を作る。
//     ・PC の次の値は 4:1 の優先 MUX (TBR / XPC / MODIFIED_PC / PC)。
//       MODIFIED_PC は W_TGT と INCREMENTED_PC (32bit 加算器 add_32_4) の 2:1 MUX。
//       W の FF → 加算 → MUX → PC の FF で 1 サイクル。
//     ・PC は「完了した命令の番地」を表す FF で、命令フェッチの番地ではない
//       (フェッチは 170 の IF_REQ_AD が先へ先へと進めている)。PC がフェッチに
//       使われるのは割り込み・RFE・状態変更の次のサイクル (START_TRIGGER) だけ。
//     ・XPSW_NEW の build_psw は配線だけなので、MODIFIED_CC (W の命令の CC を反映した
//       値) と PSW_USER / PSW_TYPE の FF がそのまま XPSW の該当ビットの MUX に入る。
//       XPSW の他のビット (CC/USER/TYPE 以外) は割り込みで 0 になる。
//
// [Netlist notes]
//   Inputs : W_* (W-cycle FFs made in 090), WW_* (combinational, made from the W FFs in 050)
//   Outputs (all FFs): PC          -> 170 (fetch address on restart), output port of stm_cntl
//                      PSW_CC      -> 040 (CC of a resolved BC), 120 (RSR)
//                      PSW_USER    -> 015 (legality of privileged instructions), 120
//                      TBR / CMPR / XPSW / XPC / XLA / SVR0 / SVR1 / PSW_TYPE -> 120 (RSR)
//                      CMPR        -> 050 (address compare)
//                      START_TRIGGER (inverse of START_TRIGGER_BAR) -> 170, 180, 190
//   Circuit:
//     - The system registers (TBR, CMPR, SVR0/1, XPSW, XPC, XLA) are 32-bit FFs whose D input
//       is "W_WDT2 if WSR writes this register, otherwise hold". The hold branch becomes the
//       FF's CE pin, and a 4-bit compare of W_WAD2 makes the CE.
//     - The next PC is a 4:1 priority mux (TBR / XPC / MODIFIED_PC / PC).
//       MODIFIED_PC is a 2:1 mux of W_TGT and INCREMENTED_PC (a 32-bit adder, add_32_4).
//       W FFs -> adder -> mux -> PC FFs in one cycle.
//     - PC is an FF holding "the address of the completed instruction", not the fetch address
//       (fetching runs ahead with IF_REQ_AD in 170). PC is used for fetching only in the cycle
//       after an interrupt, RFE or state change (START_TRIGGER).
//     - build_psw in XPSW_NEW is only wiring, so MODIFIED_CC (the CC including the W instruction)
//       and the PSW_USER / PSW_TYPE FFs go straight into the muxes of the matching XPSW bits.
//       The other bits of XPSW (other than CC/USER/TYPE) become 0 on an interrupt.
// ---------------------------------------------------------------------

// w-act : w-cycle activity

//  Modify GR,SR  -- not depend on intr (WE* or PRIVCODE is enough)

// 【解説】WSR で書けるシステムレジスタ:
//           TBR  : 割り込みハンドラの番地      CMPR : アドレス比較割り込みの番地
//           SVR0, SVR1 : 退避用の汎用レジスタ
// [Note] System registers WSR can write:
//          TBR  : address of the interrupt handler   CMPR : address for the address-compare interrupt
//          SVR0, SVR1 : general registers for saving values
assign TBR_NEW = (WW_WSR & (W_WAD2 == SYSREG_TBR)) ? W_WDT2 		: TBR;
assign CMPR_NEW = (WW_WSR & (W_WAD2 == SYSREG_CMPR)) ? W_WDT2 		: CMPR;
assign SVR0_NEW = (WW_WSR & (W_WAD2 == SYSREG_SVR0)) ? W_WDT2 		: SVR0;
assign SVR1_NEW = (WW_WSR & (W_WAD2 == SYSREG_SVR1)) ? W_WDT2 		: SVR1;

//  Compute new PC
// 【解説】PC の増分。2 命令同時に完了すれば 8, 1 命令なら 4。
//         割り込みを起こした命令は完了しないので、その分は進めない (0 または 4)。
// [Note] PC increment: 8 if two instructions complete together, 4 for one.
//        An instruction that raised an interrupt does not complete, so it is not counted (0 or 4).
assign PC_INCR_AMOUNT = ( W_IS_SUPERSCALAR & !W_JB_V & !WW_INTERRUPTION) ? 8 :
	       (  WW_LS_INT_V & (!W_IS_SUPERSCALAR | !W_FIRST_IS_EX)
	       |  WW_EX_INT_V & (!W_IS_SUPERSCALAR |  W_FIRST_IS_EX) ) ? 0 : 4;

// ---- #ifndef VHDL (C シミュレータ版を採用) ----
//      (#ifndef VHDL: the C-simulator version is used)
assign INCREMENTED_PC = add_32_4(PC,PC_INCR_AMOUNT);
// ---- #endif ----

// 【解説】taken の分岐が完了したら分岐先, そうでなければ次の命令。
// [Note] When a taken branch completes, the branch target; otherwise the next instruction.
assign MODIFIED_PC = ( W_JB_V & !WW_INTERRUPTION )  ? W_TGT : INCREMENTED_PC;

//  Compute new CC
// 【解説】CC を変える命令が完了したらその値。
// [Note] When an instruction that changes CC completes, its value.
assign MODIFIED_CC = W_SETCC ? W_CC : PSW_CC;

//  Modify PC,PSW-CC/USER/TYPE

// 【解説】両パイプで同時に割り込みが出たら、プログラム順で先の命令の方を採る
//         (EX が先の命令なら LS 側の割り込みは隠す)。
// [Note] If both pipes raise an interrupt at the same time, take the one of the instruction that is
//        earlier in program order (if EX is the earlier instruction, the LS interrupt is hidden).
assign WW_HIDE_LS = W_FIRST_IS_EX & WW_EX_INT_V;
assign WW_INTCODE = (WW_LS_INT_V & !WW_HIDE_LS) ? W_LS_INTCODE : W_EX_INTCODE;

// 【解説】PSW の各フィールドの更新。優先順は
//           割り込み (0 クリア / 種別を記録) > RFE (XPSW から復帰) > WSR で PSW へ書く > 通常
// [Note] Update of each PSW field. The priority is
//          interrupt (clear to 0 / record the type) > RFE (restore from XPSW) > WSR writing PSW > normal
assign PSW_CC_NEW = 	WW_INTERRUPTION 		? 0 :
		WW_RFE          		? pickup_cc(XPSW) :
		WW_WSR & (W_WAD2 == SYSREG_PSW) ? pickup_cc(W_WDT2) :
						  MODIFIED_CC;

assign PSW_USER_NEW =   WW_INTERRUPTION 		? 0 :
		WW_RFE          		? pickup_user(XPSW) :
		WW_WSR & (W_WAD2 == SYSREG_PSW) ? pickup_user(W_WDT2) :
						  PSW_USER;

assign PSW_TYPE_NEW =   WW_INTERRUPTION 		? zero_ext_5(WW_INTCODE) :
		WW_RFE          		? pickup_type(XPSW) :
		WW_WSR & (W_WAD2 == SYSREG_PSW) ? pickup_type(W_WDT2) :
						  PSW_TYPE;

// 【解説】PC の更新: 割り込み → TBR, RFE → XPC (退避した PC), 命令完了 → MODIFIED_PC。
// [Note] PC update: interrupt -> TBR, RFE -> XPC (the saved PC), instruction completed -> MODIFIED_PC.
assign PC_NEW =   WW_INTERRUPTION 		? TBR :
		WW_RFE          		? XPC :
		W_COMPLETE          		? MODIFIED_PC :
						  PC;
// 【解説】割り込み時に、割り込み直前の PSW を保存。
// [Note] On an interrupt, save the PSW from just before it.
assign XPSW_NEW =   WW_INTERRUPTION ? build_psw(MODIFIED_CC,PSW_USER,PSW_TYPE) :
		WW_WSR & (W_WAD2 == SYSREG_XPSW) ? W_WDT2 :
						   XPSW;

// 【解説】割り込み時に、戻り番地 (割り込んだ命令の番地) を保存。
// [Note] On an interrupt, save the return address (the address of the interrupted instruction).
assign XPC_NEW =   WW_INTERRUPTION 		? MODIFIED_PC :
		WW_WSR & (W_WAD2 == SYSREG_XPC) ? W_WDT2 :
						  XPC;

// 【解説】TLB 例外時にアクセス番地を保存 (TLB は未実装)。
// [Note] On a TLB exception, save the accessed address (the TLB is not implemented).
assign XLA_NEW =   WW_INTERRUPTION & (W_LS_INTCODE == INTCODE_TLB) & !WW_HIDE_LS
	 		? W_WDT1 :
		WW_WSR & (W_WAD2 == SYSREG_XLA) ? W_WDT2 :
						  XLA;


// 【解説】割り込み・RFE・状態変更の次のサイクルで、命令フェッチを PC から
//         やり直す合図 START_TRIGGER。反転して FF に入れているので、リセット直後
//         (FF=0) にも START_TRIGGER=1 となり、最初のフェッチが始まる。
// [Note] START_TRIGGER: the signal to restart instruction fetch from PC in the cycle after an interrupt,
//        RFE or state change. It is stored inverted in the FF, so right after reset
//        (FF=0) START_TRIGGER=1 too, and the first fetch starts.
assign START_TRIGGER_BAR_NEW = !( WW_INTERRUPTION | WW_RFE | WW_STATECHANGE );
assign START_TRIGGER = !START_TRIGGER_BAR;
