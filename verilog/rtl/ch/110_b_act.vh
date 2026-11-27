// =====================================================================
//  110_b_act.vh  <-  hard/110-b-act.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】B → E の状態遷移
//
// 元コメントの通り 3 つの場合がある:
//   1. INTLK : E がインタロック → E は留まる (分岐解決とデータのバイパスだけ行う)
//   2. CLEAR : E が空になる (B から何も来ない) → 有効ビットをクリア
//   3. SLIDE : B の命令が E へ進む (B_FWD) → B のタグを E へコピー
// 有効ビット類は上の 3 通りで決め、それ以外のタグ (番地, データなど) は
// E がインタロックでなければ単にコピーする。
//
// [Note] State transition B -> E
//
// As the original comment says, there are 3 cases:
//   1. INTLK : E is interlocked -> E stays (only branch resolution and data bypass are done)
//   2. CLEAR : E becomes empty (nothing comes from B) -> clear the valid bits
//   3. SLIDE : the instruction in B moves into E (B_FWD) -> copy the tags of B to E
// The valid bits are decided by these 3 cases; the other tags (addresses, data, ...)
// are simply copied when E is not interlocked.
//
// 【ネットリスト解説】
//   入力 : B_* (130 の FF), B_FWD / E_INTLK / D_FWD (070), G_BC_JUST_SOLVED / _TAKEN (210),
//          DD_ISSUEING_UNSOLVED_BC_ON_B_LS / _ON_E_LS (040)
//   出力 (すべて FF): E_* -> 090 (E サイクルの処理), 060 / 070 (インタロック),
//                     040 (E_*_SETCC, E_EX_CC), 100 / 140 (E_WAD/WE/EX_RES のバイパス),
//                     050 (E_LS_ST_V, E_LS_LOG_AD)
//   回路の形: B → E のパイプラインレジスタそのもの。FF の D 入力の形は 2 種類:
//     ・有効ビット類 (E_V, E_WE1 ...) : 「B_FWD ? B の値 : E_INTLK ? 保持 : 0」の
//       3:1 MUX。FF 1 本ごとに LUT 1 個 (入力 = B の値, 自分の Q, B_FWD, E_INTLK)。
//     ・データ類 (E_LS_LOG_AD, E_EX_RES ...) : 「!E_INTLK ? B の値 : 保持」なので、
//       LUT は要らず、B の FF の Q を E の FF の D に直接つなぎ、!E_INTLK を CE にする。
//       32bit の値はこの形なので、ステージ間の転送はほとんど配線と CE で済む。
//     ・E_LS_OPCODE_NEW だけはアドレス下位 2bit を opcode に埋め込む小さな論理が入る。
//     ・E_LS_OPS_IS_GR, E_LS_RADS は (元の #if 0 の式でしか使われないので) 合成で消える。
//
// [Netlist notes]
//   Inputs : B_* (FFs in 130), B_FWD / E_INTLK / D_FWD (070), G_BC_JUST_SOLVED / _TAKEN (210),
//            DD_ISSUEING_UNSOLVED_BC_ON_B_LS / _ON_E_LS (040)
//   Outputs (all FFs): E_* -> 090 (E-cycle work), 060 / 070 (interlock),
//                      040 (E_*_SETCC, E_EX_CC), 100 / 140 (bypass of E_WAD/WE/EX_RES),
//                      050 (E_LS_ST_V, E_LS_LOG_AD)
//   Circuit: this is the B -> E pipeline register itself. The D inputs of the FFs have two shapes:
//     - valid bits (E_V, E_WE1 ...) : a 3:1 mux "B_FWD ? value from B : E_INTLK ? hold : 0".
//       One LUT per FF (inputs = value from B, own Q, B_FWD, E_INTLK).
//     - data (E_LS_LOG_AD, E_EX_RES ...) : "!E_INTLK ? value from B : hold", so no LUT is
//       needed: the Q of the B FF goes straight to the D of the E FF, with !E_INTLK on CE.
//       32-bit values all have this shape, so moving data between stages is mostly wires and CE.
//     - Only E_LS_OPCODE_NEW has a little logic that puts the low 2 address bits into the opcode.
//     - E_LS_OPS_IS_GR and E_LS_RADS disappear in synthesis (they are only used in the old #if 0 code).
// ---------------------------------------------------------------------

