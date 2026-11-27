// =====================================================================
//  030_d_sec.vh  <-  hard/030-d-sec.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】D サイクル(4): 2 命令目を同時に発行できるかの判定と、パイプへの振り分け
//
// 同時発行できるのは「LS パイプ 1 命令 + EX パイプ 1 命令」や
// 「LS/EX + 分岐」の組み合わせで、依存関係や資源の競合が無い場合だけ。
// 発行する命令は役割ごとに
//   ILS : LS パイプへ流す命令
//   IEX : EX パイプへ流す命令
//   IJB : 分岐命令
// にまとめ直し、以降のステージはこの 3 つを見る。
//
// [Note] D cycle (4): can the second instruction issue at the same time, and sorting into the pipes
//
// Dual issue is possible only for pairs like "1 LS-pipe + 1 EX-pipe instruction" or
// "LS/EX + branch", and only with no dependence or resource conflict.
// The issued instructions are regrouped by role into
//   ILS : the instruction sent to the LS pipe
//   IEX : the instruction sent to the EX pipe
//   IJB : the branch instruction
// and the later stages look at these three.
//
// 【ネットリスト解説】
//   入力 : 020 の DD_FIRST_* / DD_SECOND_*, 015 のレジスタ番号と I0/I1_IS_LEGAL,
//          010 の I0 / I1 / I0_V / I1_V, 210 の G_BC_PENDING (FF)
//   出力 : DD_ISSUE_SECOND_INSN       -> 140, 150, 190 (2 命令目も発行するか)
//          ILS / IEX / IJB と ILS_V / IEX_V / IJB_V -> 035, 040, 140, 150, 190
//          DD_RAD1 / DD_RAD2 / DD_RADB -> stm_cntl の出力ポート (レジスタファイル),
//                                         140 (バイパスの番号比較), 070 (DD_RAD2)
//          DD_INTCODE                 -> 150
//   回路の形:
//     ・DD_ISSUE_SECOND_INSN は 4bit 比較器 4 個 (レジスタ依存) と多数の条件の AND。
//       D サイクルで最も段数の多い論理の 1 つ。
//     ・ILS / IEX / IJB は「I0 か I1 か 0 か」の 32bit 3:1 MUX が 3 組。
//       ILS → 035 → 040 の DD_DISP, IJB → 040 の DD_TGT (加算) と続くので、
//       IWQ → I0/I1 → DD_ISSUE_SECOND_INSN → IJB → DD_TGT → A_TGT の FF が
//       D サイクルの長い経路になる。
//     ・DD_RAD* は 4bit の 2:1 MUX。そのまま stm_cntl の外 (stm_regfile) へ出て
//       読み出しデータが戻ってくる (stm_cntl.v のポートの解説参照)。
//
// [Netlist notes]
//   Inputs : DD_FIRST_* / DD_SECOND_* (020), register numbers and I0/I1_IS_LEGAL (015),
//            I0 / I1 / I0_V / I1_V (010), G_BC_PENDING (FF in 210)
//   Outputs: DD_ISSUE_SECOND_INSN       -> 140, 150, 190 (also issue the second instruction?)
//            ILS / IEX / IJB and ILS_V / IEX_V / IJB_V -> 035, 040, 140, 150, 190
//            DD_RAD1 / DD_RAD2 / DD_RADB -> output ports of stm_cntl (register file),
//                                           140 (register-number compares of the bypass), 070 (DD_RAD2)
//            DD_INTCODE                 -> 150
//   Circuit:
//     - DD_ISSUE_SECOND_INSN is four 4-bit comparators (register dependences) ANDed with
//       many conditions. It is one of the deepest pieces of logic in the D cycle.
//     - ILS / IEX / IJB are three 32-bit 3:1 muxes ("I0, I1 or 0").
//       ILS feeds DD_DISP through 035 -> 040, and IJB feeds DD_TGT (an adder) in 040, so
//       IWQ -> I0/I1 -> DD_ISSUE_SECOND_INSN -> IJB -> DD_TGT -> the A_TGT FFs
//       is a long D-cycle path.
//     - DD_RAD* are 4-bit 2:1 muxes. They leave stm_cntl directly (to stm_regfile) and the
//       read data comes back (see the notes on the ports in stm_cntl.v).
// ---------------------------------------------------------------------

// d-sec : issue second insn

// case FIRST-IS-LS & SECOND-IS-EX)
// 	  ! CC,RD,R1,R2 conflict

// case FIRST-IS-LS & SECOND-IS-JB)
//         ! REG-rel(EAG collide)
// 	& ! RD conflict(when LINK)
// 	& ! R1,R2 conflict(when cmp)

// case FIRST-IS-EX & SECOND-IS-LS)
// 	  ! CC,RB conflict

// case FIRST-IS-EX & SECOND-IS-JB)
//         ! LINK (LINK uses EX-pipe)
// 	& ! RB conflict(when REG)
// 	& ! R1,R2 conflict(when cmp)

