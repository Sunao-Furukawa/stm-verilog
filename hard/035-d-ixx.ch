# d-ixx : decoding ILS, IEX and IJB


ILS-STORE 	= ls_store(ILS) 
ILS-LENG 	= ls_leng(ILS) 
ILS-RD-RS 	= ls_rd_rs(ILS) 
ILS-RB 		= ls_rb(ILS) 
ILS-DISP16 	= ls_disp16(ILS) 

ILS-OP2MODE 	= ex_op2mode(ILS) 
ILS-SETCC 	= ex_setcc(ILS) 
ILS-EXU-OPC 	= ex_exu_opc(ILS) 
#ILS-RB1 	= ex_rb1(ILS) 
ILS-RS2 	= ex_rs2(ILS) 
ILS-RD 		= ex_rd(ILS) 
ILS-DISP12 	= ex_disp12(ILS) 

IEX-OP2MODE 	= ex_op2mode(IEX) 
IEX-SETCC 	= ex_setcc(IEX) 
IEX-EXU-OPC 	= ex_exu_opc(IEX) 
IEX-RB1 	= ex_rb1(IEX) 
IEX-RS2 	= ex_rs2(IEX) 
IEX-RD 		= ex_rd(IEX) 
IEX-DISP12 	= ex_disp12(IEX) 

IJB-COND 	= jb_cond(IJB) 
IJB-REG 	= jb_reg(IJB) 
IJB-LINK 	= jb_link(IJB) 
IJB-CMP 	= jb_cmp(IJB) 
IJB-RD-MASK 	= jb_rd_mask(IJB) 
IJB-RB1 	= jb_rb1(IJB) 
IJB-R2-IMM4 	= jb_r2_imm4(IJB) 
IJB-IMM12 	= jb_imm12(IJB) 


IEX-IMM16 	= ex_imm16(IEX) 

IJB-IMM16 	= jb_imm16(IJB) 
IJB-IMM20 	= jb_imm20(IJB) 
IJB-BACKWARD 	= jb_backward(IJB) 


ILS-LS-OPC-H	= ls_opc_h(ILS)
ILS-EX-OPC-H	= ex_opc_h(ILS)

ILS-LS-FMT      = (ILS-LS-OPC-H == 4) & ILS-V
ILS-EXRM-FMT    = (ILS-EX-OPC-H == 0) & (ILS-OP2MODE != 0) & ILS-V