// b-act
// Three cases are possible :

//  1.INTLK) E interlocks(E-INTLK).  Handles only BC decision and data bypass.
//  2.CLEAR) E is (or becomes) empty(!E-INTLK & !B-FWD).  Clears valid flags.
//  3.SLIDE) B enters E (B-FWD).  B slides into E.

//  valids ---   data: NOW-FWD and (set-data) ,  CE  : !NXT-INTLK
//  others ---   data: (set-data itself)      ,  CE  : !NXT-INTLK

// E-STB-INTLK and B-LMD-INTLK never occur at the same time; if B-cyc is
// load or store (, maybe sending OPCLH,) and E-cyc is store  , W-cyc
// store request by STB-V is always accepted by SU and E-STB-INTLK never
// occurs.  OPCLH is never made to wait by E-STB-INTLK.

   // 【解説】E の有効ビット: B から来れば 1, E が留まるなら保持, それ以外は 0。
   // [Note] Valid bit of E: 1 if something comes from B, held if E stays, otherwise 0.
   assign E_V_NEW = B_FWD   ? 1 : E_INTLK ? E_V : 0;    // Eの有効ビット: B_FWD→1 / E_INTLK→保持 / else 0. FF1本+LUT3 / E valid: B_FWD -> 1, E_INTLK -> hold, else 0. 1 FF + LUT3

// JB-related tags need special handling; may be modified even when interlock
   // 【解説】分岐関係のタグは、インタロック中でも分岐の解決 (G_BC_JUST_SOLVED) で
   //         更新する。解決したら「未解決 BC」「投機中」のフラグを落とし、
   //         untaken と分かった分岐は無効にする。
   // [Note] Branch tags are updated by branch resolution (G_BC_JUST_SOLVED) even during an interlock.
   //        Once resolved, the "unresolved BC" and "speculative" flags are dropped, and a branch
   //        found to be untaken is invalidated.
   assign E_JB_IS_BC_NEW = B_FWD   ? B_JB_IS_BC & !G_BC_JUST_SOLVED : // EのBCが未解決か: Bから来た値 ... / is E's BC unsolved: value from B ...
			   E_INTLK ? E_JB_IS_BC & !G_BC_JUST_SOLVED : 0; // ...か保持の値を, 解決した(G_BC_JUST_SOLVED)ら0に (LUT5) / ... or held value, cleared once solved (G_BC_JUST_SOLVED) (LUT5)
   assign E_JB_SUBJECT_TO_BC_NEW = B_FWD   ? B_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED : // 未解決分岐の先の投機命令か: 同じ形 ... / speculative behind an unsolved branch: same form ...
			   E_INTLK ? E_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED : 0; // ...解決したら投機でなくなる (LUT5) / ... no longer speculative once solved (LUT5)
   assign E_JB_V_NEW =                                  // Eに分岐があるか: ... / branch present in E: ...
      B_FWD   ? B_JB_V & !(B_JB_IS_BC & G_BC_JUST_SOLVED & !G_BC_JUST_TAKEN) : // ...Bから来たBCが不成立と解決したら消す ... / ... drop a BC from B resolved not-taken ...
      E_INTLK ? E_JB_V & !(E_JB_IS_BC & G_BC_JUST_SOLVED & !G_BC_JUST_TAKEN) : 0; // ...留まっている分も同様 (LUT6 1~2個) / ... same for one held in E (1-2 LUT6s)
   // 【解説】この LS 命令が、未解決 BC の CC を作る命令か。D で BC を発行した
   //         サイクルに、その CC を作る命令が B/E にいた場合もここでセットする。
   // [Note] Is this LS instruction the one that makes the CC of the unresolved BC? It is also set here
   //        when that instruction was in B/E in the cycle the BC was issued in D.
   assign E_LS_SOLVING_BC_NEW =                         // このLS命令が未解決BCのCCを作るか: ... / does this LS insn make the unsolved BC's CC: ...
	B_FWD   ? B_LS_SOLVING_BC | DD_ISSUEING_UNSOLVED_BC_ON_B_LS & D_FWD : // ...Bからの値, またはBCを今発行しCCの作り手がBにいる ... / ... value from B, or a BC issued now whose CC maker is in B ...
	E_INTLK ? E_LS_SOLVING_BC | DD_ISSUEING_UNSOLVED_BC_ON_E_LS & D_FWD : 0; // ...保持の値, または作り手がEにいる (LUT6) → 090/210 / ... held value, or maker is in E (LUT6) -> 090/210

