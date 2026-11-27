// =====================================================================
//  150_d_act.vh  <-  hard/150-d-act.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】D → A の状態遷移 (命令の発行)
//
// D で発行を決めた ILS / IEX / IJB から、A サイクルの FF (タグ) を作る。
// A がインタロック中なら保持、D から来なければ有効ビットを 0。
//
// [Note] State transition D -> A (issuing instructions)
//
// The A-cycle FFs (tags) are made from ILS / IEX / IJB that D decided to issue.
// Held if A is interlocked; the valid bits become 0 if nothing comes from D.
//
// 【ネットリスト解説】
//   入力 : ILS_* / IEX_* / IJB_* (035), IEX_V / IJB_V / DD_INTCODE / DD_ISSUE_SECOND_INSN (030),
//          DD_* (020, 040), I0_EX_RD (015), D_FWD / A_INTLK (070), G_BC_* (210)
//   出力 (すべて FF): A_* -> 130 (B へのコピー), 120 (A_EX_OPCODE, A_PRIVCODE),
//                     060 / 070 (A_V, A_LS_LD_V/ST_V, A_WE1/2, A_*_SETCC, A_JB_SUBJECT_TO_BC),
//                     040 (A_*_SETCC), 140 (A_WAD2 / A_WE2 のバイパス),
//                     160 (A_LS_ST_V, A_JB_SUBJECT_TO_BC), 170 / 190 (A_SET_EAG_TO_TGT, A_JB_V),
//                     210 (A_EX_SOLVING_BC)
//   回路の形: D → A のパイプラインレジスタ。命令語のデコード結果を
//     「この命令は何をするか」のフラグ (A_LS_LD_V, A_WE1, A_LS_SETCC ...) と
//     番号 (A_WAD1, A_WAD2, A_LS_RADS) と opcode (A_LS_OPCODE 5bit, A_EX_OPCODE 4bit) に
//     分けて FF に入れる。以降のステージは命令語そのものを持たず、これらのタグだけで動く。
//     D_FWD が「発行」、A_INTLK が「保持」の選択信号 (070)。
//     A_TGT は 040 の加算器 DD_TGT の出力をそのまま受ける FF。
//
// [Netlist notes]
//   Inputs : ILS_* / IEX_* / IJB_* (035), IEX_V / IJB_V / DD_INTCODE / DD_ISSUE_SECOND_INSN (030),
//            DD_* (020, 040), I0_EX_RD (015), D_FWD / A_INTLK (070), G_BC_* (210)
//   Outputs (all FFs): A_* -> 130 (copy to B), 120 (A_EX_OPCODE, A_PRIVCODE),
//                      060 / 070 (A_V, A_LS_LD_V/ST_V, A_WE1/2, A_*_SETCC, A_JB_SUBJECT_TO_BC),
//                      040 (A_*_SETCC), 140 (bypass of A_WAD2 / A_WE2),
//                      160 (A_LS_ST_V, A_JB_SUBJECT_TO_BC), 170 / 190 (A_SET_EAG_TO_TGT, A_JB_V),
//                      210 (A_EX_SOLVING_BC)
//   Circuit: the D -> A pipeline register. The decoded instruction is split into flags saying
//     what it does (A_LS_LD_V, A_WE1, A_LS_SETCC ...), register numbers (A_WAD1, A_WAD2,
//     A_LS_RADS) and opcodes (A_LS_OPCODE 5 bits, A_EX_OPCODE 4 bits) and stored in FFs.
//     Later stages do not hold the instruction word; they work from these tags only.
//     D_FWD selects "issue" and A_INTLK selects "hold" (070).
//     A_TGT is an FF that takes the output of the adder DD_TGT in 040 as it is.
// ---------------------------------------------------------------------

//  d-act
// With A-INTLK, BC is never issued in D-cyc, hence not set SOLVING-BC

// 【解説】A の有効ビット。
// [Note] Valid bit of A.
assign A_V_NEW = D_FWD | A_INTLK;                       // Aの有効ビット: 発行 (D_FWD) か保持 (A_INTLK) (OR, FF1本) / A valid: issue (D_FWD) or hold (A_INTLK) (OR, 1 FF)

// 【解説】A の命令が未解決の条件分岐か。
// [Note] Is the instruction in A an unresolved conditional branch?
assign A_JB_IS_BC_NEW = D_FWD   ? DD_ISSUEING_UNSOLVED_BC : // Aの命令が未解決BCか: 発行時は040の判定 ... / is A's insn an unsolved BC: 040's decision on issue ...
			   A_INTLK ? A_JB_IS_BC & !G_BC_JUST_SOLVED : 0; // ...保持中に解決したら0 (LUT5) / ... cleared if solved while held (LUT5)
