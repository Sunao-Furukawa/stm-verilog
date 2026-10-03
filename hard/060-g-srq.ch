# g-srq : codes related to interlocks and releases
#

E-V-NOCAN 	= E-V & (!CANCEL-BY-BC | !E-JB-SUBJECT-TO-BC) & !CANCEL-BY-INT
B-V-NOCAN 	= B-V & (!CANCEL-BY-BC | !B-JB-SUBJECT-TO-BC) & !CANCEL-BY-INT
A-V-NOCAN 	= A-V & (!CANCEL-BY-BC | !A-JB-SUBJECT-TO-BC) & !CANCEL-BY-INT
                                 				# W: no intlk
# EAB : A-cyc is trying to use regs that are not yet ready, i.e. 
#       reg data made by B-LS or E-LS(with EXU).

A-EAB   	= 
     E-V & E-WE1 & ((E-LS-OPCODE != 0) | E-LS-LD-V & !E-OPCLH-LCH) & (
    	  (E-WAD1 == A-LS-RADB) & (A-WE1 | A-LS-SETCC) 
	| (E-WAD1 == A-EX-RAD1) & (A-WE2 | A-EX-SETCC)
	| (E-WAD1 == A-EX-RAD2) & (A-WE2 | A-EX-SETCC) & A-EX-OP2-IS-GR
      )
  |  B-V & B-WE1 & (
    	  (B-WAD1 == A-LS-RADB) & (A-WE1 | A-LS-SETCC)
	| (B-WAD1 == A-EX-RAD1) & (A-WE2 | A-EX-SETCC)
	| (B-WAD1 == A-EX-RAD2) & (A-WE2 | A-EX-SETCC) & A-EX-OP2-IS-GR
      )

# SU priority signals
#
# IU-SU interface has a LD-REQ(w/AD<0:31>) and a ST-REQ(w/AD<0:31> and
# DT<0:31>) buses.  Two requests can be simultaneously issued, although 
# only one can be accepted.
#
# IU suppresses LD-REQ under the following  condition, giving 
# higher priority to ST-REQ : 
#
#	1) B-V-NOCAN       & E-V-NOCAN & E-LS-ST-V & STB-V
#	     --- LD-REQ can't pass anyway due to INTLK.
#
# When SU can accept both LD and ST, it turns on SU-OP-RDY and SU-ST-RDY.
# giving LD a higher priority.  When SU can accept only ST, SU sets
# SU-OP-RDY=0 and SU-ST-RDY=1.  Never SU-OP-RDY=1 and SU-ST-RDY=0.

################## THIS IS FAKE!!! LEVEL-0 ONLY.  ####################
AA-LD-REQ-VAL	= A-V-NOCAN & !A-EAB & (A-LS-LD-V | A-LS-ST-V)
	 & !( STB-V & E-V-NOCAN & E-LS-ST-V & B-V-NOCAN )

WW-ST-REQ-VAL	= STB-V

AA-LD-GO	= SU-OP-RDY & AA-LD-REQ-VAL 
WW-ST-GO	= SU-ST-RDY & WW-ST-REQ-VAL & !AA-LD-GO