// These tags are just copied unmodified:
   // 【解説】以下のタグは変更せずにそのままコピーする。
   // [Note] The tags below are copied unchanged.
   assign E_LS_LD_V_NEW = B_FWD ? B_LS_LD_V  	: E_INTLK ? E_LS_LD_V    : 0; // ロードか: 3:1 MUX (B値/保持/0) = FF1本+LUT3 / load?: 3:1 mux (B / hold / 0) = 1 FF + LUT3
   assign E_LS_ST_V_NEW = B_FWD ?  B_LS_ST_V 	: E_INTLK ? E_LS_ST_V    : 0; // ストアか: 同じ形 / store?: same form
   assign E_WE1_NEW = B_FWD ?  B_WE1 	: E_INTLK ? E_WE1        : 0; // LS側GR書き込み: 同じ形 / LS GR write: same
   assign E_WE2_NEW = B_FWD ?  B_WE2 	: E_INTLK ? E_WE2        : 0; // EX側GR書き込み: 同じ形 / EX GR write: same
   assign E_LS_SETCC_NEW = B_FWD ?  B_LS_SETCC  : E_INTLK ? E_LS_SETCC   : 0; // LSがCCを変える: 同じ形 / LS sets CC: same
   assign E_EX_SETCC_NEW = B_FWD ?  B_EX_SETCC  : E_INTLK ? E_EX_SETCC   : 0; // EXがCCを変える: 同じ形 / EX sets CC: same
   assign E_EX_INTCODE_NEW = B_FWD ?  B_INTCODE   : E_INTLK ? E_EX_INTCODE : 0; // EX側の割り込みコード: 3bit x 同じ形 / EX interrupt code: 3 bits of the same form
   assign E_PRIVCODE_NEW = B_FWD ?  B_PRIVCODE  : E_INTLK ? E_PRIVCODE   : 0; // 特権命令の種類: 2bit x 同じ形 / privileged kind: 2 bits of the same form

