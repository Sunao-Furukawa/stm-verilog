// =====================================================================
//  150_d_act.vh  <-  hard/150-d-act.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】D → A の状態遷移 (命令の発行)
//
// D で発行を決めた ILS / IEX / IJB から、A サイクルの FF (タグ) を作る。
// A がインタロック中なら保持、D から来なければ有効ビットを 0。
// ---------------------------------------------------------------------

//  d-act
// With A-INTLK, BC is never issued in D-cyc, hence not set SOLVING-BC

// 【解説】A の有効ビット。
assign A_V_NEW = D_FWD | A_INTLK;

// 【解説】A の命令が未解決の条件分岐か。
assign A_JB_IS_BC_NEW = D_FWD   ? DD_ISSUEING_UNSOLVED_BC :
			   A_INTLK ? A_JB_IS_BC & !G_BC_JUST_SOLVED : 0;
// 【解説】未解決の BC があるときに発行された命令 = 投機的に実行中で、
//         予測ミスなら取り消される。
assign A_JB_SUBJECT_TO_BC_NEW = D_FWD   ? G_BC_PENDING :
			   A_INTLK ? A_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED : 0;
// 【解説】分岐を実行するか (untaken と分かった BC は 0)。
assign A_JB_V_NEW = D_FWD   ? IJB_V & !DD_ISSUEING_UNTAKEN_BC :
     A_INTLK ? A_JB_V & !(A_JB_IS_BC & G_BC_JUST_SOLVED & !G_BC_JUST_TAKEN) : 0;

// 【解説】この命令が、同時発行した BC の CC を作る (A/E で BC を解決する)。
assign A_LS_SOLVING_BC_NEW = A_INTLK ? A_LS_SOLVING_BC :
			D_FWD   ? DD_ISSUEING_UNSOLVED_BC_ON_D_LS : 0;
assign A_EX_SOLVING_BC_NEW = A_INTLK ? A_EX_SOLVING_BC      :
			D_FWD ?  DD_ISSUEING_UNSOLVED_BC_ON_D_EX : 0;
// 【解説】割り込みコード (不正命令) と特権命令の種類。
assign A_INTCODE_NEW = A_INTLK ? A_INTCODE	: D_FWD ?  DD_INTCODE : 0;
assign A_PRIVCODE_NEW = A_INTLK ? A_PRIVCODE	: D_FWD ?  DD_PRIVCODE : 0;

// Subword store loads data
// 【解説】LS パイプでメモリを読むか: ロード, サブワードのストア (読んで
//         一部を書き換える), メモリオペランド演算。
assign A_LS_LD_V_NEW = A_INTLK ? A_LS_LD_V	:
	D_FWD ? ILS_LS_FMT & !(ILS_STORE & (ILS_LENG == 0)) | ILS_EXRM_FMT : 0;
// 【解説】LS パイプが GR に書くか (ロード, GR に書く EX-RM 演算)。
assign A_WE1_NEW = A_INTLK ? A_WE1  	   	:
		D_FWD ? ILS_LS_FMT & !ILS_STORE
		  | ILS_EXRM_FMT & we_on(ILS_EXU_OPC) : 0;
// 【解説】ストアか。
assign A_LS_ST_V_NEW = A_INTLK ? A_LS_ST_V	: D_FWD ?  ILS_LS_FMT &  ILS_STORE : 0;

// 【解説】LS パイプでレジスタオペランド (ストアデータ / EX-RM の第 1 オペランド) を使うか。
assign A_LS_OPS_IS_GR_NEW = A_INTLK ? A_LS_OPS_IS_GR	:
		D_FWD ?  ILS_LS_FMT &  ILS_STORE |  ILS_EXRM_FMT : 0;
// 【解説】CC を変えるか (LS パイプは EX-RM, EX パイプは EX 命令)。
assign A_LS_SETCC_NEW = A_INTLK ? A_LS_SETCC	: D_FWD ?  ILS_EXRM_FMT &  ILS_SETCC : 0;

