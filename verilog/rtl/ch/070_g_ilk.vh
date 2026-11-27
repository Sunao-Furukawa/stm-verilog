// =====================================================================
//  070_g_ilk.vh  <-  hard/070-g-ilk.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】インタロック (パイプラインの停止) 条件と、各ステージの前進信号
//
// xx_INTLK : そのステージの命令が次のサイクルも留まる
// xx_FWD   : そのステージの命令が次のステージへ進む
// 後段が止まれば前段も止まる (E → B → A → D の順に伝わる)。
//
// [Note] Interlock (pipeline stall) conditions and the advance signals of each stage
//
// xx_INTLK : the instruction of that stage stays in the next cycle too
// xx_FWD   : the instruction of that stage moves on to the next stage
// When a later stage stops, the earlier ones stop too (propagates E -> B -> A -> D).
//
// 【ネットリスト解説】
//   入力 : 060 の *_V_NOCAN / A_EAB / AA_LD_GO / WW_ST_GO, 050 の CANCEL_BY_INT,
//          各ステージの FF (E_LS_LD_V, E_OPCLH_LCH, STB_V, A/B/E/W_PRIVCODE ...),
//          D サイクルの組合せ信号 (I0_V, DD_FIRST_IS_JB, DD_ISSUEING_UNSOLVED_BC,
//          DD_PRIVCODE, DD_RAD2)
//   出力 : D_FWD   -> 110, 130, 140, 150, 170, 190, 210 (いちばん多く使われる)
//          A_FWD   -> 130, 170, 210 ;  A_INTLK -> 140, 150
//          B_FWD   -> 110          ;  B_INTLK -> 130
//          E_FWD   -> 090, 210     ;  E_INTLK -> 100, 110 ;  E_STB_INTLK -> 100
//   回路の形:
//     ・どれも 1bit の AND/OR だが、E_INTLK → B_INTLK → A_INTLK → D_FWD と
//       後段から前段へ鎖のようにつながっている (ストール信号の連鎖)。
//       E_OPCLH_LCH などの FF から始まり、D_FWD で終わる。
//     ・xx_FWD / xx_INTLK は次のステージの FF すべての「更新 / 保持 / クリア」を
//       選ぶ MUX の選択信号になる (例えば A_INTLK は A_* の FF 約 200 本の保持を選ぶ)。
//       そのためネットリスト上で最もファンアウトの大きいネット群で、FPGA では
//       FF の CE 端子 (クロックイネーブル) につながることが多い。
//     ・E_STAT などの *_STAT はどこからも使われないので消える。
//
// [Netlist notes]
//   Inputs : *_V_NOCAN / A_EAB / AA_LD_GO / WW_ST_GO (060), CANCEL_BY_INT (050),
//            FFs of each stage (E_LS_LD_V, E_OPCLH_LCH, STB_V, A/B/E/W_PRIVCODE ...),
//            combinational D-cycle signals (I0_V, DD_FIRST_IS_JB, DD_ISSUEING_UNSOLVED_BC,
//            DD_PRIVCODE, DD_RAD2)
//   Outputs: D_FWD   -> 110, 130, 140, 150, 170, 190, 210 (the most widely used)
//            A_FWD   -> 130, 170, 210 ;  A_INTLK -> 140, 150
//            B_FWD   -> 110          ;  B_INTLK -> 130
//            E_FWD   -> 090, 210     ;  E_INTLK -> 100, 110 ;  E_STB_INTLK -> 100
//   Circuit:
//     - All are 1-bit AND/OR, but they are chained from the back of the pipe to the front:
//       E_INTLK -> B_INTLK -> A_INTLK -> D_FWD (a chain of stall signals).
//       It starts at FFs such as E_OPCLH_LCH and ends at D_FWD.
//     - xx_FWD / xx_INTLK are the selects of the "update / hold / clear" muxes of every FF of
//       the next stage (A_INTLK, for example, selects hold for about 200 A_* FFs).
//       So these are the nets with the largest fan-out in the netlist, and on an FPGA they
//       often drive the CE (clock enable) pins of the FFs.
//     - E_STAT and the other *_STAT are unused and disappear.
// ---------------------------------------------------------------------

// g-ilk : interlock conditions

// E-STB-INTLK and B-LMD-INTLK can never simultaneously occur.  When
// STB-V & E-V-NOCAN & E-LS-ST-V B-V-NOCAN & B-LS-V ,
// i.e. (1)ST, (2)ST, (3)L/ST have passed SU consecutively and (1) is at W,
// (2) at E, (3) at B, SU must give (1)ST the highest priority -- higher
// than MI or MO --.  Otherwise (3) cannot issue OP-CLH and SU gets deadlock.

// 【解説】E のストアが、ストアバッファ STB が空かないため W へ進めない。
// [Note] The store in E cannot move to W because the store buffer STB is not free.
assign E_STB_INTLK = E_LS_ST_V & E_OPCLH_LCH & STB_V & !WW_ST_GO; // Eのストアが進めない: STBが埋まりST2も通らない (AND4 = LUT4) / E store stuck: STB full and ST2 not accepted (AND4 = LUT4)
// 【解説】E の L/ST がキャッシュのデータを待っている (キャッシュミス)。
// [Note] The L/ST in E is waiting for cache data (cache miss).
assign E_LMD_INTLK = (E_LS_LD_V | E_LS_ST_V) & !E_OPCLH_LCH; // EのL/STがキャッシュの応答待ち (ミス): LUT3 / E L/ST waiting for the cache (miss): LUT3
// 【解説】A の L/ST の要求を S ユニットが受け付けなかった (S ユニットが忙しい)。
// [Note] The S unit did not accept the request of the L/ST in A (the S unit is busy).
assign A_SBS_INTLK = (A_LS_LD_V | A_LS_ST_V) & !AA_LD_GO; // AのL/STをSユニットが受け付けない (S busy): LUT3 / S unit did not accept A's L/ST (S busy): LUT3