// First, check that I0 is legal
// 【解説】1 命令目が有効かつ合法か。不正命令なら命令例外 (INTCODE_OP) を
//         A サイクルへ渡し、W サイクルで割り込みになる。
// [Note] Is the first instruction valid and legal? An illegal instruction passes an instruction
//        exception (INTCODE_OP) to the A cycle, and it becomes an interrupt in the W cycle.
assign I0_V_NOINT = I0_V & I0_IS_LEGAL;                 // I0が有効かつ合法 (AND 1個): 発行してよい1命令目 / I0 valid and legal (one AND): first insn may issue
assign DD_INTCODE = (I0_IS_LEGAL ? 0 : INTCODE_OP);     // 不正ならINTCODE_OP(=1): 3bitのうちbit0だけがNOT(I0_IS_LEGAL), 残りは0固定 / INTCODE_OP (=1) if illegal: only bit 0 = NOT legal, the rest tied to 0

// 【解説】2 命令目も発行する条件。次のどれか 1 つでもあると 1 命令だけ発行:
//           ・2 命令とも CC を変える
//           ・1 命令目が書くレジスタを 2 命令目が読む/書く (レジスタ依存)
//           ・LS + レジスタ間接分岐 (アドレス加算器 EAG の取り合い)
//           ・EX + リンク付き分岐 (どちらも EX パイプを使う)
//           ・未解決の条件分岐があるのに、また条件分岐が来た
//           ・1 命令目が分岐、LS どうし、EX どうし、特権命令、不正命令
//
// [Note] Condition to issue the second instruction too. If any one of these holds, only one issues:
//          - both instructions change CC
//          - the second reads/writes a register the first writes (register dependence)
//          - LS + register-indirect branch (both need the address adder EAG)
//          - EX + branch with link (both use the EX pipe)
//          - a conditional branch arrives while one is still unresolved
//          - the first is a branch, both are LS, both are EX, privileged, or illegal
assign DD_ISSUE_SECOND_INSN =                           // 2命令目も発行するか: 下の全条件のAND (Dサイクルで最も深い論理, LUT 3~4段) / dual issue?: AND of all terms below (deepest D-cycle logic, 3-4 LUT levels)
       I1_V                                             // I1が存在する / I1 exists
    & !(DD_FIRST_SETCC & DD_SECOND_SETCC)   // CC dependency  -- 2命令ともCCを変えるなら1命令だけ (AND+NOT, LUTの1入力) / both insns set CC -> issue one only (AND + NOT, one LUT input)
    & !(DD_FIRST_WAD_V &((DD_SECOND_WAD_V  & (DD_FIRST_WAD == DD_SECOND_WAD )) // I0の書き先をI1も書く (WAW): 4bit一致比較器(XNOR4+AND) / I1 writes I0's destination (WAW): 4-bit equality comparator
	                |(DD_SECOND_RADB_V & (DD_FIRST_WAD == DD_SECOND_RADB1)) // I0の書き先をI1がベースとして読む (RAW) / I1 reads I0's destination as base (RAW)
	                |(DD_SECOND_RAD1_V & (DD_FIRST_WAD == DD_SECOND_RADB1)) // I1がR1として読む (R1とRBは同じ[19:16]なので比較器を共有) / I1 reads it as R1 (R1 and RB share bits [19:16], so the comparator is shared)
	                |(DD_SECOND_RAD2_V & (DD_FIRST_WAD == DD_SECOND_RAD2)) ) // I1がR2として読む (2つ目の4bit比較器) / I1 reads it as R2 (second 4-bit comparator)
       )   // REG dependency  -- 上の4項の終わり: I0の書き先をI1が使えば1命令だけ (4bit比較器2個のOR) / end of the 4 terms above: one insn if I1 uses I0's destination (OR of 2 comparators)
    & !(DD_FIRST_IS_LS & DD_SECOND_IS_JB & I1_JB_REG)   // EAG conflict  -- LS+レジスタ間接分岐はアドレス加算器EAGを取り合う (AND3) / LS + register-indirect branch both need the EAG adder (AND3)
    & !(DD_FIRST_IS_EX & DD_SECOND_IS_JB & I1_JB_LINK)   // EX/LINK conflict  -- EX+リンク付き分岐はどちらもEXパイプで書く (AND3) / EX + branch with link both write through the EX pipe (AND3)
    & !(DD_SECOND_IS_JB & I1_JB_COND & G_BC_PENDING)   // BC 2nd  -- 未解決BCがあるのに2命令目もBC: 2つ目は待たせる (AND3, G_BC_PENDINGはFF) / second BC while one is pending: hold it (AND3, G_BC_PENDING is an FF)
    & ! DD_FIRST_IS_JB   // First branches  -- 1命令目が分岐なら2命令目は出さない (分岐先が変わるため) / no second insn after a branch (the path changes)
    & !(DD_FIRST_IS_LS & DD_SECOND_IS_LS)   // pipe conflict  -- LS+LS: LSパイプは1本 (AND) / LS + LS: there is one LS pipe (AND)
    & !(DD_FIRST_IS_EX & DD_SECOND_IS_EX)   // pipe conflict  -- EX+EX: EXパイプは1本 (AND) / EX + EX: there is one EX pipe (AND)
    & (DD_PRIVCODE == 0)   // privileged op  -- 1命令目が特権命令なら単独で発行 (2bitのNOR) / a privileged first insn issues alone (2-bit NOR)
    & !DD_SECOND_PRIV_V   // privileged op  -- 2命令目が特権命令なら次のサイクルに回す / a privileged second insn waits for the next cycle
    & I0_IS_LEGAL   // not intrrupting  -- 1命令目が不正命令 (例外になる) なら2命令目は出さない / no second insn if the first is illegal (it traps)
    & I1_IS_LEGAL;   // not intrrupting  -- 2命令目が不正命令なら出さない (次のサイクルに1命令目として例外にする). ここまでの全項のAND = LUT 3~4段 / not if the second is illegal (it traps next cycle as the first). AND of all terms = 3-4 LUT levels


