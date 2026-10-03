// =====================================================================
//  030_d_sec.vh  <-  hard/030-d-sec.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
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
assign I0_V_NOINT = I0_V & I0_IS_LEGAL;
assign DD_INTCODE = (I0_IS_LEGAL ? 0 : INTCODE_OP);

// 【解説】2 命令目も発行する条件。次のどれか 1 つでもあると 1 命令だけ発行:
//           ・2 命令とも CC を変える
//           ・1 命令目が書くレジスタを 2 命令目が読む/書く (レジスタ依存)
//           ・LS + レジスタ間接分岐 (アドレス加算器 EAG の取り合い)
//           ・EX + リンク付き分岐 (どちらも EX パイプを使う)
//           ・未解決の条件分岐があるのに、また条件分岐が来た
//           ・1 命令目が分岐、LS どうし、EX どうし、特権命令、不正命令
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
assign DD_RADB = (DD_FIRST_RADB_V ? I0_LS_RB : I1_LS_RB);
assign DD_RAD1 = (DD_FIRST_RAD1_V ? I0_EX_RB1 : I1_EX_RB1);
assign DD_RAD2 = ((DD_FIRST_RAD2_V | (DD_PRIVCODE != 0)) ? I0_EX_RS2 : I1_EX_RS2);

// IXX   : XX-insn (XX = LS,EX,JB)
// IXX-V : XX-insn is being issued

// 【解説】パイプへの振り分け。_V が有効ビット、ILS/IEX/IJB が命令語そのもの。
//         1 命令目を優先し、2 命令目は同時発行するときだけ選ぶ。
assign ILS_V = I0_V_NOINT & DD_FIRST_IS_LS | DD_ISSUE_SECOND_INSN & DD_SECOND_IS_LS;
assign ILS = ( I0_V_NOINT & DD_FIRST_IS_LS ? I0 :
		     (DD_ISSUE_SECOND_INSN & DD_SECOND_IS_LS ? I1 : 0) );
assign IEX_V = I0_V_NOINT & DD_FIRST_IS_EX | DD_ISSUE_SECOND_INSN & DD_SECOND_IS_EX;
assign IEX = ( I0_V_NOINT & DD_FIRST_IS_EX ? I0 :
		     (DD_ISSUE_SECOND_INSN & DD_SECOND_IS_EX ? I1 : 0) );
assign IJB_V = I0_V_NOINT & DD_FIRST_IS_JB | DD_ISSUE_SECOND_INSN & DD_SECOND_IS_JB;
assign IJB = ( I0_V_NOINT & DD_FIRST_IS_JB ? I0 :
		     (DD_ISSUE_SECOND_INSN & DD_SECOND_IS_JB ? I1 : 0) );