// 【解説】未解決の BC があるときに発行された命令 = 投機的に実行中で、
//         予測ミスなら取り消される。
// [Note] An instruction issued while there is an unresolved BC = running speculatively,
//        cancelled on a misprediction.
assign A_JB_SUBJECT_TO_BC_NEW = D_FWD   ? G_BC_PENDING : // 投機的に発行された命令か: 発行時に未解決BCがあれば1 ... / issued speculatively: 1 if a BC is pending at issue ...
			   A_INTLK ? A_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED : 0; // ...解決したら0 (LUT5) → 060, 160 / ... 0 once solved (LUT5) -> 060, 160
// 【解説】分岐を実行するか (untaken と分かった BC は 0)。
// [Note] Is the branch executed (0 for a BC found to be untaken)?
assign A_JB_V_NEW = D_FWD   ? IJB_V & !DD_ISSUEING_UNTAKEN_BC : // Aに実行する分岐があるか: 不成立と分かったBCは除く ... / A has a branch to execute: minus BCs known not taken ...
     A_INTLK ? A_JB_V & !(A_JB_IS_BC & G_BC_JUST_SOLVED & !G_BC_JUST_TAKEN) : 0; // ...保持中に不成立と解決しても消す (LUT6) / ... also dropped if resolved not-taken while held (LUT6)

// 【解説】この命令が、同時発行した BC の CC を作る (A/E で BC を解決する)。
// [Note] This instruction makes the CC of the BC issued with it (the BC is resolved in A/E).
assign A_LS_SOLVING_BC_NEW = A_INTLK ? A_LS_SOLVING_BC : // 同時発行のBCのCCをLS側が作る: 保持/発行/0 ... / LS side makes the co-issued BC's CC: hold / issue / 0 ...
			D_FWD   ? DD_ISSUEING_UNSOLVED_BC_ON_D_LS : 0; // ...(FF+LUT3) → 130→110→090で解決 / ... (FF + LUT3) -> resolved via 130 -> 110 -> 090
assign A_EX_SOLVING_BC_NEW = A_INTLK ? A_EX_SOLVING_BC      : // 同時発行のBCのCCをEX側が作る ... / EX side makes the co-issued BC's CC ...
			D_FWD ?  DD_ISSUEING_UNSOLVED_BC_ON_D_EX : 0; // ...→ 210でAのEXUのCCを見て解決 / ... -> 210 resolves it from the A EXU CC
// 【解説】割り込みコード (不正命令) と特権命令の種類。
// [Note] Interrupt code (illegal instruction) and kind of privileged instruction.
assign A_INTCODE_NEW = A_INTLK ? A_INTCODE	: D_FWD ?  DD_INTCODE : 0; // 不正命令の割り込みコード: 保持/発行/0 (bit0だけが意味を持つ) / illegal-insn code: hold / issue / 0 (only bit 0 matters)
assign A_PRIVCODE_NEW = A_INTLK ? A_PRIVCODE	: D_FWD ?  DD_PRIVCODE : 0; // 特権命令の種類: 2bit, 保持/発行/0 / privileged kind: 2 bits, hold / issue / 0

// Subword store loads data
// 【解説】LS パイプでメモリを読むか: ロード, サブワードのストア (読んで
//         一部を書き換える), メモリオペランド演算。
// [Note] Does the LS pipe read memory: loads, sub-word stores (read, then rewrite part),
//        and operations with a memory operand.
assign A_LS_LD_V_NEW = A_INTLK ? A_LS_LD_V	:       // LSパイプがメモリを読むか: ... / does the LS pipe read memory: ...
	D_FWD ? ILS_LS_FMT & !(ILS_STORE & (ILS_LENG == 0)) | ILS_EXRM_FMT : 0; // ...ロード, サブワードのストア(読んで書き換え), EX-RM (LUT6) / ... load, sub-word store (read-modify-write), EX-RM (LUT6)
// 【解説】LS パイプが GR に書くか (ロード, GR に書く EX-RM 演算)。
// [Note] Does the LS pipe write GR (loads, EX-RM operations that write GR)?
assign A_WE1_NEW = A_INTLK ? A_WE1  	   	:       // LSパイプがGRに書くか: ... / does the LS pipe write a GR: ...
		D_FWD ? ILS_LS_FMT & !ILS_STORE         // ...ロード ... / ... a load ...
		  | ILS_EXRM_FMT & we_on(ILS_EXU_OPC) : 0; // ...またはGRに書くEX-RM演算 (LUT6) / ... or an EX-RM op that writes a GR (LUT6)