// Register file address port -- may be critical!

// 【解説】レジスタファイルの読み出しアドレス (ポートは RADB, RAD1, RAD2 の 3 本)。
//         1 命令目が使うならその番号, そうでなければ 2 命令目の番号を出す。
//         (元コメント: タイミング的にクリティカルかもしれない部分)
// [Note] Read addresses of the register file (3 ports: RADB, RAD1, RAD2).
//        If the first instruction uses a port, its number; otherwise the second's.
//        (original comment: this may be timing-critical)
assign DD_RADB = (DD_FIRST_RADB_V ? I0_LS_RB : I1_LS_RB); // RBの読み出し番号→stm_regfileのradb: 4bit 2:1 MUX / RB read number -> radb of stm_regfile: 4-bit 2:1 mux
assign DD_RAD1 = (DD_FIRST_RAD1_V ? I0_EX_RB1 : I1_EX_RB1); // R1の読み出し番号→rad1: 4bit 2:1 MUX / R1 read number -> rad1: 4-bit 2:1 mux
assign DD_RAD2 = ((DD_FIRST_RAD2_V | (DD_PRIVCODE != 0)) ? I0_EX_RS2 : I1_EX_RS2); // R2の読み出し番号→rad2 (特権命令はI0固定): 4bit 2:1 MUX, 選択はLUT1個 / R2 read number -> rad2 (I0 for priv ops): 4-bit 2:1 mux, select in 1 LUT

// IXX   : XX-insn (XX = LS,EX,JB)
// IXX-V : XX-insn is being issued

// 【解説】パイプへの振り分け。_V が有効ビット、ILS/IEX/IJB が命令語そのもの。
//         1 命令目を優先し、2 命令目は同時発行するときだけ選ぶ。
// [Note] Sorting into the pipes. _V is the valid bit, ILS/IEX/IJB the instruction word itself.
//        The first instruction has priority; the second is chosen only when dual-issued.
assign ILS_V = I0_V_NOINT & DD_FIRST_IS_LS | DD_ISSUE_SECOND_INSN & DD_SECOND_IS_LS; // LSパイプへ発行する命令がある: AND-OR (LUT1個) → 150のA_LS_V / an insn issues to the LS pipe: AND-OR (1 LUT) -> A_LS_V in 150
assign ILS = ( I0_V_NOINT & DD_FIRST_IS_LS ? I0 :       // LSパイプの命令語: I0優先 ... / LS-pipe insn word: I0 first ...
		     (DD_ISSUE_SECOND_INSN & DD_SECOND_IS_LS ? I1 : 0) ); // ...次にI1, どちらでもなければ0: 32bit 3:1 MUX (LUT 32~64個) / ... then I1, else 0: 32-bit 3:1 mux (32-64 LUTs)
assign IEX_V = I0_V_NOINT & DD_FIRST_IS_EX | DD_ISSUE_SECOND_INSN & DD_SECOND_IS_EX; // EXパイプへ発行する命令がある → 150のA_EX_V / an insn issues to the EX pipe -> A_EX_V in 150
assign IEX = ( I0_V_NOINT & DD_FIRST_IS_EX ? I0 :       // EXパイプの命令語: I0優先 ... / EX-pipe insn word: I0 first ...
		     (DD_ISSUE_SECOND_INSN & DD_SECOND_IS_EX ? I1 : 0) ); // ...次にI1, なければ0: 32bit 3:1 MUX / ... then I1, else 0: 32-bit 3:1 mux
assign IJB_V = I0_V_NOINT & DD_FIRST_IS_JB | DD_ISSUE_SECOND_INSN & DD_SECOND_IS_JB; // 分岐命令を発行する → 040/150/210 / a branch issues -> 040/150/210
assign IJB = ( I0_V_NOINT & DD_FIRST_IS_JB ? I0 :       // 分岐の命令語: I0優先 ... / branch insn word: I0 first ...
		     (DD_ISSUE_SECOND_INSN & DD_SECOND_IS_JB ? I1 : 0) ); // ...次にI1: 32bit 3:1 MUX. この後040の加算器へ続く長い経路 / ... then I1: 32-bit 3:1 mux, feeding the long path into the 040 adder
