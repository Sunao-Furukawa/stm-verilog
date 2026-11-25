// =====================================================================
//  060_g_srq.vh  <-  hard/060-g-srq.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】各ステージの有効フラグと、S ユニットへの要求の制御
//
// xx_V_NOCAN = 「そのステージに命令があり、取り消されていない」。
// A_EAB は、A サイクルの命令が使うレジスタの値がまだ出来ていない状態を表し、
// インタロック (070_g_ilk.vh) の原因の 1 つになる。
//
// [Note] Valid flags of each stage, and control of the requests to the S unit
//
// xx_V_NOCAN = "the stage holds an instruction and it is not cancelled".
// A_EAB means a register the A-cycle instruction uses is not ready yet;
// it is one of the causes of interlock (070_g_ilk.vh).
//
// 【ネットリスト解説】
//   入力 : A_* (150 / 140 の FF), B_* (130 の FF), E_* (110 / 100 の FF),
//          STB_V (090), OP_B_* / OP_WAIT_* (160), CANCEL_BY_* / SU_*_RDY (050),
//          AA_EAG_OUTPUT (120 の加算器出力, 組合せ。I/O 判定用)
//   出力 : E_V_NOCAN / B_V_NOCAN / A_V_NOCAN -> 070 (インタロック), A_V_NOCAN -> 170
//          A_EAB      -> 070 (A_INTLK の原因)
//          AA_LD_GO   -> 070, 160 (S ユニットが A の L/ST を受け付けた)
//          WW_ST_GO   -> 070, 090, 160 (S ユニットが STB の ST2 を受け付けた)
//   回路の形:
//     ・A_EAB は 4bit 一致比較器 6 個 (E_WAD1 / B_WAD1 と A の 3 つの読み出し番号)
//       と AND/OR。データ (32bit) は通らず、番号とフラグだけの論理。
//     ・AA_LD_GO と WW_ST_GO は「A の L/ST を優先する」2 入力の調停回路。
//     ・AA_IO_LD_HOLD は EXT_BUS=1 のときだけ残る。入力の AA_EAG_OUTPUT は
//       A サイクルの 32bit 加算の結果なので、A → 060 → 070 (A_INTLK) → 140/150
//       (A の FF の保持) という経路が加算器の後ろにつながる。
//
// [Netlist notes]
//   Inputs : A_* (FFs in 150 / 140), B_* (FFs in 130), E_* (FFs in 110 / 100),
//            STB_V (090), OP_B_* / OP_WAIT_* (160), CANCEL_BY_* / SU_*_RDY (050),
//            AA_EAG_OUTPUT (adder output in 120, combinational; for the I/O check)
//   Outputs: E_V_NOCAN / B_V_NOCAN / A_V_NOCAN -> 070 (interlock), A_V_NOCAN -> 170
//            A_EAB      -> 070 (a cause of A_INTLK)
//            AA_LD_GO   -> 070, 160 (the S unit accepted the L/ST in A)
//            WW_ST_GO   -> 070, 090, 160 (the S unit accepted the ST2 from the STB)
//   Circuit:
//     - A_EAB is six 4-bit equality comparators (E_WAD1 / B_WAD1 against the 3 read numbers
//       of A) plus AND/OR. No 32-bit data passes through it; only numbers and flags.
//     - AA_LD_GO and WW_ST_GO form a 2-input arbiter that gives priority to the L/ST in A.
//     - AA_IO_LD_HOLD only remains with EXT_BUS=1. Its input AA_EAG_OUTPUT is the result of
//       the 32-bit add in the A cycle, so the path A -> 060 -> 070 (A_INTLK) -> 140/150
//       (hold of the A FFs) hangs off the end of the adder.
// ---------------------------------------------------------------------

// g-srq : codes related to interlocks and releases


// 【解説】有効かつ取り消されていない命令。分岐予測ミスで消えるのは
//         SUBJECT_TO_BC (未解決分岐の後に投機的に発行された) の命令だけ。
// [Note] Valid and not cancelled. A branch misprediction only removes instructions with
//        SUBJECT_TO_BC (issued speculatively after an unresolved branch).
assign E_V_NOCAN = E_V & (!CANCEL_BY_BC | !E_JB_SUBJECT_TO_BC) & !CANCEL_BY_INT;
assign B_V_NOCAN = B_V & (!CANCEL_BY_BC | !B_JB_SUBJECT_TO_BC) & !CANCEL_BY_INT;
assign A_V_NOCAN = A_V & (!CANCEL_BY_BC | !A_JB_SUBJECT_TO_BC) & !CANCEL_BY_INT;
// W: no intlk
// EAB : A-cyc is trying to use regs that are not yet ready, i.e.
//       reg data made by B-LS or E-LS(with EXU).