// D-V-NOCAN	= !( (NIP == 6) | (NIP >= 4) & !V45  )
// 【解説】D サイクルに発行できる命令がある。
// [Note] There is an instruction that can issue in the D cycle.
assign D_V_NOCAN = I0_V & !CANCEL_BY_INT;               // Dに発行できる命令がある: I0_V & !CANCEL_BY_INT / an insn can issue in D: I0_V & !CANCEL_BY_INT
// 【解説】未解決の条件分岐がすでにある間は、2 つ目の未解決分岐を発行しない。
// [Note] While an unresolved conditional branch exists, a second unresolved branch is not issued.
assign D_BC_2ND_INTLK = DD_FIRST_IS_JB & DD_ISSUEING_UNSOLVED_BC // 2つ目の未解決BCは待たせる: 1命令目がBCで ... / hold a second unsolved BC: first insn is a BC ...
			 & G_BC_PENDING;                // ...すでに未解決BCがある (210のFF) / ... and one is already pending (FF in 210)
// 【解説】RSR (システムレジスタ読み出し) は、先行する特権命令や
//         システムレジスタを書く可能性のある命令がパイプから抜けるまで待つ。
// [Note] RSR (system register read) waits until earlier privileged instructions and instructions
//        that may write system registers have left the pipe.
assign D_PIPECLR_INTLK = (DD_PRIVCODE == PRIVCODE_RSR) & // RSRはパイプが空くまで待つ: ... / RSR waits for the pipe to drain: ...
   ( (A_PRIVCODE != 0)|(B_PRIVCODE != 0)|(E_PRIVCODE != 0)|(W_PRIVCODE != 0) | // ...A/B/E/Wに特権命令がいる (2bit OR x4) か ... / ... a privileged insn in A/B/E/W (four 2-bit ORs) or ...
			  (A_V | B_V | E_V) & (DD_RAD2 == 0) ); // ...PSW(SR0)を読むのに先行命令が残る (CCが変わりうる). LUT2段 / ... reading PSW (SR0) with older insns left (CC may change). 2 LUT levels

// 【解説】各ステージのインタロック。後段が止まると前段も止まる。
// [Note] Interlock of each stage. When a later stage stops, the earlier ones stop too.
assign E_INTLK = E_V_NOCAN & (E_STB_INTLK | E_LMD_INTLK);   // E: STBFUL,LMD -- Eが止まる → B_INTLK, 100/110のE側FFの保持(CE) / E stalls -> B_INTLK, hold (CE) of E FFs in 100/110
assign B_INTLK = B_V_NOCAN &  E_INTLK;   // B: no intlk -- Bの停止はEの停止だけが原因 / B stalls only because E stalls
assign A_INTLK = A_V_NOCAN & (A_SBS_INTLK | A_EAB | B_INTLK );   // A:EAB,SUBUSY -- Sビジー/データハザード/後段停止 → 140/150のA_* FF約200本の保持 / S busy, hazard or later stall -> hold of ~200 A_* FFs in 140/150
assign D_INTLK = D_V_NOCAN & (D_BC_2ND_INTLK | D_PIPECLR_INTLK);   // D:BC2ND,PCLR -- 2つ目のBC / RSRのパイプ空け待ち / second BC / RSR drain

// 【解説】各ステージの命令が次のステージへ進む条件。
// [Note] Condition for the instruction of each stage to move on to the next stage.
assign E_FWD = E_V_NOCAN & ! E_STB_INTLK & ! E_LMD_INTLK; // Eの命令がWへ進む → 090のW_* FF / E insn moves to W -> W_* FFs in 090
assign B_FWD = B_V_NOCAN & ! E_INTLK;                   // Bの命令がEへ進む → 110 / B insn moves to E -> 110
assign A_FWD = A_V_NOCAN & !(A_SBS_INTLK | A_EAB | B_INTLK); // Aの命令がBへ進む → 130, 170, 210 / A insn moves to B -> 130, 170, 210
assign D_FWD = D_V_NOCAN & ! D_INTLK & !A_INTLK;        // Dの命令がAへ進む: 停止の連鎖(E→B→A→D)の終点, 最大ファンアウトのネット / D insn moves to A: end of the stall chain (E->B->A->D), the largest fan-out net


//# These are solely for simulation convenience (serve as probe) ##


// ---- #ifndef VHDL (C シミュレータ版を採用) ----
//      (#ifndef VHDL: the C-simulator version is used)
// 【解説】シミュレーション観測用 (bit3=FWD, bit0=V)。
// [Note] For observation in simulation (bit3=FWD, bit0=V).
assign E_STAT = (E_FWD << 3) | E_V;                     // 観測用 {FWD,0,0,V}: どこからも使われず合成で消える / probe {FWD,0,0,V}: unused, removed by synthesis
assign B_STAT = (B_FWD << 3) | B_V;                     // 観測用: 消える / probe: removed
assign A_STAT = (A_FWD << 3) | A_V;                     // 観測用: 消える / probe: removed
assign D_STAT = (D_FWD << 3) | D_V_NOCAN;               // 観測用: 消える / probe: removed
// ---- #endif ----
