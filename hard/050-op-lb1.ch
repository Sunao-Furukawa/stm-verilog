# op-lb1 : OP-LBS in S-Unit :  generate output for other units
# Unit Interface Signals :
# in CANCEL-BY-BC 	<- ? , in CANCEL-BY-INT 	<- ?
# out SU-OP-RDY,SU-ST-RDY  -> g-srq ; B-OPCLH,OP-LBS-DATA<0:31>  -> b-dat
# out OP-B-INTCODE	-> ?

# For cache miss simulation
#ifndef VHDL
RANDOM-FOR-OPCLH = random_clh ? ((random()&0xf)>=8) : 1
#endif

# This is actually in IU, but appears here becaused it's referenced here..

WW-WSR		= (W-PRIVCODE == PRIVCODE-WSR)
WW-RFE		= (W-PRIVCODE == PRIVCODE-RFE)
WW-LS-INT-V	= (W-LS-INTCODE != 0)
WW-EX-INT-V	= (W-EX-INTCODE != 0)
#ifndef VHDL
WW-STATECHANGE  = WW-WSR & ((W-WAD2 & 12) == 0)
#else
WW-STATECHANGE  = WW-WSR & (W-WAD2[0] | W-WAD2[1])
#endif
WW-INTERRUPTION = WW-LS-INT-V | WW-EX-INT-V
CANCEL-BY-INT	= WW-INTERRUPTION | WW-RFE | WW-STATECHANGE

# Means that branch prediction failed.
# All insns with SUBJECT-TO-BC shall be cancelled by this.

CANCEL-BY-BC  =  G-BC-JUST-SOLVED & (G-BC-JUST-TAKEN ^ G-BC-TKN-PREDICTED)

# Cancel and Valid-after-cancel

OP-B-CANCELLED	= (OP-B-OPC != SU-OPC-ST2) & CANCEL-BY-INT
		 | OP-B-SUBJECT-TO-BC & CANCEL-BY-BC
OP-WAIT-CANCELLED	= (OP-WAIT-OPC != SU-OPC-ST2) & CANCEL-BY-INT
		 | OP-WAIT-SUBJECT-TO-BC & CANCEL-BY-BC

OP-B-V-NOCAN	= OP-B-V & !OP-B-CANCELLED
OP-WAIT-V-NOCAN	= OP-WAIT-V & !OP-WAIT-CANCELLED

## Lvl-1. No TLB miss exception yet. Only address-compare exception (which
## in fact should belong to IU)

OP-B-INTCODE	= (OP-B-V & ((OP-B-OPC == SU-OPC-LD)|(OP-B-OPC == SU-OPC-ST))
			  & (LBS-AD == CMPR))
		  ? INTCODE-CMP : 0

# From the cycle ST passes B-cyc to the cyc its ST2 passes, access to the
# same address will never  miss-hit, because cache line is held during that
# time. 

B-OPCLH = OP-B-V & ((OP-B-OPC==SU-OPC-LD)|(OP-B-OPC==SU-OPC-ST)) 
	   & ( RANDOM-FOR-OPCLH | (STB-V & (LBS-AD == STB-AD))
	      | (E-LS-ST-V & E-OPCLH-LCH & (LBS-AD == E-LS-LOG-AD))  
	      | (OP-B-INTCODE != 0)  )
SU-OP-RDY = !OP-WAIT-V
SU-ST-RDY = !OP-WAIT-V

# LD-DT : set DT, maybe SLB
#
# No need to bypass from B-LBS-DT ;  No concurrent LD and ST

## Lvl-1. Do DAT later!!

OP-LBS-DATA =  (B-OPCLH ? MEM-DT-OP : 0xdead0a0a)

