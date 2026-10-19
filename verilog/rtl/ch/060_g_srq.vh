// =====================================================================
//  060_g_srq.vh  <-  hard/060-g-srq.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】各ステージの有効フラグと、S ユニットへの要求の制御
//
// xx_V_NOCAN = 「そのステージに命令があり、取り消されていない」。
// A_EAB は、A サイクルの命令が使うレジスタの値がまだ出来ていない状態を表し、
// インタロック (070_g_ilk.vh) の原因の 1 つになる。
// ---------------------------------------------------------------------

// g-srq : codes related to interlocks and releases


// 【解説】有効かつ取り消されていない命令。分岐予測ミスで消えるのは
//         SUBJECT_TO_BC (未解決分岐の後に投機的に発行された) の命令だけ。
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
assign AA_IO_LD_HOLD = A_LS_LD_V & is_io(AA_EAG_OUTPUT)
	 & ( A_JB_SUBJECT_TO_BC | B_V | E_V | STB_V
	   | OP_B_V & (OP_B_OPC == SU_OPC_ST2)
	   | OP_WAIT_V & (OP_WAIT_OPC == SU_OPC_ST2) );

// 【解説】ストアバッファ STB からの実書き込み (ST2) の要求。
assign WW_ST_REQ_VAL = STB_V;

// 【解説】要求の受け付け。A からの L/ST を優先し、空いていれば ST2 を通す。
assign AA_LD_GO = SU_OP_RDY & AA_LD_REQ_VAL;
assign WW_ST_GO = SU_ST_RDY & WW_ST_REQ_VAL & !AA_LD_GO;
