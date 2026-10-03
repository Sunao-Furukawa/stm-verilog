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
   assign E_V_NEW = B_FWD   ? 1 : E_INTLK ? E_V : 0;

// JB-related tags need special handling; may be modified even when interlock
   // 【解説】分岐関係のタグは、インタロック中でも分岐の解決 (G_BC_JUST_SOLVED) で
   //         更新する。解決したら「未解決 BC」「投機中」のフラグを落とし、
   //         untaken と分かった分岐は無効にする。
   assign E_JB_IS_BC_NEW = B_FWD   ? B_JB_IS_BC & !G_BC_JUST_SOLVED :
			   E_INTLK ? E_JB_IS_BC & !G_BC_JUST_SOLVED : 0;
   assign E_JB_SUBJECT_TO_BC_NEW = B_FWD   ? B_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED :
			   E_INTLK ? E_JB_SUBJECT_TO_BC & !G_BC_JUST_SOLVED : 0;
   assign E_JB_V_NEW = 
      B_FWD   ? B_JB_V & !(B_JB_IS_BC & G_BC_JUST_SOLVED & !G_BC_JUST_TAKEN) :
      E_INTLK ? E_JB_V & !(E_JB_IS_BC & G_BC_JUST_SOLVED & !G_BC_JUST_TAKEN) : 0;
   // 【解説】この LS 命令が、未解決 BC の CC を作る命令か。D で BC を発行した
   //         サイクルに、その CC を作る命令が B/E にいた場合もここでセットする。
   assign E_LS_SOLVING_BC_NEW = 
	B_FWD   ? B_LS_SOLVING_BC | DD_ISSUEING_UNSOLVED_BC_ON_B_LS & D_FWD :
	E_INTLK ? E_LS_SOLVING_BC | DD_ISSUEING_UNSOLVED_BC_ON_E_LS & D_FWD : 0;

// These tags are just copied unmodified:
   // 【解説】以下のタグは変更せずにそのままコピーする。
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