// 【解説】ストアか。
// [Note] Is it a store?
assign A_LS_ST_V_NEW = A_INTLK ? A_LS_ST_V	: D_FWD ?  ILS_LS_FMT &  ILS_STORE : 0; // ストアか: 保持/発行/0 (FF+LUT) / store?: hold / issue / 0 (FF + LUT)

// 【解説】LS パイプでレジスタオペランド (ストアデータ / EX-RM の第 1 オペランド) を使うか。
// [Note] Does the LS pipe use a register operand (store data / first operand of EX-RM)?
assign A_LS_OPS_IS_GR_NEW = A_INTLK ? A_LS_OPS_IS_GR	: // レジスタオペランドRSを使うか: ... / uses register operand RS: ...
		D_FWD ?  ILS_LS_FMT &  ILS_STORE |  ILS_EXRM_FMT : 0; // ...ストア(データ)かEX-RM (LUT) / ... store (data) or EX-RM (LUT)
// 【解説】CC を変えるか (LS パイプは EX-RM, EX パイプは EX 命令)。
// [Note] Does it change CC (EX-RM in the LS pipe, EX instructions in the EX pipe)?
assign A_LS_SETCC_NEW = A_INTLK ? A_LS_SETCC	: D_FWD ?  ILS_EXRM_FMT &  ILS_SETCC : 0; // LSパイプがCCを変えるか (EX-RMのSETCC) / LS pipe sets CC (EX-RM SETCC)

assign A_EX_SETCC_NEW = A_INTLK ? A_EX_SETCC	: D_FWD ?  IEX_SETCC : 0; // EXパイプがCCを変えるか / EX pipe sets CC
// 【解説】EX パイプが GR に書くか (EX 演算, リンク付き分岐, RSR)。
// [Note] Does the EX pipe write GR (EX operations, branches with link, RSR)?
assign A_WE2_NEW = A_INTLK ? A_WE2	  	:       // EXパイプがGRに書くか: ... / does the EX pipe write a GR: ...
		D_FWD ?  we_on(IEX_EXU_OPC) | IJB_V & IJB_LINK // ...EX演算(C/CU以外) / リンク付き分岐 ... / ... EX op (not C/CU) / branch with link ...
			| (DD_PRIVCODE == PRIVCODE_RSR) : 0; // ...RSR (SRの値をGRへ) (LUT6) / ... RSR (SR value to a GR) (LUT6)


// Tags that are not 'valid' tags can be written with CE = !A-INTLK.
// 【解説】書き込みレジスタ番号:
//           WAD1 : LS パイプ (RD)
//           WAD2 : EX パイプ (RD / 特権命令の RD / リンク付き分岐の RD)
//           LS_RADS : LS パイプのレジスタオペランド (ストアデータ等) の番号
//
// [Note] Register numbers written:
//          WAD1 : LS pipe (RD)
//          WAD2 : EX pipe (RD / RD of a privileged instruction / RD of a branch with link)
//          LS_RADS : number of the LS-pipe register operand (store data etc.)
assign A_WAD1_NEW = A_INTLK ? A_WAD1	:  ILS_RD_RS;   // LS側の書き込み番号 = ILSのRD: CE付きFF4本 (保持=CE, LUT無し) / LS write number = ILS RD: 4 FFs with CE (hold = CE, no LUT)
assign A_LS_RADS_NEW = A_INTLK ? A_LS_RADS	:  (ILS_LS_FMT ?  ILS_RD_RS : ILS_RS2); // RSの番号: LSならRD/RS, EX-RMならRS (4bit 2:1 MUX + CE) / RS number: RD/RS for LS, RS for EX-RM (4-bit 2:1 mux + CE)
assign A_WAD2_NEW = A_INTLK ? A_WAD2    :               // EX側の書き込み番号: ... / EX write number: ...
		IEX_V ? IEX_RD : ((DD_PRIVCODE != 0) ? I0_EX_RD : IJB_RD_MASK); // ...EX命令のRD / 特権命令(RSR)のRD / 分岐のリンク先 (4bit 3:1 MUX + CE) / ... EX RD / priv (RSR) RD / branch link GR (4-bit 3:1 mux + CE)

