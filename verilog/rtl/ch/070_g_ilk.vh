// =====================================================================
//  070_g_ilk.vh  <-  hard/070-g-ilk.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】インタロック (パイプラインの停止) 条件と、各ステージの前進信号
//
// xx_INTLK : そのステージの命令が次のサイクルも留まる
// xx_FWD   : そのステージの命令が次のステージへ進む
// 後段が止まれば前段も止まる (E → B → A → D の順に伝わる)。
// ---------------------------------------------------------------------

// g-ilk : interlock conditions

// E-STB-INTLK and B-LMD-INTLK can never simultaneously occur.  When
// STB-V & E-V-NOCAN & E-LS-ST-V B-V-NOCAN & B-LS-V ,
// i.e. (1)ST, (2)ST, (3)L/ST have passed SU consecutively and (1) is at W,
// (2) at E, (3) at B, SU must give (1)ST the highest priority -- higher
// than MI or MO --.  Otherwise (3) cannot issue OP-CLH and SU gets deadlock.

// 【解説】E のストアが、ストアバッファ STB が空かないため W へ進めない。
assign E_STB_INTLK = E_LS_ST_V & E_OPCLH_LCH & STB_V & !WW_ST_GO;
// 【解説】E の L/ST がキャッシュのデータを待っている (キャッシュミス)。
assign E_LMD_INTLK = (E_LS_LD_V | E_LS_ST_V) & !E_OPCLH_LCH;
// 【解説】A の L/ST の要求を S ユニットが受け付けなかった (S ユニットが忙しい)。
assign A_SBS_INTLK = (A_LS_LD_V | A_LS_ST_V) & !AA_LD_GO;

// D-V-NOCAN	= !( (NIP == 6) | (NIP >= 4) & !V45  )
// 【解説】D サイクルに発行できる命令がある。
assign D_V_NOCAN = I0_V & !CANCEL_BY_INT;
// 【解説】未解決の条件分岐がすでにある間は、2 つ目の未解決分岐を発行しない。
assign D_BC_2ND_INTLK = DD_FIRST_IS_JB & DD_ISSUEING_UNSOLVED_BC
			 & G_BC_PENDING;
// 【解説】RSR (システムレジスタ読み出し) は、先行する特権命令や
//         システムレジスタを書く可能性のある命令がパイプから抜けるまで待つ。
assign D_PIPECLR_INTLK = (DD_PRIVCODE == PRIVCODE_RSR) &
   ( (A_PRIVCODE != 0)|(B_PRIVCODE != 0)|(E_PRIVCODE != 0)|(W_PRIVCODE != 0) |
			  (A_V | B_V | E_V) & (DD_RAD2 == 0) );

// 【解説】各ステージのインタロック。後段が止まると前段も止まる。
assign E_INTLK = E_V_NOCAN & (E_STB_INTLK | E_LMD_INTLK);   // E: STBFUL,LMD
assign B_INTLK = B_V_NOCAN &  E_INTLK;   // B: no intlk
assign A_INTLK = A_V_NOCAN & (A_SBS_INTLK | A_EAB | B_INTLK );   // A:EAB,SUBUSY
assign D_INTLK = D_V_NOCAN & (D_BC_2ND_INTLK | D_PIPECLR_INTLK);   // D:BC2ND,PCLR

// 【解説】各ステージの命令が次のステージへ進む条件。
assign E_FWD = E_V_NOCAN & ! E_STB_INTLK & ! E_LMD_INTLK;
assign B_FWD = B_V_NOCAN & ! E_INTLK;
assign A_FWD = A_V_NOCAN & !(A_SBS_INTLK | A_EAB | B_INTLK);
assign D_FWD = D_V_NOCAN & ! D_INTLK & !A_INTLK;


//# These are solely for simulation convenience (serve as probe) ##


// ---- #ifndef VHDL (C シミュレータ版を採用) ----
// 【解説】シミュレーション観測用 (bit3=FWD, bit0=V)。
assign E_STAT = (E_FWD << 3) | E_V;
assign B_STAT = (B_FWD << 3) | B_V;
assign A_STAT = (A_FWD << 3) | A_V;
assign D_STAT = (D_FWD << 3) | D_V_NOCAN;
// ---- #endif ----
