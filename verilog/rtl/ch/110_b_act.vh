// =====================================================================
//  110_b_act.vh  <-  hard/110-b-act.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
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
   assign E_V_NEW = B_FWD   ? 1 : E_INTLK ? E_V : 0;

// JB-related tags need special handling; may be modified even when interlock
   // 【解説】分岐関係のタグは、インタロック中でも分岐の解決 (G_BC_JUST_SOLVED) で
   //         更新する。解決したら「未解決 BC」「投機中」のフラグを落とし、
   //         untaken と分かった分岐は無効にする。
   // [Note] Branch tags are updated by branch resolution (G_BC_JUST_SOLVED) even during an interlock.
   //        Once resolved, the "unresolved BC" and "speculative" flags are dropped, and a branch
   //        found to be untaken is invalidated.
   assign E_JB_IS_BC_NEW = B_FWD   ? B_JB_IS_BC & !G_BC_JUST_SOLVED :
			   E_INTLK ? E_JB_IS_BC & !G_BC_JUST_SOLVED : 0;
   assign E_JB_SUBJECT_TO_BC_NEW = B_FWD   ? B_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED :
			   E_INTLK ? E_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED : 0;
   assign E_JB_V_NEW = 
      B_FWD   ? B_JB_V & !(B_JB_IS_BC & G_BC_JUST_SOLVED & !G_BC_JUST_TAKEN) :
      E_INTLK ? E_JB_V & !(E_JB_IS_BC & G_BC_JUST_SOLVED & !G_BC_JUST_TAKEN) : 0;
   // 【解説】この LS 命令が、未解決 BC の CC を作る命令か。D で BC を発行した
   //         サイクルに、その CC を作る命令が B/E にいた場合もここでセットする。
   // [Note] Is this LS instruction the one that makes the CC of the unresolved BC? It is also set here
   //        when that instruction was in B/E in the cycle the BC was issued in D.
   assign E_LS_SOLVING_BC_NEW = 
	B_FWD   ? B_LS_SOLVING_BC | DD_ISSUEING_UNSOLVED_BC_ON_B_LS & D_FWD :
	E_INTLK ? E_LS_SOLVING_BC | DD_ISSUEING_UNSOLVED_BC_ON_E_LS & D_FWD : 0;

// These tags are just copied unmodified:
   // 【解説】以下のタグは変更せずにそのままコピーする。
   // [Note] The tags below are copied unchanged.
   assign E_LS_LD_V_NEW = B_FWD ? B_LS_LD_V  	: E_INTLK ? E_LS_LD_V    : 0;
   assign E_LS_ST_V_NEW = B_FWD ?  B_LS_ST_V 	: E_INTLK ? E_LS_ST_V    : 0;
   assign E_WE1_NEW = B_FWD ?  B_WE1 	: E_INTLK ? E_WE1        : 0;
   assign E_WE2_NEW = B_FWD ?  B_WE2 	: E_INTLK ? E_WE2        : 0;
   assign E_LS_SETCC_NEW = B_FWD ?  B_LS_SETCC  : E_INTLK ? E_LS_SETCC   : 0;
   assign E_EX_SETCC_NEW = B_FWD ?  B_EX_SETCC  : E_INTLK ? E_EX_SETCC   : 0;
   assign E_EX_INTCODE_NEW = B_FWD ?  B_INTCODE   : E_INTLK ? E_EX_INTCODE : 0;
   assign E_PRIVCODE_NEW = B_FWD ?  B_PRIVCODE  : E_INTLK ? E_PRIVCODE   : 0;

// Tags that are not 'valid' tags can be copied with CE = !E-INTLK.
   // 【解説】有効ビット以外のタグは E がインタロックでなければコピー (CE = !E_INTLK)。
   // [Note] Tags other than valid bits are copied when E is not interlocked (CE = !E_INTLK).
   assign E_LS_LOG_AD_NEW = !E_INTLK ?  B_LS_LOG_AD  	: E_LS_LOG_AD;
   assign E_WAD1_NEW = !E_INTLK ?  B_WAD1    	: E_WAD1;
   assign E_WAD2_NEW = !E_INTLK ?  B_WAD2    	: E_WAD2;
   assign E_LS_OPS_IS_GR_NEW = !E_INTLK ?  B_LS_OPS_IS_GR 	: E_LS_OPS_IS_GR;
   assign E_LS_RADS_NEW = !E_INTLK ?  B_LS_RADS   	: E_LS_RADS;
   assign E_EX_RES_NEW = !E_INTLK ?  B_EX_RES 	: E_EX_RES;
   assign E_EX_CC_NEW = !E_INTLK ?  B_EX_CC  	: E_EX_CC;
   assign E_TGT_NEW = !E_INTLK ?  B_TGT 		: E_TGT;
   assign E_IS_SUPERSCALAR_NEW = !E_INTLK ?  B_IS_SUPERSCALAR : E_IS_SUPERSCALAR;
   assign E_LATTER_IS_JB_NEW = !E_INTLK ?  B_LATTER_IS_JB   : E_LATTER_IS_JB;
   assign E_FIRST_IS_EX_NEW = !E_INTLK ?  B_FIRST_IS_EX    : E_FIRST_IS_EX;

// Change OPCODE depending on address when L/ST-byte/hfw
// ---- #ifndef VHDL (C シミュレータ版を採用) ----
   // 【解説】バイト/ハーフワードの L/ST は、どのバイトを使うかをアドレスの
   //         下位 2bit で opcode に入れる (opcode が 16 以上のとき):
   //           bit1 ← アドレス bit1,  bit0 ← アドレス bit0 (バイトのときだけ)
   //         例: LDB (16) で番地の下位が 3 → 19 (LDB3)
   //
   // [Note] For byte/halfword L/ST, which byte to use is put into the opcode from the low 2 address bits
   //        (when the opcode is 16 or more):
   //          bit1 <- address bit1,  bit0 <- address bit0 (bytes only)
   //        e.g. LDB (16) at an address ending in 3 -> 19 (LDB3)
   assign E_LS_OPCODE_NEW = !E_INTLK ?
		(  B_LS_OPCODE
               	    | ((B_LS_OPCODE & 16) ? (B_LS_LOG_AD & 2) : 0)
		    | (((B_LS_OPCODE & 16) && (!(B_LS_OPCODE & 4))) ?
				(B_LS_LOG_AD & 1) : 0)	)
		: E_LS_OPCODE;
// ---- #else (VHDL 版: 参考) ----
// E-LS-OPCODE    := !E-INTLK ? B-LS-OPCODE[0:3] . 
// 		  B-LS-OPCODE[0] & B-LS-LOG-AD[30] . 
// 		  B-LS-OPCODE[0] & !B-LS-OPCODE[2] & B-LS-LOG-AD[31]  
// 		: E-LS-OPCODE
// ---- #endif ----
