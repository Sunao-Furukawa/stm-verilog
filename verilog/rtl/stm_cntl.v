// =====================================================================
//  stm_cntl.v  -  STM (2-way superscalar 32bit RISC) 本体
//
//  hard/*.ch (CHDL) を Verilog HDL 2001 に変換したもの。
//  CHDL の 1 ファイル = ch/ 以下の 1 つのインクルードファイル。
//
//  CHDL -> Verilog の対応
//    NAME  = 式      (ネット)       ->  assign NAME = 式;
//    NAME := 式      (FF への代入)  ->  assign NAME_NEW = 式;   と
//                                       always @(posedge clk) NAME <= NAME_NEW;
//      (C シミュレータが NAME_NEW に計算してサイクルの最後に NAME へ
//       コピーしていたのと同じ構造)
//    名前中の '-'                    ->  '_'   (例 DD-RAD1 -> DD_RAD1)
//    マクロ (bit_ext, cc_match ...)   ->  function (stm_defs.vh, stm_fmt_*.vh)
//    exu() 関数                       ->  stm_exu モジュール (2 個)
//    GR[] / Mem[]  (045-g-ram.ch)     ->  外部の stm_regfile / stm_memory
//
//  CHDL では各ネットはソース順に評価されるが、元ソースは「使う前に
//  定義する」順序になっている (確認済み) ので、順序に依存しない
//  Verilog の連続代入にそのまま置き換えても同じ動作になる。
//
//  リセット: rst=1 の間のクロックで全 FF を 0 にし, PC だけ RESET_PC にする (同期リセット)。
//            (C 版で PC に開始番地を入れ, 他を 0 から始めたのと同じ。
//             START-TRIGGER-BAR=0 なので最初のサイクルで命令フェッチが始まる)
// =====================================================================
//
// 【解説】パイプラインの構成
//
//   IF : 命令フェッチ。8 バイト (2 命令) ずつ命令キュー IWQ-A/B へ  (170〜200)
//   D  : デコードと発行。最大 2 命令を LS / EX / JB に振り分け     (010〜040, 140, 150)
//   A  : EX パイプの演算 (EXU), LS パイプのアドレス計算 (EAG)       (120, 130)
//   B  : オペランドキャッシュへのアクセス (S ユニット)             (050, 100, 110, 160)
//   E  : LS パイプの ALU (メモリオペランド演算, サブワード整形)    (090)
//   W  : 完了。GR / PC / PSW の更新, 割り込み                       (080)
//   インタロック・取り消し・分岐予測の制御は 060, 070, 210。
//
// 【解説】信号名の付け方 (元の CHDL の慣習)
//
//   X_...  (X = A, B, E, W)  : X サイクルにいる命令のタグ。ほとんどが FF で、
//                              命令が次のステージへ進むと次の段の FF へコピーされる
//   XX_... (DD, AA, BB, EE, WW, GG) : X サイクルの組合せ回路 (その場で計算するネット)
//                              GG はステージに属さないグローバルな回路
//   G_...                    : グローバルな FF (分岐の解決状態など)
//   I0, I1                   : 発行候補の 1 命令目, 2 命令目
//   ILS, IEX, IJB            : LS パイプ / EX パイプ / 分岐へ振り分けた命令
//   ..._V                    : 有効ビット (valid)
//   ..._NOCAN                : 有効かつ取り消されていない
//   ..._FWD / ..._INTLK      : 次へ進む / 留まる (インタロック)
//   WAD / RAD                : レジスタの書き込み / 読み出しアドレス (番号)
//   WDT / DT                 : データ
//   ..1 / ..2 (WE1, WAD1 …) : 1 = LS パイプ側, 2 = EX パイプ側 (W_WE1 / W_WE2 など)
//
// =====================================================================
module stm_cntl (
  input              clk,
  input              rst,
  input      [31:0]  RESET_PC,

  // キャッシュミス模擬 (C 版の random_clh)。常時 1 ならミス無し。
  input              RANDOM_FOR_OPCLH,
  input              RANDOM_FOR_IFRDY,
  input              RANDOM_FOR_IFCLH,

  // レジスタファイル (stm_regfile) とのインタフェース
  output     [3:0]   DD_RAD1,
  output     [3:0]   DD_RAD2,
  output     [3:0]   DD_RADB,
  output reg [3:0]   B_LS_RADS,
  input      [31:0]  GR_DT_1,
  input      [31:0]  GR_DT_2,
  input      [31:0]  GR_DT_B,
  input      [31:0]  GR_DT_S,
  output reg         W_WE1,
  output reg         W_WE2,
  output reg [3:0]   W_WAD1,
  output reg [3:0]   W_WAD2,
  output reg [31:0]  W_WDT1,
  output reg [31:0]  W_WDT2,

  // メモリ (stm_memory) とのインタフェース
  output reg         LBS_WE,
  output reg [31:0]  LBS_AD,
  output reg [31:0]  LBS_DT,
  input      [31:0]  MEM_DT_OP,
  output reg [31:0]  IB_AD,
  input      [31:0]  MEM_DT_IF_H,
  input      [31:0]  MEM_DT_IF_L,

  // 観測用
  output reg [31:0]  PC
);

`include "stm_const.vh"
`include "stm_defs.vh"
`include "stm_fmt_ls_ex.vh"
`include "stm_fmt_jb.vh"

// ---------------------------------------------------------------------
//  宣言 (元の .ch ファイルごと)。ビット幅は vh/prop.tab, vh/assi.tab による。
//    wire      : CHDL の '='  (組合せ回路のネット)
//    reg       : CHDL の ':=' (FF)。 *_NEW がその D 入力
// ---------------------------------------------------------------------

