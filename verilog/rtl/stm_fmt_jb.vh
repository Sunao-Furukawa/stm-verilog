// =====================================================================
//  stm_fmt_jb.vh  <-  hard/fmt-jb.h
//  JB (ジャンプ/分岐) 形式と特権命令形式のフィールド抽出関数
//
//  ビット番号: 図は CHDL 流 (MSB=0)。Verilog では [31:0] (MSB=31) に変換済み。
//
//  Field extraction functions for the JB (jump/branch) format and the privileged format.
//  Bit numbers: the figures use CHDL numbering (MSB=0); in Verilog they are converted to [31:0] (MSB=31).
//
// 【ネットリスト解説】ここの function はすべて「命令語のビットの一部を取り出す」
//   だけなので、回路としては配線 (LUT 0 個) にしかならない。例えば
//   jb_rd_mask(IJB) は IJB[23:20] の 4 本のネットにそのまま名前を付けたもの。
//   同じビットが jb_rd_mask (マスク) にも ex_rd (書き込み先) にもなるのは、
//   命令形式によってフィールドの意味が変わるからで、どの意味で使うかは
//   使う側の式 (020, 040, 150 など) が形式判定の結果で選ぶ。
//
// [Netlist notes] Every function here only takes out some bits of the instruction word,
//   so as a circuit they are only wiring (0 LUTs). For example jb_rd_mask(IJB) simply names
//   the 4 nets IJB[23:20]. The same bits become both jb_rd_mask (the mask) and ex_rd (the
//   destination) because the meaning of a field depends on the instruction format; which
//   meaning is used is chosen by the using expressions (020, 040, 150, ...) from the format decode.
// =====================================================================
/*JB :
# COND -- conditional branch
# R/PC -- addressing by Reg+Disp or PC-relative
# LNK  -- saving current PC to GR
# cmp  -- compares two GR's and then decide to branch
# LINK -- GR number to save PC
# MASK -- on which CC we should branch

#  When COND && cmp, only PC-rel. adr'sing is allowed. (no field)
#  No   COND && LNK. (For conditional function call, argument setting will
#			be inserted between compare and jump.)
#
#         +----- COND           #
#         |+---- REG            #
#         ||+--- LINK           #
#         |||+-- CMP            #
#         vvvv                  #
#    4      4    4    4      16
# +------+----+----+----+---------------+
# | 1011 |000.|....|   IMM20            |  uncond,  !LNK,  PC
# |      |010.|....| RB |   IMM16       |  uncond,  !LNK,  Reg
# +------+----+----+----+---------------+
# |      |001.| RD |   IMM20            |  uncond,   LNK,  PC
# |      |011.| RD | RB |   IMM16       |  uncond,   LNK,  Reg
# +------+----+----+----+---------------+
# |      |10.0|MASK|   IMM20            |    cond,  !cmp,  PC
# |      |11.0|MASK| RB |   IMM16       |    cond,  !cmp,  Reg --- deleted!
# |      |10.1|MASK| R1 | R2 |  IMM12   |    cond,   cmp,  PC
# +------+----+----+----+----+----------+
*/
function [3:0]  jb_opc_h   (input [31:0] i); jb_opc_h    = i[31:28]; endfunction // bit_ext(i,0,4)  -- i[31:28] の配線だけ (ゲート0): 上位4bit / wires only (no gate): top 4 bits
function        jb_cond    (input [31:0] i); jb_cond     = i[27];    endfunction // bit_ext(i,4,1)  -- i[27] の配線だけ (ゲート0): 条件分岐 / wires only (no gate): conditional
function        jb_reg     (input [31:0] i); jb_reg      = i[26];    endfunction // bit_ext(i,5,1)  -- i[26] の配線だけ (ゲート0): レジスタ相対 / wires only (no gate): register-relative
function        jb_link    (input [31:0] i); jb_link     = i[25];    endfunction // bit_ext(i,6,1)  -- i[25] の配線だけ (ゲート0): リンク / wires only (no gate): link
function        jb_cmp     (input [31:0] i); jb_cmp      = i[24];    endfunction // bit_ext(i,7,1)  -- i[24] の配線だけ (ゲート0): 比較分岐 / wires only (no gate): compare branch
function [3:0]  jb_rd_mask (input [31:0] i); jb_rd_mask  = i[23:20]; endfunction // bit_ext(i,8,4)  -- i[23:20] の配線だけ (ゲート0): リンク先GR / wires only (no gate): CCマスク
function [3:0]  jb_rb1     (input [31:0] i); jb_rb1      = i[19:16]; endfunction // bit_ext(i,12,4)  -- i[19:16] の配線だけ (ゲート0): ベース/比較の第1GR / wires only (no gate): base
function [3:0]  jb_r2_imm4 (input [31:0] i); jb_r2_imm4  = i[15:12]; endfunction // bit_ext(i,16,4)  -- i[15:12] の配線だけ (ゲート0): 比較の第2GR / wires only (no gate): second compare GR
function [11:0] jb_imm12   (input [31:0] i); jb_imm12    = i[11:0];  endfunction // bit_ext(i,20,12)  -- i[11:0] の配線だけ (ゲート0): 比較分岐の12bit変位 / wires only (no gate): 12-bit compare-branch disp