assign A_EX_SETCC_NEW = A_INTLK ? A_EX_SETCC	: D_FWD ?  IEX_SETCC : 0;
// 【解説】EX パイプが GR に書くか (EX 演算, リンク付き分岐, RSR)。
assign A_WE2_NEW = A_INTLK ? A_WE2	  	:
		D_FWD ?  we_on(IEX_EXU_OPC) | IJB_V & IJB_LINK
			| (DD_PRIVCODE == PRIVCODE_RSR) : 0;


// Tags that are not 'valid' tags can be written with CE = !A-INTLK.
// 【解説】書き込みレジスタ番号:
//           WAD1 : LS パイプ (RD)
//           WAD2 : EX パイプ (RD / 特権命令の RD / リンク付き分岐の RD)
//           LS_RADS : LS パイプのレジスタオペランド (ストアデータ等) の番号
assign A_WAD1_NEW = A_INTLK ? A_WAD1	:  ILS_RD_RS;
assign A_LS_RADS_NEW = A_INTLK ? A_LS_RADS	:  (ILS_LS_FMT ?  ILS_RD_RS : ILS_RS2);
assign A_WAD2_NEW = A_INTLK ? A_WAD2    :
		IEX_V ? IEX_RD : ((DD_PRIVCODE != 0) ? I0_EX_RD : IJB_RD_MASK);

// For byte/halfword load/store, opcode is
//    1  STORE HALFWORD(!BYTE) * *
// where ** are the last bits of address.
// In EXRM case, opcode is extended from 4 to 5 bits.
// ---- #ifndef VHDL (C シミュレータ版を採用) ----
// 【解説】E サイクルの ALU に使う 5bit opcode:
//           EX-RM        : EX の opcode (0〜15)
//           サブワード L/ST : 1 S H 0 0  (S=ストア, H=ハーフワード; 下位 2bit は後でアドレスから)
//           語 L/ST      : LDW (0) / STW (4)
assign A_LS_OPCODE_NEW = A_INTLK ? 	A_LS_OPCODE :
		ILS_EXRM_FMT ? ILS_EXU_OPC  :
		ILS_LS_FMT & (ILS_LENG!=0)  ?
		    16 | (ILS_STORE ? 8 : 0)|((ILS_LENG & 2) ? 4 : 0) :
		(ILS_STORE ? OPC_STW : OPC_LDW);
// ---- #else (VHDL 版: 参考) ----
// A-LS-OPCODE := A-INTLK ? 	A-LS-OPCODE :  
// 		ILS-EXRM-FMT ? B"0" . ILS-EXU-OPC  :
// 		ILS-LS-FMT & (ILS-LENG!=0)  ? 
// 		    B"1" . ILS-STORE . ILS-LENG[2] . B"00" :
// 		(ILS-STORE ? OPC-STW : OPC-LDW)
// ---- #endif ----

// 【解説】2 命令同時発行したか, 1 命令目が EX か, 2 命令目が分岐か (W での PC 計算や割り込み処理に使う)。
assign A_IS_SUPERSCALAR_NEW = A_INTLK ? A_IS_SUPERSCALAR :  DD_ISSUE_SECOND_INSN;
assign A_FIRST_IS_EX_NEW = A_INTLK ? A_FIRST_IS_EX    :  DD_FIRST_IS_EX;
assign A_LATTER_IS_JB_NEW = A_INTLK ? A_LATTER_IS_JB   :  DD_SECOND_IS_JB;
assign A_TGT_NEW = A_INTLK ? A_TGT 		 :  DD_TGT;

// If there's nothing else, OPC-EX is AU for LINK
// 【解説】EX パイプの EXU の opcode:
//           EX 命令はその opcode, 比較分岐は C, WSR は LDW (値をそのまま通す),
//           それ以外 (リンク付き分岐の戻り番地計算) は AU (加算)。
assign A_EX_OPCODE_NEW = A_INTLK ? A_EX_OPCODE :
		IEX_V  ? IEX_EXU_OPC :
		IJB_V & IJB_CMP 	? OPC_C :
		(DD_PRIVCODE == PRIVCODE_WSR) ? OPC_LDW : OPC_AU;
// 【解説】レジスタ間接分岐: 分岐先を A の EAG で計算する。
assign A_SET_EAG_TO_TGT_NEW = A_INTLK ? A_SET_EAG_TO_TGT :  IJB_REG;
