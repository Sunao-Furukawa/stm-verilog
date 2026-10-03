# d-bra: D-cycle, issueing branch insn

# Address of branch insn
#      NIP -+                                                              #
#           v    IWQ-*                                                     #
#       +---+---+---+---+---+---+      D-IF-AD-*                           #
#       |X-16   |   |   |X  |   |     +------+                             #
#       |X-8|   |X  |   |   |   |     |  X   |                             #
#       +---+---+---+---+---+---+     +------+                             #
#        o       o       o               |                                 #
#                A(!V45) A(V45)          |                                 #
#                +-------+---------------+                                 #

DD-JB-INSN-AD-PART1 = EID ? D-IF-AD-B & 0xfffffff8 : D-IF-AD-A & 0xfffffff8 
#DD-JB-INSN-AD-PART2 = MINUS1*(V45 ? 16 : 8) + 4*NIP + (DD-FIRST-IS-JB ? 0 : 4)
DD-JB-INSN-AD-PART2 = add_4_5_3(V45,NIP,DD-FIRST-IS-JB)

# Kind of JB-insn (BA/JA/BL/JL/BC)

IJB-IS-BA	= IJB-V & !IJB-COND & !IJB-LINK & !IJB-REG
IJB-IS-JA	= IJB-V & !IJB-COND & !IJB-LINK &  IJB-REG
IJB-IS-BL	= IJB-V &   IJB-LINK & !IJB-REG
IJB-IS-JL	= IJB-V &   IJB-LINK &  IJB-REG
IJB-IS-BC	= IJB-V &   IJB-COND
####  IJB-IS-CMP = ...  !!!!!

# If BC, has it been solved?  Which stage decides CC ?
#                                                                  #
#         D   |   A   |   B   |   E   |    W                       #
#             |       |       |       |                            #
#   LS        |  uns  |  uns  |   +   |                            #
#             |       |       |       |  sol                       #
#   EX        |   +   |  sol  |  sol  |                            #

DD-SETCC		= DD-FIRST-SETCC
####			 | IJB-IS-CMP !!!!!
DD-ISSUEING-SOLVED-BC	= !(A-EX-SETCC | A-LS-SETCC | B-LS-SETCC | E-LS-SETCC
			   | DD-FIRST-SETCC & DD-SECOND-IS-JB) & IJB-IS-BC
DD-CC-FOR-SOLVED-BC	= (B-EX-SETCC ? B-EX-CC :
			  (E-EX-SETCC ? E-EX-CC : (W-SETCC ? W-CC : PSW-CC) ) )
DD-SOLVED-BC-TAKEN	= cc-match(DD-CC-FOR-SOLVED-BC,IJB-RD-MASK)
DD-ISSUEING-TAKEN-BRANCH = DD-SOLVED-BC-TAKEN & DD-ISSUEING-SOLVED-BC
               | IJB-IS-BA | IJB-IS-BL 
DD-ISSUEING-UNTAKEN-BC  = !DD-SOLVED-BC-TAKEN & DD-ISSUEING-SOLVED-BC

DD-ISSUEING-UNSOLVED-BC	=  !DD-ISSUEING-SOLVED-BC & IJB-IS-BC

DD-ISSUEING-UNSOLVED-BC-ON-D-EX =  DD-FIRST-SETCC & DD-SECOND-IS-JB 
				  & DD-FIRST-IS-EX & IJB-IS-BC
####				 | IJB-IS-CMP  !!!!!
DD-ISSUEING-UNSOLVED-BC-ON-D-LS =  DD-FIRST-SETCC & DD-SECOND-IS-JB 
				  & DD-FIRST-IS-LS & IJB-IS-BC
DD-ISSUEING-UNSOLVED-BC-ON-A-EX	=  !DD-SETCC & A-EX-SETCC & IJB-IS-BC
DD-ISSUEING-UNSOLVED-BC-ON-A-LS	=  !DD-SETCC & A-LS-SETCC & IJB-IS-BC
DD-ISSUEING-UNSOLVED-BC-ON-B-LS	=  !DD-SETCC & !A-LS-SETCC & !A-EX-SETCC 
					& B-LS-SETCC & IJB-IS-BC
DD-ISSUEING-UNSOLVED-BC-ON-E-LS	=  !DD-SETCC & !A-LS-SETCC & !A-EX-SETCC 
					& !B-LS-SETCC & E-LS-SETCC & IJB-IS-BC
# branch prediction : backward branch <-> TKN predicted
DD-PREDICTING-TAKEN  = DD-ISSUEING-UNSOLVED-BC & IJB-BACKWARD
DD-DISP       = ILS-LS-FMT   ? ILS-DISP16 :
		ILS-EXRM-FMT ? sign-ext-12(ILS-DISP12) : IJB-IMM16 
#ifndef VHDL
DD-TGT = add_32_5_20(DD-JB-INSN-AD-PART1,DD-JB-INSN-AD-PART2,IJB-IMM20)
       ## + (IJB-CMP ? sign-ext(12,IJB-IMM12) : sign-ext(20,jb-imm20(IJB)))
#endif