// 【解説】A サイクルの命令が読むレジスタを、まだ値の出ていない先行命令が書く:
//           ・E にいる LS パイプ命令で、ALU を通す (サブワード/RM 演算) か、ロードデータ未着
//           ・B にいる LS パイプ命令 (ロードデータは早くても B の終わり)
//         このとき A は次へ進めない。
//
// [Note] A register read by the A-cycle instruction is written by an earlier instruction whose value is not out yet:
//          - an LS-pipe instruction in E that goes through the ALU (sub-word / RM operation), or whose load data has not arrived
//          - an LS-pipe instruction in B (load data comes at the end of B at the earliest)
//        Then A cannot move on.
assign A_EAB = 
     E_V & E_WE1 & ((E_LS_OPCODE != 0) | E_LS_LD_V & !E_OPCLH_LCH) & (
    	  (E_WAD1 == A_LS_RADB) & (A_WE1 | A_LS_SETCC)
	| (E_WAD1 == A_EX_RAD1) & (A_WE2 | A_EX_SETCC)
	| (E_WAD1 == A_EX_RAD2) & (A_WE2 | A_EX_SETCC) & A_EX_OP2_IS_GR
      )
  |  B_V & B_WE1 & (
    	  (B_WAD1 == A_LS_RADB) & (A_WE1 | A_LS_SETCC)
	| (B_WAD1 == A_EX_RAD1) & (A_WE2 | A_EX_SETCC)
	| (B_WAD1 == A_EX_RAD2) & (A_WE2 | A_EX_SETCC) & A_EX_OP2_IS_GR
      );

// SU priority signals

// IU-SU interface has a LD-REQ(w/AD<0:31>) and a ST-REQ(w/AD<0:31> and
// DT<0:31>) buses.  Two requests can be simultaneously issued, although
// only one can be accepted.

// IU suppresses LD-REQ under the following  condition, giving
// higher priority to ST-REQ :

// 	1) B-V-NOCAN       & E-V-NOCAN & E-LS-ST-V & STB-V
// 	     --- LD-REQ can't pass anyway due to INTLK.

// When SU can accept both LD and ST, it turns on SU-OP-RDY and SU-ST-RDY.
// giving LD a higher priority.  When SU can accept only ST, SU sets
// SU-OP-RDY=0 and SU-ST-RDY=1.  Never SU-OP-RDY=1 and SU-ST-RDY=0.

//################# THIS IS FAKE!!! LEVEL-0 ONLY.  ####################
// 【解説】A サイクルの L/ST から S ユニットへのアクセス要求
//         (元コメント: レベル 0 用の仮の実装)。
//         ST2 が詰まっていてどうせ進めない場合は要求を出さない。
// [Note] Access request from the L/ST in the A cycle to the S unit
//        (original comment: a provisional implementation for level 0).
//        No request is made when ST2 is stuck and it could not proceed anyway.
assign AA_LD_REQ_VAL = A_V_NOCAN & !A_EAB & (A_LS_LD_V | A_LS_ST_V)
	 & !( STB_V & E_V_NOCAN & E_LS_ST_V & B_V_NOCAN )
	 & !AA_IO_LD_HOLD;

// 【解説】(Verilog 版で追加, EXT_BUS=1) I/O 領域へのロードは、確定するまで
//         S ユニットに渡さない (A サイクルで待たせる)。待つ条件:
//           ・未解決の条件分岐の先にある (予測ミスで取り消されるかもしれない)
//           ・B / E に先行する命令がいる (それが割り込みを起こすかもしれない)
//           ・先行するストアが終わっていない (STB, または S ユニットの ST2)。
//             I/O の読み書きの順序を守るため (STB からのフォワーディングもしない)
//         待っているロードは先行する命令に依存しないのでデッドロックはしない。
//         W の命令の割り込みは CANCEL_BY_INT で同じサイクルに A を取り消す。
//         同じ組で先に発行した EX 命令のオーバーフローだけは防げない。
//
// [Note] (added in the Verilog version, EXT_BUS=1) A load from the I/O region is not handed to the
//        S unit until it is certain (it waits in the A cycle). It waits while:
//          - it is beyond an unresolved conditional branch (a misprediction may cancel it)
//          - an earlier instruction is in B / E (it may raise an interrupt)
//          - an earlier store has not finished (STB, or ST2 in the S unit),
//            to keep the order of I/O reads and writes (no forwarding from the STB either)
//        The waiting load does not depend on the earlier instructions, so there is no deadlock.
//        An interrupt of the instruction in W cancels A in the same cycle through CANCEL_BY_INT.
//        Only an overflow of the EX instruction issued first in the same pair cannot be prevented.
assign AA_IO_LD_HOLD = A_LS_LD_V & is_io(AA_EAG_OUTPUT)
	 & ( A_JB_SUBJECT_TO_BC | B_V | E_V | STB_V
	   | OP_B_V & (OP_B_OPC == SU_OPC_ST2)
	   | OP_WAIT_V & (OP_WAIT_OPC == SU_OPC_ST2) );

// 【解説】ストアバッファ STB からの実書き込み (ST2) の要求。
// [Note] Request for the actual write (ST2) from the store buffer STB.
assign WW_ST_REQ_VAL = STB_V;

// 【解説】要求の受け付け。A からの L/ST を優先し、空いていれば ST2 を通す。
// [Note] Accepting requests. The L/ST from A has priority; ST2 goes through if free.
assign AA_LD_GO = SU_OP_RDY & AA_LD_REQ_VAL;
assign WW_ST_GO = SU_ST_RDY & WW_ST_REQ_VAL & !AA_LD_GO;