// 【解説】imm16 は「レジスタ + 変位」の分岐 (REG=1) の変位, imm20 は PC 相対の変位。
//         jb_backward は imm20 の符号ビット (= 後方分岐)。040_d_bra.vh の静的予測で使う。
//         (比較分岐 CMP=1 では imm20 の位置に R1/R2 が重なるが、元の設計の DD_TGT は
//          形式によらず imm20 を足している。imm12 を使う式は元ソースでもコメントの
//          ままで、比較分岐は未完成だったと思われる。040_d_bra.vh 参照)
//
// [Note] imm16 is the displacement of a "register + displacement" branch (REG=1), imm20 that of a PC-relative one.
//        jb_backward is the sign bit of imm20 (= backward branch), used by the static prediction in 040_d_bra.vh.
//        (For a compare branch, CMP=1, R1/R2 overlap the position of imm20, but DD_TGT of the original
//         design adds imm20 whatever the format. The expression using imm12 is only a comment
//         in the original source too, so compare branches seem to have been unfinished. See 040_d_bra.vh)
function [15:0] jb_imm16   (input [31:0] i); jb_imm16    = i[15:0];  endfunction // bit_ext(i,16,16)  -- i[15:0] の配線だけ (ゲート0): レジスタ相対の16bit変位 / wires only (no gate): 16-bit register-relative disp
function [19:0] jb_imm20   (input [31:0] i); jb_imm20    = i[19:0];  endfunction // bit_ext(i,12,20)  -- i[19:0] の配線だけ (ゲート0): PC相対の20bit変位 / wires only (no gate): 20-bit PC-relative disp
function        jb_backward(input [31:0] i); jb_backward = i[19];    endfunction // bit_ext(i,12,1)  -- i[19] の配線だけ (ゲート0): 変位の符号=後方分岐 / wires only (no gate): sign of disp = backward

/*  Priviledged operations

#    4      4    4    4    4    12
# +------+----+----+----+----+----------+
# | 1100 |0001|    |    |    |          |  RFE
# | 1100 |0010| RD |    | R2 |          |  RSR : SR(R2) -> GR(RD)
# | 1100 |0011| RD |    | R2 |          |  WSR : GR(R2) -> SR(RD)
# +------+----+----+----+----+----------+
*/
// 【解説】特権命令の種類は 2 番目の 4bit の下位 2bit (1=RFE, 2=RSR, 3=WSR)。
//         RD は ex_rd, R2 は ex_rs2 と同じ位置なので、特権命令の番号は EX 形式の
//         フィールド (I0_EX_RD / I0_EX_RS2) で読む (030_d_sec.vh, 150_d_act.vh)。
// [Note] The kind of privileged instruction is the low 2 bits of the second 4-bit group (1=RFE, 2=RSR, 3=WSR).
//        RD is at the same place as ex_rd and R2 as ex_rs2, so the numbers of privileged instructions
//        are read with the EX-format fields (I0_EX_RD / I0_EX_RS2) (030_d_sec.vh, 150_d_act.vh).
function [1:0]  priv_opc   (input [31:0] i); priv_opc    = i[25:24]; endfunction // bit_ext(i,6,2)  -- i[25:24] の配線だけ (ゲート0): 特権命令の種類 / wires only (no gate): privileged kind
