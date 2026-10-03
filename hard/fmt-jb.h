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
# uncond	-+-  .	-+-PC
#   	 |	 +-Reg
# 	 |
# 	 +- LNK	-+-PC
# 		 +-Reg
# 
# cond	-+-  .  -+-PC
#   	 |	 +-Reg
# 	 |
# 	 +- cmp	-+-PC
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
#define jb_opc_h(i) 	bit_ext(i,0,4)
#define jb_cond(i) 	bit_ext(i,4,1)
#define jb_reg(i) 	bit_ext(i,5,1)
#define jb_link(i) 	bit_ext(i,6,1)
#define jb_cmp(i) 	bit_ext(i,7,1)
#define jb_rd_mask(i) 	bit_ext(i,8,4)
#define jb_rb1(i) 	bit_ext(i,12,4)
#define jb_r2_imm4(i) 	bit_ext(i,16,4)
#define jb_imm12(i) 	bit_ext(i,20,12)

#define jb_imm16(i) 	bit_ext(i,16,16)
#define jb_imm20(i) 	bit_ext(i,12,20)
#define jb_backward(i) 	bit_ext(i,12,1)

/*  Priviledged operations 

#    4      4    4    4    4    12
# +------+----+----+----+----+----------+
# | 1100 |0001|    |    |    |          |  RFE
# | 1100 |0010| RD |    | R2 |          |  RSR : SR(R2) -> GR(RD)
# | 1100 |0011| RD |    | R2 |          |  WSR : GR(R2) -> SR(RD)
# +------+----+----+----+----+----------+
*/ 
#define priv_opc(i)     bit_ext(i,6,2)
