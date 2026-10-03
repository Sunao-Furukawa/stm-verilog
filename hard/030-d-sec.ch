# d-sec : issue second insn
#
# case FIRST-IS-LS & SECOND-IS-EX)
# 	  ! CC,RD,R1,R2 conflict
#
# case FIRST-IS-LS & SECOND-IS-JB)
#         ! REG-rel(EAG collide) 
#	& ! RD conflict(when LINK)
#	& ! R1,R2 conflict(when cmp)
#
# case FIRST-IS-EX & SECOND-IS-LS)
# 	  ! CC,RB conflict
#
# case FIRST-IS-EX & SECOND-IS-JB)
#         ! LINK (LINK uses EX-pipe)
#	& ! RB conflict(when REG)
#	& ! R1,R2 conflict(when cmp)

# First, check that I0 is legal
I0-V-NOINT	= I0-V & I0-IS-LEGAL
DD-INTCODE	= (I0-IS-LEGAL ? 0 : INTCODE-OP)

DD-ISSUE-SECOND-INSN = 	
       I1-V 
    & !(DD-FIRST-SETCC & DD-SECOND-SETCC)		# CC dependency
    & !(DD-FIRST-WAD-V &((DD-SECOND-WAD-V  & (DD-FIRST-WAD == DD-SECOND-WAD ))
	                |(DD-SECOND-RADB-V & (DD-FIRST-WAD == DD-SECOND-RADB1))
	                |(DD-SECOND-RAD1-V & (DD-FIRST-WAD == DD-SECOND-RADB1))
	                |(DD-SECOND-RAD2-V & (DD-FIRST-WAD == DD-SECOND-RAD2)) )
       )						# REG dependency
    & !(DD-FIRST-IS-LS & DD-SECOND-IS-JB & I1-JB-REG)	# EAG conflict
    & !(DD-FIRST-IS-EX & DD-SECOND-IS-JB & I1-JB-LINK)	# EX/LINK conflict
    & !(DD-SECOND-IS-JB & I1-JB-COND & G-BC-PENDING)	# BC 2nd 
    & ! DD-FIRST-IS-JB 					# First branches
    & !(DD-FIRST-IS-LS & DD-SECOND-IS-LS)		# pipe conflict  
    & !(DD-FIRST-IS-EX & DD-SECOND-IS-EX)		# pipe conflict  
    & (DD-PRIVCODE == 0)				# privileged op
    & !DD-SECOND-PRIV-V 				# privileged op
    & I0-IS-LEGAL					# not intrrupting
    & I1-IS-LEGAL					# not intrrupting


# Register file address port -- may be critical!

DD-RADB = (DD-FIRST-RADB-V ? I0-LS-RB : I1-LS-RB)
DD-RAD1 = (DD-FIRST-RAD1-V ? I0-EX-RB1 : I1-EX-RB1)
DD-RAD2 = ((DD-FIRST-RAD2-V | (DD-PRIVCODE != 0)) ? I0-EX-RS2 : I1-EX-RS2)

# IXX   : XX-insn (XX = LS,EX,JB)
# IXX-V : XX-insn is being issued

ILS-V	= I0-V-NOINT & DD-FIRST-IS-LS | DD-ISSUE-SECOND-INSN & DD-SECOND-IS-LS
ILS     = ( I0-V-NOINT & DD-FIRST-IS-LS ? I0 :
		     (DD-ISSUE-SECOND-INSN & DD-SECOND-IS-LS ? I1 : 0) )
IEX-V	= I0-V-NOINT & DD-FIRST-IS-EX | DD-ISSUE-SECOND-INSN & DD-SECOND-IS-EX
IEX    	= ( I0-V-NOINT & DD-FIRST-IS-EX ? I0 :
		     (DD-ISSUE-SECOND-INSN & DD-SECOND-IS-EX ? I1 : 0) )
IJB-V	= I0-V-NOINT & DD-FIRST-IS-JB | DD-ISSUE-SECOND-INSN & DD-SECOND-IS-JB
IJB    	= ( I0-V-NOINT & DD-FIRST-IS-JB ? I0 :
		     (DD-ISSUE-SECOND-INSN & DD-SECOND-IS-JB ? I1 : 0) )

