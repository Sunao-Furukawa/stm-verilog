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
assign I0_V_NOINT = I0_V & I0_IS_LEGAL;
assign DD_INTCODE = (I0_IS_LEGAL ? 0 : INTCODE_OP);

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
assign DD_ISSUE_SECOND_INSN = 
       I1_V
    & !(DD_FIRST_SETCC & DD_SECOND_SETCC)   // CC dependency
    & !(DD_FIRST_WAD_V &((DD_SECOND_WAD_V  & (DD_FIRST_WAD == DD_SECOND_WAD ))
	                |(DD_SECOND_RADB_V & (DD_FIRST_WAD == DD_SECOND_RADB1))
	                |(DD_SECOND_RAD1_V & (DD_FIRST_WAD == DD_SECOND_RADB1))
	                |(DD_SECOND_RAD2_V & (DD_FIRST_WAD == DD_SECOND_RAD2)) )
       )   // REG dependency
    & !(DD_FIRST_IS_LS & DD_SECOND_IS_JB & I1_JB_REG)   // EAG conflict
    & !(DD_FIRST_IS_EX & DD_SECOND_IS_JB & I1_JB_LINK)   // EX/LINK conflict
    & !(DD_SECOND_IS_JB & I1_JB_COND & G_BC_PENDING)   // BC 2nd
    & ! DD_FIRST_IS_JB   // First branches
    & !(DD_FIRST_IS_LS & DD_SECOND_IS_LS)   // pipe conflict
    & !(DD_FIRST_IS_EX & DD_SECOND_IS_EX)   // pipe conflict
    & (DD_PRIVCODE == 0)   // privileged op
    & !DD_SECOND_PRIV_V   // privileged op
    & I0_IS_LEGAL   // not intrrupting
    & I1_IS_LEGAL;   // not intrrupting


// Register file address port -- may be critical!

// 【解説】レジスタファイルの読み出しアドレス (ポートは RADB, RAD1, RAD2 の 3 本)。
//         1 命令目が使うならその番号, そうでなければ 2 命令目の番号を出す。
//         (元コメント: タイミング的にクリティカルかもしれない部分)
// [Note] Read addresses of the register file (3 ports: RADB, RAD1, RAD2).
//        If the first instruction uses a port, its number; otherwise the second's.
//        (original comment: this may be timing-critical)
assign DD_RADB = (DD_FIRST_RADB_V ? I0_LS_RB : I1_LS_RB);
assign DD_RAD1 = (DD_FIRST_RAD1_V ? I0_EX_RB1 : I1_EX_RB1);
assign DD_RAD2 = ((DD_FIRST_RAD2_V | (DD_PRIVCODE != 0)) ? I0_EX_RS2 : I1_EX_RS2);

// IXX   : XX-insn (XX = LS,EX,JB)
// IXX-V : XX-insn is being issued

// 【解説】パイプへの振り分け。_V が有効ビット、ILS/IEX/IJB が命令語そのもの。
//         1 命令目を優先し、2 命令目は同時発行するときだけ選ぶ。
// [Note] Sorting into the pipes. _V is the valid bit, ILS/IEX/IJB the instruction word itself.
//        The first instruction has priority; the second is chosen only when dual-issued.
assign ILS_V = I0_V_NOINT & DD_FIRST_IS_LS | DD_ISSUE_SECOND_INSN & DD_SECOND_IS_LS;
assign ILS = ( I0_V_NOINT & DD_FIRST_IS_LS ? I0 :
		     (DD_ISSUE_SECOND_INSN & DD_SECOND_IS_LS ? I1 : 0) );
assign IEX_V = I0_V_NOINT & DD_FIRST_IS_EX | DD_ISSUE_SECOND_INSN & DD_SECOND_IS_EX;
assign IEX = ( I0_V_NOINT & DD_FIRST_IS_EX ? I0 :
		     (DD_ISSUE_SECOND_INSN & DD_SECOND_IS_EX ? I1 : 0) );
assign IJB_V = I0_V_NOINT & DD_FIRST_IS_JB | DD_ISSUE_SECOND_INSN & DD_SECOND_IS_JB;
assign IJB = ( I0_V_NOINT & DD_FIRST_IS_JB ? I0 :
		     (DD_ISSUE_SECOND_INSN & DD_SECOND_IS_JB ? I1 : 0) );
