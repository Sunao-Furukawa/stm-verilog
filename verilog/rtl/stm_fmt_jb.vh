// =====================================================================
//  stm_fmt_jb.vh  <-  hard/fmt-jb.h
//  JB (ジャンプ/分岐) 形式と特権命令形式のフィールド抽出関数
//
//  ビット番号: 図は CHDL 流 (MSB=0)。Verilog では [31:0] (MSB=31) に変換済み。
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
function [3:0]  jb_opc_h   (input [31:0] i); jb_opc_h    = i[31:28]; endfunction // bit_ext(i,0,4)
function        jb_cond    (input [31:0] i); jb_cond     = i[27];    endfunction // bit_ext(i,4,1)
function        jb_reg     (input [31:0] i); jb_reg      = i[26];    endfunction // bit_ext(i,5,1)
function        jb_link    (input [31:0] i); jb_link     = i[25];    endfunction // bit_ext(i,6,1)
function        jb_cmp     (input [31:0] i); jb_cmp      = i[24];    endfunction // bit_ext(i,7,1)
function [3:0]  jb_rd_mask (input [31:0] i); jb_rd_mask  = i[23:20]; endfunction // bit_ext(i,8,4)
function [3:0]  jb_rb1     (input [31:0] i); jb_rb1      = i[19:16]; endfunction // bit_ext(i,12,4)
function [3:0]  jb_r2_imm4 (input [31:0] i); jb_r2_imm4  = i[15:12]; endfunction // bit_ext(i,16,4)
function [11:0] jb_imm12   (input [31:0] i); jb_imm12    = i[11:0];  endfunction // bit_ext(i,20,12)

function [15:0] jb_imm16   (input [31:0] i); jb_imm16    = i[15:0];  endfunction // bit_ext(i,16,16)
function [19:0] jb_imm20   (input [31:0] i); jb_imm20    = i[19:0];  endfunction // bit_ext(i,12,20)
function        jb_backward(input [31:0] i); jb_backward = i[19];    endfunction // bit_ext(i,12,1)

/*  Priviledged operations

#    4      4    4    4    4    12
# +------+----+----+----+----+----------+
# | 1100 |0001|    |    |    |          |  RFE
# | 1100 |0010| RD |    | R2 |          |  RSR : SR(R2) -> GR(RD)
# | 1100 |0011| RD |    | R2 |          |  WSR : GR(R2) -> SR(RD)
# +------+----+----+----+----+----------+
*/
function [1:0]  priv_opc   (input [31:0] i); priv_opc    = i[25:24]; endfunction // bit_ext(i,6,2)