// For byte/halfword load/store, opcode is
//    1  STORE HALFWORD(!BYTE) * *
// where ** are the last bits of address.
// In EXRM case, opcode is extended from 4 to 5 bits.
// ---- #ifndef VHDL (C シミュレータ版を採用) ----
//      (#ifndef VHDL: the C-simulator version is used)
// 【解説】E サイクルの ALU に使う 5bit opcode:
//           EX-RM        : EX の opcode (0〜15)
//           サブワード L/ST : 1 S H 0 0  (S=ストア, H=ハーフワード; 下位 2bit は後でアドレスから)
//           語 L/ST      : LDW (0) / STW (4)
//
// [Note] 5-bit opcode for the ALU of the E cycle:
//          EX-RM         : the EX opcode (0-15)
//          sub-word L/ST : 1 S H 0 0  (S=store, H=halfword; the low 2 bits come later from the address)
//          word L/ST     : LDW (0) / STW (4)
assign A_LS_OPCODE_NEW = A_INTLK ? 	A_LS_OPCODE :   // EのALUに使う5bit opcode: 保持 (CE) ... / 5-bit opcode for the E ALU: hold (CE) ...
		ILS_EXRM_FMT ? ILS_EXU_OPC  :           // ...EX-RMはEXのopcode ... / ... EX opcode for EX-RM ...
		ILS_LS_FMT & (ILS_LENG!=0)  ?           // ...サブワードL/STは ... / ... sub-word L/ST: ...
		    16 | (ILS_STORE ? 8 : 0)|((ILS_LENG & 2) ? 4 : 0) : // ...1 S H 0 0 (下位2bitは110で番地から) ... / ... 1 S H 0 0 (low 2 bits from the address in 110) ...
		(ILS_STORE ? OPC_STW : OPC_LDW);        // ...語はSTW(4)/LDW(0). ビットごとにLUT1個 (FF5本) / ... words: STW (4) / LDW (0). One LUT per bit (5 FFs)
// ---- #else (VHDL 版: 参考) ----
//      (#else: the VHDL version, for reference)
// A-LS-OPCODE := A-INTLK ? 	A-LS-OPCODE :  
// 		ILS-EXRM-FMT ? B"0" . ILS-EXU-OPC  :
// 		ILS-LS-FMT & (ILS-LENG!=0)  ? 
// 		    B"1" . ILS-STORE . ILS-LENG[2] . B"00" :
// 		(ILS-STORE ? OPC-STW : OPC-LDW)
// ---- #endif ----

// 【解説】2 命令同時発行したか, 1 命令目が EX か, 2 命令目が分岐か (W での PC 計算や割り込み処理に使う)。
// [Note] Dual-issued?, is the first EX?, is the second a branch? (used for the PC and interrupts in W)
assign A_IS_SUPERSCALAR_NEW = A_INTLK ? A_IS_SUPERSCALAR :  DD_ISSUE_SECOND_INSN; // 2命令同時発行したか: CE付きFF / dual issued?: FF with CE
assign A_FIRST_IS_EX_NEW = A_INTLK ? A_FIRST_IS_EX    :  DD_FIRST_IS_EX; // 1命令目がEXか: CE付きFF / first is EX?: FF with CE
assign A_LATTER_IS_JB_NEW = A_INTLK ? A_LATTER_IS_JB   :  DD_SECOND_IS_JB; // 2命令目が分岐か: CE付きFF / second is a branch?: FF with CE
assign A_TGT_NEW = A_INTLK ? A_TGT 		 :  DD_TGT; // PC相対の分岐先: 040のDD_TGT加算器の出力をCE付きFF32本で受ける / PC-relative target: DD_TGT adder output into 32 FFs with CE

// If there's nothing else, OPC-EX is AU for LINK
// 【解説】EX パイプの EXU の opcode:
//           EX 命令はその opcode, 比較分岐は C, WSR は LDW (値をそのまま通す),
//           それ以外 (リンク付き分岐の戻り番地計算) は AU (加算)。
// [Note] Opcode for the EX-pipe EXU:
//          an EX instruction uses its opcode, a compare branch C, WSR LDW (passes the value through),
//          anything else (return address of a branch with link) AU (add).
assign A_EX_OPCODE_NEW = A_INTLK ? A_EX_OPCODE :        // EXUのopcode (4bit): 保持 ... / EXU opcode (4 bits): hold ...
		IEX_V  ? IEX_EXU_OPC :                  // ...EX命令ならそのopcode ... / ... the EX insn's opcode ...
		IJB_V & IJB_CMP 	? OPC_C :       // ...比較分岐ならC (比較) ... / ... C (compare) for a compare branch ...
		(DD_PRIVCODE == PRIVCODE_WSR) ? OPC_LDW : OPC_AU; // ...WSRならLDW(素通し), 他はAU(リンクの戻り番地の加算) / ... LDW (pass through) for WSR, else AU (add for the link address)
// 【解説】レジスタ間接分岐: 分岐先を A の EAG で計算する。
// [Note] Register-indirect branch: the target is computed by the EAG in A.
assign A_SET_EAG_TO_TGT_NEW = A_INTLK ? A_SET_EAG_TO_TGT :  IJB_REG; // レジスタ間接分岐: 分岐先をAのEAGで作る → 130, 170 / register-indirect branch: target from the A EAG -> 130, 170
