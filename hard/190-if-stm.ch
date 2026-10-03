# if-stm
# Next State of Insn Fetch State Machine

# IB-AD,ID,V     -- After IF-REQ is issued, set them.  Otherwise,
#                        AD,ID -> stay      V -> 0 .  (For lvl-0)

IB-V 	:= IF-REQ-V & SU-IF-RDY ? 1 :   SU-IF-CLH | CANCEL-IB ? 0 : IB-V
IB-AD  	:= IF-REQ-V & SU-IF-RDY ? IF-REQ-AD : IB-AD
IB-ID	:= IF-REQ-V & SU-IF-RDY ? IF-REQ-ID : IB-ID

# CUR-ID         -- Change if (BC-issue & predict TKN) | (just after BC-cancel)
# 
CUR-IWQ-ID := (EID ^ (DD-PREDICTING-TAKEN & D-FWD)) & !WW-INTERRUPTION

# NIP :
SU-IF-CLH-NOCAN	= SU-IF-CLH & !CANCEL-IB & !IWQ-FULL
EMIT = !D-FWD ? 0 : DD-ISSUE-SECOND-INSN ? 2 : 1 

# if '+' is allowed, I would write as follows :
#SFTUP-A   = IWQ-A-V45 & (NIP-A + (!EID ? EMIT : 0) >= 2)
#SFTUP-B   = IWQ-B-V45 & (NIP-B + ( EID ? EMIT : 0) >= 2)

EMIT-FOR-A	 = (!EID ? EMIT : 0)
NIP-AFTER-EMIT-A = add_3_2(NIP-A,EMIT-FOR-A)

EMIT-FOR-B	 = ( EID ? EMIT : 0)
NIP-AFTER-EMIT-B = add_3_2(NIP-B,EMIT-FOR-B)
#ifndef VHDL
SFTUP-A   = IWQ-A-V45 & ((NIP-AFTER-EMIT-A & 6) != 0)
SFTUP-B   = IWQ-B-V45 & ((NIP-AFTER-EMIT-B & 6) != 0)
#else
SFTUP-A   = IWQ-A-V45 & (NIP-AFTER-EMIT-A[0] | NIP-AFTER-EMIT-A[1])
SFTUP-B   = IWQ-B-V45 & (NIP-AFTER-EMIT-B[0] | NIP-AFTER-EMIT-B[1])
#endif

DD-JB-TKN = IJB-V & !DD-ISSUEING-UNSOLVED-BC & !DD-ISSUEING-UNTAKEN-BC

CLEAR-NIP-A = IJB-V & D-FWD & (EID&DD-ISSUEING-UNSOLVED-BC | !EID & DD-JB-TKN) 
	      | !EID & A-JB-V & A-SET-EAG-TO-TGT | START-TRIGGER | CANCEL-BY-INT
CLEAR-NIP-B = IJB-V & D-FWD & (!EID&DD-ISSUEING-UNSOLVED-BC | EID & DD-JB-TKN) 
	      |  EID & A-JB-V & A-SET-EAG-TO-TGT | START-TRIGGER | CANCEL-BY-INT

# if '+' is allowed, I would write as follows :
#NIP-A := ( CLEAR-NIP-A  ? 6+((IF-REQ-AD&4)>>2) :
#         ( (NIP-A >= 6) ? NIP-A + MINUS2 * (SU-IF-CLH-NOCAN & ! IB-ID) : 
#		NIP-A + (!EID ? EMIT : 0) + MINUS2 * SFTUP-A   ))
#NIP-B := ( CLEAR-NIP-B  ? 6+((IF-REQ-AD&4)>>2) :
#         ( (NIP-B >= 6) ? NIP-B + MINUS2 * (SU-IF-CLH-NOCAN &   IB-ID) : 
#		NIP-B + ( EID ? EMIT : 0) + MINUS2 * SFTUP-B   ))

#ifndef VHDL
NIP-A-TMP = CLEAR-NIP-A       ? 6 | ((IF-REQ-AD & 4) ? 1 : 0)                 :
         ((NIP-A & 6) == 6) ? NIP-A & ((SU-IF-CLH-NOCAN & ! IB-ID) ? 5 : 7) : 
	 SFTUP-A ? ( ((NIP-AFTER-EMIT-A & 2)!=0) ? (NIP-AFTER-EMIT-A & 5) :
	  					   2 | (NIP-AFTER-EMIT-A & 1) ):
	 NIP-AFTER-EMIT-A

NIP-B := CLEAR-NIP-B        ? 6 | ((IF-REQ-AD & 4) ? 1 : 0)                 :
         ((NIP-B & 6) == 6) ? NIP-B & ((SU-IF-CLH-NOCAN &   IB-ID) ? 5 : 7) : 
	 SFTUP-B ? ( ((NIP-AFTER-EMIT-B & 2)!=0) ? (NIP-AFTER-EMIT-B & 5) :
	  					   2 | (NIP-AFTER-EMIT-B & 1) ):
	 NIP-AFTER-EMIT-B
#else
NIP-A-TMP = CLEAR-NIP-A        ? B"11" . IF-REQ-AD[29] :
         (NIP-A[0]&NIP-A[1]) ? B"1" . !(SU-IF-CLH-NOCAN & ! IB-ID) . NIP-A[2] : 
	 SFTUP-A ? B"0" . NIP-AFTER-EMIT-A[0] . NIP-AFTER-EMIT-A[2] :
	 NIP-AFTER-EMIT-A
NIP-B := CLEAR-NIP-B        ? B"11" . IF-REQ-AD[29] :
         (NIP-B[0]&NIP-B[1]) ? B"1" . !(SU-IF-CLH-NOCAN &   IB-ID) . NIP-B[2] : 
	 SFTUP-B ? B"0" . NIP-AFTER-EMIT-B[0] . NIP-AFTER-EMIT-B[2] :
	 NIP-AFTER-EMIT-B
#endif

NIP-A-REG := NIP-A-TMP ^ 6

D-IF-AD-A := CLEAR-NIP-A 	       ? IF-REQ-AD : 
	     SU-IF-CLH-NOCAN & ! IB-ID ? IB-AD     : D-IF-AD-A 
D-IF-AD-B := CLEAR-NIP-B 	       ? IF-REQ-AD : 
	     SU-IF-CLH-NOCAN &   IB-ID ? IB-AD     : D-IF-AD-B 