// ---- 010-d-pre.ch
wire           EID;
wire [31:0]    IWQ_0;
wire [31:0]    IWQ_1;
wire [31:0]    IWQ_2;
wire [31:0]    IWQ_3;
wire [31:0]    IWQ_4;
wire [31:0]    IWQ_5;
wire [2:0]     NIP_A;
wire [2:0]     NIP;
wire           NIP_0;
wire           NIP_1;
wire           NIP_2;
wire           NIP_3;
wire           NIP_4;
wire           NIP_5;
wire           V01;
wire           V23;
wire           V45;
wire           I0_V;
wire           I1_V;
wire [31:0]    I0_CANDID;
wire [31:0]    I0;
wire [31:0]    I1_CANDID;
wire [31:0]    I1;
// ---- 015-d-i01.ch
wire           I0_LS_STORE;
wire [3:0]     I0_LS_LENG;
wire [3:0]     I0_LS_RD_RS;
wire [3:0]     I0_LS_RB;
wire [15:0]    I0_LS_DISP16;
wire [1:0]     I0_EX_OP2MODE;
wire           I0_EX_SETCC;
wire [3:0]     I0_EX_EXU_OPC;
wire [3:0]     I0_EX_RB1;
wire [3:0]     I0_EX_RS2;
wire [3:0]     I0_EX_RD;
wire [11:0]    I0_EX_DISP12;
wire           I0_JB_COND;
wire           I0_JB_REG;
wire           I0_JB_LINK;
wire           I0_JB_CMP;
wire [3:0]     I0_JB_RD_MASK;
wire [3:0]     I0_JB_RB1;
wire [3:0]     I0_JB_R2_IMM4;
wire [11:0]    I0_JB_IMM12;
wire           I1_LS_STORE;
wire [3:0]     I1_LS_LENG;
wire [3:0]     I1_LS_RD_RS;
wire [3:0]     I1_LS_RB;
wire [15:0]    I1_LS_DISP16;
wire [1:0]     I1_EX_OP2MODE;
wire           I1_EX_SETCC;
wire [3:0]     I1_EX_EXU_OPC;
wire [3:0]     I1_EX_RB1;
wire [3:0]     I1_EX_RS2;
wire [3:0]     I1_EX_RD;
wire [11:0]    I1_EX_DISP12;
wire           I1_JB_COND;
wire           I1_JB_REG;
wire           I1_JB_LINK;
wire           I1_JB_CMP;
wire [3:0]     I1_JB_RD_MASK;
wire [3:0]     I1_JB_RB1;
wire [3:0]     I1_JB_R2_IMM4;
wire [11:0]    I1_JB_IMM12;
wire           I0_IS_LEGAL;
wire           I1_IS_LEGAL;
wire [2:0]     I0_LS_OPC_H;
wire           I0_EX_OPC_H;
wire [3:0]     I0_INSN_OPC;
wire [1:0]     I0_PRIV_OPC;
wire [2:0]     I1_LS_OPC_H;
wire           I1_EX_OPC_H;
wire [3:0]     I1_INSN_OPC;
// ---- 020-d-iss.ch
wire           DD_I0_LS_FMT;
wire           DD_I0_EX_FMT;
wire           DD_I0_JB_FMT;
wire           DD_I1_LS_FMT;
wire           DD_I1_EX_FMT;
wire           DD_I1_JB_FMT;
wire           DD_FIRST_IS_LS;
wire           DD_SECOND_IS_LS;
wire           DD_FIRST_IS_EX;
wire           DD_SECOND_IS_EX;
wire           DD_FIRST_IS_JB;
wire           DD_SECOND_IS_JB;
wire [1:0]     DD_PRIVCODE;
wire           DD_SECOND_PRIV_V;
wire           DD_FIRST_SETCC;
wire [3:0]     DD_FIRST_WAD;
wire           DD_FIRST_WAD_V;
wire           DD_FIRST_RADB_V;
wire           DD_FIRST_RAD2_V;
wire           DD_FIRST_RAD1_V;
wire [3:0]     DD_FIRST_RADB1;
wire [3:0]     DD_FIRST_RAD2;
wire           DD_SECOND_SETCC;
wire [3:0]     DD_SECOND_WAD;
wire           DD_SECOND_WAD_V;
wire           DD_SECOND_RADB_V;
wire           DD_SECOND_RAD2_V;
wire           DD_SECOND_RAD1_V;
wire [3:0]     DD_SECOND_RADB1;
wire [3:0]     DD_SECOND_RAD2;
// ---- 030-d-sec.ch
wire           I0_V_NOINT;
wire [2:0]     DD_INTCODE;
wire           DD_ISSUE_SECOND_INSN;
wire           ILS_V;
wire [31:0]    ILS;
wire           IEX_V;
wire [31:0]    IEX;
wire           IJB_V;
wire [31:0]    IJB;
// ---- 035-d-ixx.ch
wire           ILS_STORE;
wire [3:0]     ILS_LENG;
wire [3:0]     ILS_RD_RS;
wire [3:0]     ILS_RB;
wire [15:0]    ILS_DISP16;
wire [1:0]     ILS_OP2MODE;
wire           ILS_SETCC;
wire [3:0]     ILS_EXU_OPC;
wire [3:0]     ILS_RS2;
wire [3:0]     ILS_RD;
wire [11:0]    ILS_DISP12;
wire [1:0]     IEX_OP2MODE;
wire           IEX_SETCC;
wire [3:0]     IEX_EXU_OPC;
wire [3:0]     IEX_RB1;
wire [3:0]     IEX_RS2;
wire [3:0]     IEX_RD;
wire [11:0]    IEX_DISP12;
wire           IJB_COND;
wire           IJB_REG;
wire           IJB_LINK;
wire           IJB_CMP;
wire [3:0]     IJB_RD_MASK;
wire [3:0]     IJB_RB1;
wire [3:0]     IJB_R2_IMM4;
wire [11:0]    IJB_IMM12;
wire [15:0]    IEX_IMM16;
wire [15:0]    IJB_IMM16;
wire [19:0]    IJB_IMM20;
wire           IJB_BACKWARD;
wire [2:0]     ILS_LS_OPC_H;
wire           ILS_EX_OPC_H;
wire           ILS_LS_FMT;
wire           ILS_EXRM_FMT;
// ---- 040-d-bra.ch
wire [31:0]    DD_JB_INSN_AD_PART1;
wire [5:0]     DD_JB_INSN_AD_PART2;
wire           IJB_IS_BA;
wire           IJB_IS_JA;
wire           IJB_IS_BL;
wire           IJB_IS_JL;
wire           IJB_IS_BC;
wire           DD_SETCC;
wire           DD_ISSUEING_SOLVED_BC;
wire [1:0]     DD_CC_FOR_SOLVED_BC;
wire           DD_SOLVED_BC_TAKEN;
wire           DD_ISSUEING_TAKEN_BRANCH;
wire           DD_ISSUEING_UNTAKEN_BC;
wire           DD_ISSUEING_UNSOLVED_BC;
wire           DD_ISSUEING_UNSOLVED_BC_ON_D_EX;
wire           DD_ISSUEING_UNSOLVED_BC_ON_D_LS;
wire           DD_ISSUEING_UNSOLVED_BC_ON_A_EX;
wire           DD_ISSUEING_UNSOLVED_BC_ON_A_LS;
wire           DD_ISSUEING_UNSOLVED_BC_ON_B_LS;
wire           DD_ISSUEING_UNSOLVED_BC_ON_E_LS;
wire           DD_PREDICTING_TAKEN;
wire [15:0]    DD_DISP;
wire [31:0]    DD_TGT;
// ---- 045-g-ram.ch
// ---- 050-op-lb1.ch
wire           WW_WSR;
wire           WW_RFE;
wire           WW_LS_INT_V;
wire           WW_EX_INT_V;
wire           WW_STATECHANGE;
wire           WW_INTERRUPTION;
wire           CANCEL_BY_INT;
wire           CANCEL_BY_BC;
wire           OP_B_CANCELLED;
wire           OP_WAIT_CANCELLED;
wire           OP_B_V_NOCAN;
wire           OP_WAIT_V_NOCAN;
wire [2:0]     OP_B_INTCODE;
wire           B_OPCLH;
wire           SU_OP_RDY;
wire           SU_ST_RDY;
wire [31:0]    OP_LBS_DATA;
// ---- 060-g-srq.ch
wire           E_V_NOCAN;
wire           B_V_NOCAN;
wire           A_V_NOCAN;
wire           A_EAB;
wire           AA_LD_REQ_VAL;
wire           WW_ST_REQ_VAL;
wire           AA_LD_GO;
wire           WW_ST_GO;
// ---- 070-g-ilk.ch
wire           E_STB_INTLK;
wire           E_LMD_INTLK;
wire           A_SBS_INTLK;
wire           D_V_NOCAN;
wire           D_BC_2ND_INTLK;
wire           D_PIPECLR_INTLK;
wire           E_INTLK;
wire           B_INTLK;
wire           A_INTLK;
wire           D_INTLK;
wire           E_FWD;
wire           B_FWD;
wire           A_FWD;
wire           D_FWD;
wire [3:0]     E_STAT;
wire [3:0]     B_STAT;
wire [3:0]     A_STAT;
wire [3:0]     D_STAT;
// ---- 080-w-act.ch
reg  [31:0]    TBR;
wire [31:0]    TBR_NEW;
reg  [31:0]    CMPR;
wire [31:0]    CMPR_NEW;
reg  [31:0]    SVR0;
wire [31:0]    SVR0_NEW;
reg  [31:0]    SVR1;
wire [31:0]    SVR1_NEW;
wire [4:0]     PC_INCR_AMOUNT;
wire [31:0]    INCREMENTED_PC;
wire [31:0]    MODIFIED_PC;
wire [1:0]     MODIFIED_CC;
wire           WW_HIDE_LS;
wire [2:0]     WW_INTCODE;
reg  [1:0]     PSW_CC;
wire [1:0]     PSW_CC_NEW;
reg            PSW_USER;
wire           PSW_USER_NEW;
reg  [7:0]     PSW_TYPE;
wire [7:0]     PSW_TYPE_NEW;
wire [31:0]    PC_NEW;
reg  [31:0]    XPSW;
wire [31:0]    XPSW_NEW;
reg  [31:0]    XPC;
wire [31:0]    XPC_NEW;
reg  [31:0]    XLA;
wire [31:0]    XLA_NEW;
reg            START_TRIGGER_BAR;
wire           START_TRIGGER_BAR_NEW;
wire           START_TRIGGER;
// ---- 090-e-act.ch
wire [31:0]    EE_MEMOP;
wire [31:0]    EE_OPS;
wire [2:0]     EE_LS_INTCODE;
wire           EE_LS_INT_V;
wire           EE_EX_INT_V;
wire           EE_HIDE_EX;
wire           EE_HIDE_LS;
wire           EE_SET_CC_FROM_LS;
wire           EE_SET_CC_FROM_EX;
wire [3:0]     W_WAD1_NEW;
wire [3:0]     W_WAD2_NEW;
wire [31:0]    W_WDT1_NEW;
wire [31:0]    W_WDT2_NEW;
reg  [31:0]    W_TGT;
wire [31:0]    W_TGT_NEW;
reg            W_IS_SUPERSCALAR;
wire           W_IS_SUPERSCALAR_NEW;
reg            W_LATTER_IS_JB;
wire           W_LATTER_IS_JB_NEW;
reg            W_FIRST_IS_EX;
wire           W_FIRST_IS_EX_NEW;
reg  [1:0]     W_CC;
wire [1:0]     W_CC_NEW;
wire           W_WE1_NEW;
wire           W_WE2_NEW;
reg            W_SETCC;
wire           W_SETCC_NEW;
reg            W_COMPLETE;
wire           W_COMPLETE_NEW;
reg  [1:0]     W_PRIVCODE;
wire [1:0]     W_PRIVCODE_NEW;
reg  [2:0]     W_EX_INTCODE;
wire [2:0]     W_EX_INTCODE_NEW;
reg  [2:0]     W_LS_INTCODE;
wire [2:0]     W_LS_INTCODE_NEW;
reg            W_JB_V;
wire           W_JB_V_NEW;
reg            STB_V;
wire           STB_V_NEW;
reg  [31:0]    STB_AD;
wire [31:0]    STB_AD_NEW;
reg  [31:0]    STB_DT;
wire [31:0]    STB_DT_NEW;
// ---- 100-b-dat.ch
reg  [31:0]    E_LS_OPS_DT;
wire [31:0]    E_LS_OPS_DT_NEW;
reg            E_OPCLH_LCH;
wire           E_OPCLH_LCH_NEW;
reg  [2:0]     E_LS_INTCODE;
wire [2:0]     E_LS_INTCODE_NEW;
wire [31:0]    BB_MEM_DATA;
reg  [31:0]    E_LS_LD_DT;
wire [31:0]    E_LS_LD_DT_NEW;
// ---- 110-b-act.ch
reg            E_V;
wire           E_V_NEW;
reg            E_JB_IS_BC;
wire           E_JB_IS_BC_NEW;
reg            E_JB_SUBJECT_TO_BC;
wire           E_JB_SUBJECT_TO_BC_NEW;
reg            E_JB_V;
wire           E_JB_V_NEW;
reg            E_LS_SOLVING_BC;
wire           E_LS_SOLVING_BC_NEW;
reg            E_LS_LD_V;
wire           E_LS_LD_V_NEW;
reg            E_LS_ST_V;
wire           E_LS_ST_V_NEW;
reg            E_WE1;
wire           E_WE1_NEW;
reg            E_WE2;
wire           E_WE2_NEW;
reg            E_LS_SETCC;
wire           E_LS_SETCC_NEW;
reg            E_EX_SETCC;
wire           E_EX_SETCC_NEW;
reg  [2:0]     E_EX_INTCODE;
wire [2:0]     E_EX_INTCODE_NEW;
reg  [1:0]     E_PRIVCODE;
wire [1:0]     E_PRIVCODE_NEW;
reg  [31:0]    E_LS_LOG_AD;
wire [31:0]    E_LS_LOG_AD_NEW;
reg  [3:0]     E_WAD1;
wire [3:0]     E_WAD1_NEW;
reg  [3:0]     E_WAD2;
wire [3:0]     E_WAD2_NEW;
reg            E_LS_OPS_IS_GR;
wire           E_LS_OPS_IS_GR_NEW;
reg  [3:0]     E_LS_RADS;
wire [3:0]     E_LS_RADS_NEW;
reg  [31:0]    E_EX_RES;
wire [31:0]    E_EX_RES_NEW;
reg  [1:0]     E_EX_CC;
wire [1:0]     E_EX_CC_NEW;
reg  [31:0]    E_TGT;
wire [31:0]    E_TGT_NEW;
reg            E_IS_SUPERSCALAR;
wire           E_IS_SUPERSCALAR_NEW;
reg            E_LATTER_IS_JB;
wire           E_LATTER_IS_JB_NEW;
reg            E_FIRST_IS_EX;
wire           E_FIRST_IS_EX_NEW;
reg  [4:0]     E_LS_OPCODE;
wire [4:0]     E_LS_OPCODE_NEW;
// ---- 120-a-dat.ch
wire [31:0]    AA_OPB;
wire [31:0]    AA_OP1;
wire [31:0]    AA_OP2;
wire [31:0]    AA_EAG_OUTPUT;
wire [31:0]    A_SR_READ_DATA;
wire [31:0]    AA_EX_RES;
// ---- 130-a-act.ch
reg            B_V;
wire           B_V_NEW;
reg            B_JB_IS_BC;
wire           B_JB_IS_BC_NEW;
reg            B_JB_SUBJECT_TO_BC;
wire           B_JB_SUBJECT_TO_BC_NEW;
reg            B_JB_V;
wire           B_JB_V_NEW;
reg            B_LS_SOLVING_BC;
wire           B_LS_SOLVING_BC_NEW;
reg  [2:0]     B_INTCODE;
wire [2:0]     B_INTCODE_NEW;
reg  [1:0]     B_PRIVCODE;
wire [1:0]     B_PRIVCODE_NEW;
reg            B_LS_LD_V;
wire           B_LS_LD_V_NEW;
reg            B_LS_ST_V;
wire           B_LS_ST_V_NEW;
reg            B_WE1;
wire           B_WE1_NEW;
reg            B_WE2;
wire           B_WE2_NEW;
reg            B_LS_SETCC;
wire           B_LS_SETCC_NEW;
reg            B_EX_SETCC;
wire           B_EX_SETCC_NEW;
reg  [31:0]    B_LS_LOG_AD;
wire [31:0]    B_LS_LOG_AD_NEW;
reg  [3:0]     B_WAD1;
wire [3:0]     B_WAD1_NEW;
reg  [3:0]     B_WAD2;
wire [3:0]     B_WAD2_NEW;
reg            B_LS_OPS_IS_GR;
wire           B_LS_OPS_IS_GR_NEW;
wire [3:0]     B_LS_RADS_NEW;
reg  [4:0]     B_LS_OPCODE;
wire [4:0]     B_LS_OPCODE_NEW;
reg            B_IS_SUPERSCALAR;
wire           B_IS_SUPERSCALAR_NEW;
reg            B_LATTER_IS_JB;
wire           B_LATTER_IS_JB_NEW;
reg            B_FIRST_IS_EX;
wire           B_FIRST_IS_EX_NEW;
reg  [3:0]     B_EX_RAD2;
wire [3:0]     B_EX_RAD2_NEW;
reg  [31:0]    B_TGT;
wire [31:0]    B_TGT_NEW;
reg  [31:0]    B_EX_RES;
wire [31:0]    B_EX_RES_NEW;
reg  [1:0]     B_EX_CC;
wire [1:0]     B_EX_CC_NEW;
// ---- 140-d-dat.ch
reg            A_LS_OPB_IS_GR;
wire           A_LS_OPB_IS_GR_NEW;
reg            A_EX_OP1_IS_GR;
wire           A_EX_OP1_IS_GR_NEW;
reg            A_EX_OP2_IS_GR;
wire           A_EX_OP2_IS_GR_NEW;
wire [5:0]     DD_JB_INSN_AD_PART2P4;
reg  [31:0]    A_LS_OPB_DT;
wire [31:0]    A_LS_OPB_DT_NEW;
reg  [31:0]    A_EX_OP1_DT;
wire [31:0]    A_EX_OP1_DT_NEW;
reg  [31:0]    A_EX_OP2_DT;
wire [31:0]    A_EX_OP2_DT_NEW;
reg  [3:0]     A_LS_RADB;
wire [3:0]     A_LS_RADB_NEW;
reg  [3:0]     A_EX_RAD1;
wire [3:0]     A_EX_RAD1_NEW;
reg  [3:0]     A_EX_RAD2;
wire [3:0]     A_EX_RAD2_NEW;
reg  [15:0]    A_DISP;
wire [15:0]    A_DISP_NEW;
// ---- 150-d-act.ch
reg            A_V;
wire           A_V_NEW;
reg            A_JB_IS_BC;
wire           A_JB_IS_BC_NEW;
reg            A_JB_SUBJECT_TO_BC;
wire           A_JB_SUBJECT_TO_BC_NEW;
reg            A_JB_V;
wire           A_JB_V_NEW;
reg            A_LS_SOLVING_BC;
wire           A_LS_SOLVING_BC_NEW;
reg            A_EX_SOLVING_BC;
wire           A_EX_SOLVING_BC_NEW;
reg  [2:0]     A_INTCODE;
wire [2:0]     A_INTCODE_NEW;
reg  [1:0]     A_PRIVCODE;
wire [1:0]     A_PRIVCODE_NEW;
reg            A_LS_LD_V;
wire           A_LS_LD_V_NEW;
reg            A_WE1;
wire           A_WE1_NEW;
reg            A_LS_ST_V;
wire           A_LS_ST_V_NEW;
reg            A_LS_OPS_IS_GR;
wire           A_LS_OPS_IS_GR_NEW;
reg            A_LS_SETCC;
wire           A_LS_SETCC_NEW;
reg            A_EX_SETCC;
wire           A_EX_SETCC_NEW;
reg            A_WE2;
wire           A_WE2_NEW;
reg  [3:0]     A_WAD1;
wire [3:0]     A_WAD1_NEW;
reg  [3:0]     A_LS_RADS;
wire [3:0]     A_LS_RADS_NEW;
reg  [3:0]     A_WAD2;
wire [3:0]     A_WAD2_NEW;
reg  [4:0]     A_LS_OPCODE;
wire [4:0]     A_LS_OPCODE_NEW;
reg            A_IS_SUPERSCALAR;
wire           A_IS_SUPERSCALAR_NEW;
reg            A_FIRST_IS_EX;
wire           A_FIRST_IS_EX_NEW;
reg            A_LATTER_IS_JB;
wire           A_LATTER_IS_JB_NEW;
reg  [31:0]    A_TGT;
wire [31:0]    A_TGT_NEW;
reg  [3:0]     A_EX_OPCODE;
wire [3:0]     A_EX_OPCODE_NEW;
reg            A_SET_EAG_TO_TGT;
wire           A_SET_EAG_TO_TGT_NEW;
// ---- 160-op-lb2.ch
wire           OP_B_FORWARDING;
wire           GO_SU;
wire [1:0]     ACCEPTING_OPC;
wire [31:0]    ACCEPTING_AD;
wire           OP_WAIT_STAYS;
wire           OP_WAIT_ACCEPT;
reg            OP_WAIT_V;
wire           OP_WAIT_V_NEW;
reg  [1:0]     OP_WAIT_OPC;
wire [1:0]     OP_WAIT_OPC_NEW;
reg            OP_WAIT_WE;
wire           OP_WAIT_WE_NEW;
reg  [31:0]    OP_WAIT_AD;
wire [31:0]    OP_WAIT_AD_NEW;
reg  [31:0]    OP_WAIT_DT;
wire [31:0]    OP_WAIT_DT_NEW;
reg            OP_WAIT_SUBJECT_TO_BC;
wire           OP_WAIT_SUBJECT_TO_BC_NEW;
wire           OP_B_STAYS;
wire           OP_B_SHIFT;
reg            OP_B_V;
wire           OP_B_V_NEW;
reg  [1:0]     OP_B_OPC;
wire [1:0]     OP_B_OPC_NEW;
wire           LBS_WE_NEW;
wire [31:0]    LBS_AD_NEW;
wire [31:0]    LBS_DT_NEW;
reg            OP_B_SUBJECT_TO_BC;
wire           OP_B_SUBJECT_TO_BC_NEW;
// ---- 170-if-req.ch
wire           IWQ_FULL;
wire [31:0]    IF_INCR_1;
wire [4:0]     IF_INCR_2;
wire [31:0]    IF_INCR_OUT;
wire           IF_CASE_START;
wire           IF_CASE_J;
wire           IF_CASE_BA;
wire           IF_CASE_BC;
wire           IF_CASE_NULL;
wire           IF_REQ_V;
wire [31:0]    IF_REQ_AD;
wire           IF_REQ_ID;
wire           CANCEL_IB;
// ---- 180-if-lbs.ch
wire           SU_IF_CLH;
wire           SU_IF_RDY;
wire [31:0]    I_LBS_H;
wire [31:0]    I_LBS_L;
// ---- 190-if-stm.ch
reg            IB_V;
wire           IB_V_NEW;
wire [31:0]    IB_AD_NEW;
reg            IB_ID;
wire           IB_ID_NEW;
reg            CUR_IWQ_ID;
wire           CUR_IWQ_ID_NEW;
wire           SU_IF_CLH_NOCAN;
wire [1:0]     EMIT;
wire [1:0]     EMIT_FOR_A;
wire [2:0]     NIP_AFTER_EMIT_A;
wire [1:0]     EMIT_FOR_B;
wire [2:0]     NIP_AFTER_EMIT_B;
wire           SFTUP_A;
wire           SFTUP_B;
wire           DD_JB_TKN;
wire           CLEAR_NIP_A;
wire           CLEAR_NIP_B;
wire [2:0]     NIP_A_TMP;
reg  [2:0]     NIP_B;
wire [2:0]     NIP_B_NEW;
reg  [2:0]     NIP_A_REG;
wire [2:0]     NIP_A_REG_NEW;
reg  [31:0]    D_IF_AD_A;
wire [31:0]    D_IF_AD_A_NEW;
reg  [31:0]    D_IF_AD_B;
wire [31:0]    D_IF_AD_B_NEW;
// ---- 200-if-iwq.ch
reg  [31:0]    IWQ_A_0;
wire [31:0]    IWQ_A_0_NEW;
reg  [31:0]    IWQ_A_1;
wire [31:0]    IWQ_A_1_NEW;
reg  [31:0]    IWQ_A_2;
wire [31:0]    IWQ_A_2_NEW;
reg  [31:0]    IWQ_A_3;
wire [31:0]    IWQ_A_3_NEW;
reg            IWQ_A_V01;
wire           IWQ_A_V01_NEW;
reg            IWQ_A_V23;
wire           IWQ_A_V23_NEW;
reg  [31:0]    IWQ_B_0;
wire [31:0]    IWQ_B_0_NEW;
reg  [31:0]    IWQ_B_1;
wire [31:0]    IWQ_B_1_NEW;
reg  [31:0]    IWQ_B_2;
wire [31:0]    IWQ_B_2_NEW;
reg  [31:0]    IWQ_B_3;
wire [31:0]    IWQ_B_3_NEW;
reg            IWQ_B_V01;
wire           IWQ_B_V01_NEW;
reg            IWQ_B_V23;
wire           IWQ_B_V23_NEW;
reg  [31:0]    IWQ_A_4;
wire [31:0]    IWQ_A_4_NEW;
reg  [31:0]    IWQ_A_5;
wire [31:0]    IWQ_A_5_NEW;
reg  [31:0]    IWQ_B_4;
wire [31:0]    IWQ_B_4_NEW;
reg  [31:0]    IWQ_B_5;
wire [31:0]    IWQ_B_5_NEW;
reg            IWQ_A_V45;
wire           IWQ_A_V45_NEW;
reg            IWQ_B_V45;
wire           IWQ_B_V45_NEW;
// ---- 210-g-bc.ch
wire           GG_SOLVING_CASE_ON_E;
wire           GG_SOLVING_CASE_ON_A;
wire           GG_SOLVING_CASE;
wire [3:0]     GG_MASK_FOR_BC;
wire [1:0]     GG_CC_FOR_BC;
wire           GG_ISSUEING_CASE;
reg            G_BC_PENDING;
wire           G_BC_PENDING_NEW;
reg            G_BC_JUST_SOLVED;
wire           G_BC_JUST_SOLVED_NEW;
reg            G_BC_JUST_TAKEN;
wire           G_BC_JUST_TAKEN_NEW;
reg            G_BC_TKN_PREDICTED;
wire           G_BC_TKN_PREDICTED_NEW;
reg  [3:0]     G_BC_MASK;
wire [3:0]     G_BC_MASK_NEW;
// ---- EXU の出力 (090-e-act.ch / 120-a-dat.ch の exu() 呼び出し)
wire [1:0]     EE_ALU_CC;
wire [31:0]    EE_ALU_OUTPUT;
wire [2:0]     EE_ALU_INT;
wire [1:0]     AA_EXU_CC;
wire [31:0]    AA_EXU_OUTPUT;
wire [2:0]     AA_EXU_INT;