// Tags that are not 'valid' tags can be copied with CE = !E-INTLK.
   // 【解説】有効ビット以外のタグは E がインタロックでなければコピー (CE = !E_INTLK)。
   // [Note] Tags other than valid bits are copied when E is not interlocked (CE = !E_INTLK).
   assign E_LS_LOG_AD_NEW = !E_INTLK ?  B_LS_LOG_AD  	: E_LS_LOG_AD; // L/ST番地: D=B_LS_LOG_ADのQ直結, CE=!E_INTLK (LUT無しのFF32本) / L/ST address: D wired to B_LS_LOG_AD, CE = !E_INTLK (32 FFs, no LUT)
   assign E_WAD1_NEW = !E_INTLK ?  B_WAD1    	: E_WAD1; // LS側の書き込み番号: CE付きFF4本 / LS write number: 4 FFs with CE
   assign E_WAD2_NEW = !E_INTLK ?  B_WAD2    	: E_WAD2; // EX側の書き込み番号: CE付きFF4本 / EX write number: 4 FFs with CE
   assign E_LS_OPS_IS_GR_NEW = !E_INTLK ?  B_LS_OPS_IS_GR 	: E_LS_OPS_IS_GR; // 旧版(#if 0)用: 使われず合成で消える / for the old #if 0 code: unused, removed
   assign E_LS_RADS_NEW = !E_INTLK ?  B_LS_RADS   	: E_LS_RADS; // 旧版用: 使われず消える / for the old code: unused, removed
   assign E_EX_RES_NEW = !E_INTLK ?  B_EX_RES 	: E_EX_RES; // EXの結果: CE付きFF32本 → 090のW_WDT2, 100/140のバイパス / EX result: 32 FFs with CE -> W_WDT2 in 090, bypass in 100/140
   assign E_EX_CC_NEW = !E_INTLK ?  B_EX_CC  	: E_EX_CC; // EXのCC: CE付きFF2本 → 040のフォワード, 090のW_CC / EX CC: 2 FFs with CE -> forwarding in 040, W_CC in 090
   assign E_TGT_NEW = !E_INTLK ?  B_TGT 		: E_TGT; // 分岐先: CE付きFF32本 / branch target: 32 FFs with CE
   assign E_IS_SUPERSCALAR_NEW = !E_INTLK ?  B_IS_SUPERSCALAR : E_IS_SUPERSCALAR; // 2命令の組か: CE付きFF / pair?: FF with CE
   assign E_LATTER_IS_JB_NEW = !E_INTLK ?  B_LATTER_IS_JB   : E_LATTER_IS_JB; // 後の命令が分岐か: CE付きFF / latter is a branch?: FF with CE
   assign E_FIRST_IS_EX_NEW = !E_INTLK ?  B_FIRST_IS_EX    : E_FIRST_IS_EX; // 先の命令がEXか: CE付きFF / first is EX?: FF with CE

// Change OPCODE depending on address when L/ST-byte/hfw
// ---- #ifndef VHDL (C シミュレータ版を採用) ----
//      (#ifndef VHDL: the C-simulator version is used)
   // 【解説】バイト/ハーフワードの L/ST は、どのバイトを使うかをアドレスの
   //         下位 2bit で opcode に入れる (opcode が 16 以上のとき):
   //           bit1 ← アドレス bit1,  bit0 ← アドレス bit0 (バイトのときだけ)
   //         例: LDB (16) で番地の下位が 3 → 19 (LDB3)
   //
   // [Note] For byte/halfword L/ST, which byte to use is put into the opcode from the low 2 address bits
   //        (when the opcode is 16 or more):
   //          bit1 <- address bit1,  bit0 <- address bit0 (bytes only)
   //        e.g. LDB (16) at an address ending in 3 -> 19 (LDB3)
   assign E_LS_OPCODE_NEW = !E_INTLK ?                  // ALUのopcode: CE=!E_INTLK, Dは次の式 ... / ALU opcode: CE = !E_INTLK, D is ...
		(  B_LS_OPCODE                          // ...Bのopcodeに ... / ... B's opcode OR ...
               	    | ((B_LS_OPCODE & 16) ? (B_LS_LOG_AD & 2) : 0) // ...サブワードなら番地bit1をbit1へOR ... / ... address bit 1 into bit 1 for sub-words ...
		    | (((B_LS_OPCODE & 16) && (!(B_LS_OPCODE & 4))) ? // ...バイト(bit2=0)なら番地bit0をbit0へ ... / ... address bit 0 into bit 0 for bytes (bit2=0) ...
				(B_LS_LOG_AD & 1) : 0)	) // ...(bit1,bit0にLUT3が1個ずつ, 他のbitは配線) / ... (one LUT3 each for bits 1,0; other bits are wires)
		: E_LS_OPCODE;                          // ...Eが止まっていれば保持 (CE) / ... hold while E stalls (CE)
// ---- #else (VHDL 版: 参考) ----
//      (#else: the VHDL version, for reference)
// E-LS-OPCODE    := !E-INTLK ? B-LS-OPCODE[0:3] . 
// 		  B-LS-OPCODE[0] & B-LS-LOG-AD[30] . 
// 		  B-LS-OPCODE[0] & !B-LS-OPCODE[2] & B-LS-LOG-AD[31]  
// 		: E-LS-OPCODE
// ---- #endif ----