// ---------------------------------------------------------------------
//  回路本体 (hard/*.ch を 1 対 1 に変換したもの)
// ---------------------------------------------------------------------
`include "ch/010_d_pre.vh"
`include "ch/015_d_i01.vh"
`include "ch/020_d_iss.vh"
`include "ch/030_d_sec.vh"
`include "ch/035_d_ixx.vh"
`include "ch/040_d_bra.vh"
`include "ch/045_g_ram.vh"
`include "ch/050_op_lb1.vh"
`include "ch/060_g_srq.vh"
`include "ch/070_g_ilk.vh"
`include "ch/080_w_act.vh"
`include "ch/090_e_act.vh"
`include "ch/100_b_dat.vh"
`include "ch/110_b_act.vh"
`include "ch/120_a_dat.vh"
`include "ch/130_a_act.vh"
`include "ch/140_d_dat.vh"
`include "ch/150_d_act.vh"
`include "ch/160_op_lb2.vh"
`include "ch/170_if_req.vh"
`include "ch/180_if_lbs.vh"
`include "ch/190_if_stm.vh"
`include "ch/200_if_iwq.vh"
`include "ch/210_g_bc.vh"

// ---------------------------------------------------------------------
//  FF の更新 (C 版の「サイクルの最後に X = X_NEW」に相当)
// ---------------------------------------------------------------------
// 【解説】すべての FF をここで一斉に更新する。各 X_NEW は ch/*.vh で
//         CHDL の 'X := 式' から作った D 入力。
//         同期リセット: rst=1 の間のクロックで 0 (PC は RESET_PC) にする。
//         (PC のリセット値が定数ではなく入力 RESET_PC なので、非同期リセットに
//          すると FPGA ではラッチで代用されてしまう。そのため同期リセットにしている)
always @(posedge clk) begin
  if (rst) begin
    TBR                     <= 0;
    CMPR                    <= 0;
    SVR0                    <= 0;
    SVR1                    <= 0;
    PSW_CC                  <= 0;
    PSW_USER                <= 0;
    PSW_TYPE                <= 0;
    PC                      <= RESET_PC;
    XPSW                    <= 0;
    XPC                     <= 0;
    XLA                     <= 0;
    START_TRIGGER_BAR       <= 0;
    W_WAD1                  <= 0;
    W_WAD2                  <= 0;
    W_WDT1                  <= 0;
    W_WDT2                  <= 0;
    W_TGT                   <= 0;
    W_IS_SUPERSCALAR        <= 0;
    W_LATTER_IS_JB          <= 0;
    W_FIRST_IS_EX           <= 0;
    W_CC                    <= 0;
    W_WE1                   <= 0;
    W_WE2                   <= 0;
    W_SETCC                 <= 0;
    W_COMPLETE              <= 0;
    W_PRIVCODE              <= 0;
    W_EX_INTCODE            <= 0;
    W_LS_INTCODE            <= 0;
    W_JB_V                  <= 0;
    STB_V                   <= 0;
    STB_AD                  <= 0;
    STB_DT                  <= 0;
    E_LS_OPS_DT             <= 0;
    E_OPCLH_LCH             <= 0;
    E_LS_INTCODE            <= 0;
    E_LS_LD_DT              <= 0;
    E_V                     <= 0;
    E_JB_IS_BC              <= 0;
    E_JB_SUBJECT_TO_BC      <= 0;
    E_JB_V                  <= 0;
    E_LS_SOLVING_BC         <= 0;
    E_LS_LD_V               <= 0;
    E_LS_ST_V               <= 0;
    E_WE1                   <= 0;
    E_WE2                   <= 0;
    E_LS_SETCC              <= 0;
    E_EX_SETCC              <= 0;
    E_EX_INTCODE            <= 0;
    E_PRIVCODE              <= 0;
    E_LS_LOG_AD             <= 0;
    E_WAD1                  <= 0;
    E_WAD2                  <= 0;
    E_LS_OPS_IS_GR          <= 0;
    E_LS_RADS               <= 0;
    E_EX_RES                <= 0;
    E_EX_CC                 <= 0;
    E_TGT                   <= 0;
    E_IS_SUPERSCALAR        <= 0;
    E_LATTER_IS_JB          <= 0;
    E_FIRST_IS_EX           <= 0;
    E_LS_OPCODE             <= 0;
    B_V                     <= 0;
    B_JB_IS_BC              <= 0;
    B_JB_SUBJECT_TO_BC      <= 0;
    B_JB_V                  <= 0;
    B_LS_SOLVING_BC         <= 0;
    B_INTCODE               <= 0;
    B_PRIVCODE              <= 0;
    B_LS_LD_V               <= 0;
    B_LS_ST_V               <= 0;
    B_WE1                   <= 0;
    B_WE2                   <= 0;
    B_LS_SETCC              <= 0;
    B_EX_SETCC              <= 0;
    B_LS_LOG_AD             <= 0;
    B_WAD1                  <= 0;
    B_WAD2                  <= 0;
    B_LS_OPS_IS_GR          <= 0;
    B_LS_RADS               <= 0;
    B_LS_OPCODE             <= 0;
    B_IS_SUPERSCALAR        <= 0;
    B_LATTER_IS_JB          <= 0;
    B_FIRST_IS_EX           <= 0;
    B_EX_RAD2               <= 0;
    B_TGT                   <= 0;
    B_EX_RES                <= 0;
    B_EX_CC                 <= 0;
    A_LS_OPB_IS_GR          <= 0;
    A_EX_OP1_IS_GR          <= 0;
    A_EX_OP2_IS_GR          <= 0;
    A_LS_OPB_DT             <= 0;
    A_EX_OP1_DT             <= 0;
    A_EX_OP2_DT             <= 0;
    A_LS_RADB               <= 0;
    A_EX_RAD1               <= 0;
    A_EX_RAD2               <= 0;
    A_DISP                  <= 0;
    A_V                     <= 0;
    A_JB_IS_BC              <= 0;
    A_JB_SUBJECT_TO_BC      <= 0;
    A_JB_V                  <= 0;
    A_LS_SOLVING_BC         <= 0;
    A_EX_SOLVING_BC         <= 0;
    A_INTCODE               <= 0;
    A_PRIVCODE              <= 0;
    A_LS_LD_V               <= 0;
    A_WE1                   <= 0;
    A_LS_ST_V               <= 0;
    A_LS_OPS_IS_GR          <= 0;
    A_LS_SETCC              <= 0;
    A_EX_SETCC              <= 0;
    A_WE2                   <= 0;
    A_WAD1                  <= 0;
    A_LS_RADS               <= 0;
    A_WAD2                  <= 0;
    A_LS_OPCODE             <= 0;
    A_IS_SUPERSCALAR        <= 0;
    A_FIRST_IS_EX           <= 0;
    A_LATTER_IS_JB          <= 0;
    A_TGT                   <= 0;
    A_EX_OPCODE             <= 0;
    A_SET_EAG_TO_TGT        <= 0;
    OP_WAIT_V               <= 0;
    OP_WAIT_OPC             <= 0;
    OP_WAIT_WE              <= 0;
    OP_WAIT_AD              <= 0;
    OP_WAIT_DT              <= 0;
    OP_WAIT_SUBJECT_TO_BC   <= 0;
    OP_B_V                  <= 0;
    OP_B_OPC                <= 0;
    LBS_WE                  <= 0;
    LBS_AD                  <= 0;
    LBS_DT                  <= 0;
    OP_B_SUBJECT_TO_BC      <= 0;
    IB_V                    <= 0;
    IB_AD                   <= 0;
    IB_ID                   <= 0;
    CUR_IWQ_ID              <= 0;
    NIP_B                   <= 0;
    NIP_A_REG               <= 0;
    D_IF_AD_A               <= 0;
    D_IF_AD_B               <= 0;
    IWQ_A_0                 <= 0;
    IWQ_A_1                 <= 0;
    IWQ_A_2                 <= 0;
    IWQ_A_3                 <= 0;
    IWQ_A_V01               <= 0;
    IWQ_A_V23               <= 0;
    IWQ_B_0                 <= 0;
    IWQ_B_1                 <= 0;
    IWQ_B_2                 <= 0;
    IWQ_B_3                 <= 0;
    IWQ_B_V01               <= 0;
    IWQ_B_V23               <= 0;
    IWQ_A_4                 <= 0;
    IWQ_A_5                 <= 0;
    IWQ_B_4                 <= 0;
    IWQ_B_5                 <= 0;
    IWQ_A_V45               <= 0;
    IWQ_B_V45               <= 0;
    G_BC_PENDING            <= 0;
    G_BC_JUST_SOLVED        <= 0;
    G_BC_JUST_TAKEN         <= 0;
    G_BC_TKN_PREDICTED      <= 0;
    G_BC_MASK               <= 0;
  end else begin
    TBR                     <= TBR_NEW;
    CMPR                    <= CMPR_NEW;
    SVR0                    <= SVR0_NEW;
    SVR1                    <= SVR1_NEW;
    PSW_CC                  <= PSW_CC_NEW;
    PSW_USER                <= PSW_USER_NEW;
    PSW_TYPE                <= PSW_TYPE_NEW;
    PC                      <= PC_NEW;
    XPSW                    <= XPSW_NEW;
    XPC                     <= XPC_NEW;
    XLA                     <= XLA_NEW;
    START_TRIGGER_BAR       <= START_TRIGGER_BAR_NEW;
    W_WAD1                  <= W_WAD1_NEW;
    W_WAD2                  <= W_WAD2_NEW;
    W_WDT1                  <= W_WDT1_NEW;
    W_WDT2                  <= W_WDT2_NEW;
    W_TGT                   <= W_TGT_NEW;
    W_IS_SUPERSCALAR        <= W_IS_SUPERSCALAR_NEW;
    W_LATTER_IS_JB          <= W_LATTER_IS_JB_NEW;
    W_FIRST_IS_EX           <= W_FIRST_IS_EX_NEW;
    W_CC                    <= W_CC_NEW;
    W_WE1                   <= W_WE1_NEW;
    W_WE2                   <= W_WE2_NEW;
    W_SETCC                 <= W_SETCC_NEW;
    W_COMPLETE              <= W_COMPLETE_NEW;
    W_PRIVCODE              <= W_PRIVCODE_NEW;
    W_EX_INTCODE            <= W_EX_INTCODE_NEW;
    W_LS_INTCODE            <= W_LS_INTCODE_NEW;
    W_JB_V                  <= W_JB_V_NEW;
    STB_V                   <= STB_V_NEW;
    STB_AD                  <= STB_AD_NEW;
    STB_DT                  <= STB_DT_NEW;
    E_LS_OPS_DT             <= E_LS_OPS_DT_NEW;
    E_OPCLH_LCH             <= E_OPCLH_LCH_NEW;
    E_LS_INTCODE            <= E_LS_INTCODE_NEW;
    E_LS_LD_DT              <= E_LS_LD_DT_NEW;
    E_V                     <= E_V_NEW;
    E_JB_IS_BC              <= E_JB_IS_BC_NEW;
    E_JB_SUBJECT_TO_BC      <= E_JB_SUBJECT_TO_BC_NEW;
    E_JB_V                  <= E_JB_V_NEW;
    E_LS_SOLVING_BC         <= E_LS_SOLVING_BC_NEW;
    E_LS_LD_V               <= E_LS_LD_V_NEW;
    E_LS_ST_V               <= E_LS_ST_V_NEW;
    E_WE1                   <= E_WE1_NEW;
    E_WE2                   <= E_WE2_NEW;
    E_LS_SETCC              <= E_LS_SETCC_NEW;
    E_EX_SETCC              <= E_EX_SETCC_NEW;
    E_EX_INTCODE            <= E_EX_INTCODE_NEW;
    E_PRIVCODE              <= E_PRIVCODE_NEW;
    E_LS_LOG_AD             <= E_LS_LOG_AD_NEW;
    E_WAD1                  <= E_WAD1_NEW;
    E_WAD2                  <= E_WAD2_NEW;
    E_LS_OPS_IS_GR          <= E_LS_OPS_IS_GR_NEW;
    E_LS_RADS               <= E_LS_RADS_NEW;
    E_EX_RES                <= E_EX_RES_NEW;
    E_EX_CC                 <= E_EX_CC_NEW;
    E_TGT                   <= E_TGT_NEW;
    E_IS_SUPERSCALAR        <= E_IS_SUPERSCALAR_NEW;
    E_LATTER_IS_JB          <= E_LATTER_IS_JB_NEW;
    E_FIRST_IS_EX           <= E_FIRST_IS_EX_NEW;
    E_LS_OPCODE             <= E_LS_OPCODE_NEW;
    B_V                     <= B_V_NEW;
    B_JB_IS_BC              <= B_JB_IS_BC_NEW;
    B_JB_SUBJECT_TO_BC      <= B_JB_SUBJECT_TO_BC_NEW;
    B_JB_V                  <= B_JB_V_NEW;
    B_LS_SOLVING_BC         <= B_LS_SOLVING_BC_NEW;
    B_INTCODE               <= B_INTCODE_NEW;
    B_PRIVCODE              <= B_PRIVCODE_NEW;
    B_LS_LD_V               <= B_LS_LD_V_NEW;
    B_LS_ST_V               <= B_LS_ST_V_NEW;
    B_WE1                   <= B_WE1_NEW;
    B_WE2                   <= B_WE2_NEW;
    B_LS_SETCC              <= B_LS_SETCC_NEW;
    B_EX_SETCC              <= B_EX_SETCC_NEW;
    B_LS_LOG_AD             <= B_LS_LOG_AD_NEW;
    B_WAD1                  <= B_WAD1_NEW;
    B_WAD2                  <= B_WAD2_NEW;
    B_LS_OPS_IS_GR          <= B_LS_OPS_IS_GR_NEW;
    B_LS_RADS               <= B_LS_RADS_NEW;
    B_LS_OPCODE             <= B_LS_OPCODE_NEW;
    B_IS_SUPERSCALAR        <= B_IS_SUPERSCALAR_NEW;
    B_LATTER_IS_JB          <= B_LATTER_IS_JB_NEW;
    B_FIRST_IS_EX           <= B_FIRST_IS_EX_NEW;
    B_EX_RAD2               <= B_EX_RAD2_NEW;
    B_TGT                   <= B_TGT_NEW;
    B_EX_RES                <= B_EX_RES_NEW;
    B_EX_CC                 <= B_EX_CC_NEW;
    A_LS_OPB_IS_GR          <= A_LS_OPB_IS_GR_NEW;
    A_EX_OP1_IS_GR          <= A_EX_OP1_IS_GR_NEW;
    A_EX_OP2_IS_GR          <= A_EX_OP2_IS_GR_NEW;
    A_LS_OPB_DT             <= A_LS_OPB_DT_NEW;
    A_EX_OP1_DT             <= A_EX_OP1_DT_NEW;
    A_EX_OP2_DT             <= A_EX_OP2_DT_NEW;
    A_LS_RADB               <= A_LS_RADB_NEW;
    A_EX_RAD1               <= A_EX_RAD1_NEW;
    A_EX_RAD2               <= A_EX_RAD2_NEW;
    A_DISP                  <= A_DISP_NEW;
    A_V                     <= A_V_NEW;
    A_JB_IS_BC              <= A_JB_IS_BC_NEW;
    A_JB_SUBJECT_TO_BC      <= A_JB_SUBJECT_TO_BC_NEW;
    A_JB_V                  <= A_JB_V_NEW;
    A_LS_SOLVING_BC         <= A_LS_SOLVING_BC_NEW;
    A_EX_SOLVING_BC         <= A_EX_SOLVING_BC_NEW;
    A_INTCODE               <= A_INTCODE_NEW;
    A_PRIVCODE              <= A_PRIVCODE_NEW;
    A_LS_LD_V               <= A_LS_LD_V_NEW;
    A_WE1                   <= A_WE1_NEW;
    A_LS_ST_V               <= A_LS_ST_V_NEW;
    A_LS_OPS_IS_GR          <= A_LS_OPS_IS_GR_NEW;
    A_LS_SETCC              <= A_LS_SETCC_NEW;
    A_EX_SETCC              <= A_EX_SETCC_NEW;
    A_WE2                   <= A_WE2_NEW;
    A_WAD1                  <= A_WAD1_NEW;
    A_LS_RADS               <= A_LS_RADS_NEW;
    A_WAD2                  <= A_WAD2_NEW;
    A_LS_OPCODE             <= A_LS_OPCODE_NEW;
    A_IS_SUPERSCALAR        <= A_IS_SUPERSCALAR_NEW;
    A_FIRST_IS_EX           <= A_FIRST_IS_EX_NEW;
    A_LATTER_IS_JB          <= A_LATTER_IS_JB_NEW;
    A_TGT                   <= A_TGT_NEW;
    A_EX_OPCODE             <= A_EX_OPCODE_NEW;
    A_SET_EAG_TO_TGT        <= A_SET_EAG_TO_TGT_NEW;
    OP_WAIT_V               <= OP_WAIT_V_NEW;
    OP_WAIT_OPC             <= OP_WAIT_OPC_NEW;
    OP_WAIT_WE              <= OP_WAIT_WE_NEW;
    OP_WAIT_AD              <= OP_WAIT_AD_NEW;
    OP_WAIT_DT              <= OP_WAIT_DT_NEW;
    OP_WAIT_SUBJECT_TO_BC   <= OP_WAIT_SUBJECT_TO_BC_NEW;
    OP_B_V                  <= OP_B_V_NEW;
    OP_B_OPC                <= OP_B_OPC_NEW;
    LBS_WE                  <= LBS_WE_NEW;
    LBS_AD                  <= LBS_AD_NEW;
    LBS_DT                  <= LBS_DT_NEW;
    OP_B_SUBJECT_TO_BC      <= OP_B_SUBJECT_TO_BC_NEW;
    IB_V                    <= IB_V_NEW;
    IB_AD                   <= IB_AD_NEW;
    IB_ID                   <= IB_ID_NEW;
    CUR_IWQ_ID              <= CUR_IWQ_ID_NEW;
    NIP_B                   <= NIP_B_NEW;
    NIP_A_REG               <= NIP_A_REG_NEW;
    D_IF_AD_A               <= D_IF_AD_A_NEW;
    D_IF_AD_B               <= D_IF_AD_B_NEW;
    IWQ_A_0                 <= IWQ_A_0_NEW;
    IWQ_A_1                 <= IWQ_A_1_NEW;
    IWQ_A_2                 <= IWQ_A_2_NEW;
    IWQ_A_3                 <= IWQ_A_3_NEW;
    IWQ_A_V01               <= IWQ_A_V01_NEW;
    IWQ_A_V23               <= IWQ_A_V23_NEW;
    IWQ_B_0                 <= IWQ_B_0_NEW;
    IWQ_B_1                 <= IWQ_B_1_NEW;
    IWQ_B_2                 <= IWQ_B_2_NEW;
    IWQ_B_3                 <= IWQ_B_3_NEW;
    IWQ_B_V01               <= IWQ_B_V01_NEW;
    IWQ_B_V23               <= IWQ_B_V23_NEW;
    IWQ_A_4                 <= IWQ_A_4_NEW;
    IWQ_A_5                 <= IWQ_A_5_NEW;
    IWQ_B_4                 <= IWQ_B_4_NEW;
    IWQ_B_5                 <= IWQ_B_5_NEW;
    IWQ_A_V45               <= IWQ_A_V45_NEW;
    IWQ_B_V45               <= IWQ_B_V45_NEW;
    G_BC_PENDING            <= G_BC_PENDING_NEW;
    G_BC_JUST_SOLVED        <= G_BC_JUST_SOLVED_NEW;
    G_BC_JUST_TAKEN         <= G_BC_JUST_TAKEN_NEW;
    G_BC_TKN_PREDICTED      <= G_BC_TKN_PREDICTED_NEW;
    G_BC_MASK               <= G_BC_MASK_NEW;
  end
end

endmodule
