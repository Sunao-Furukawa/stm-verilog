# b-dat

#
# Bypass register if B-reg-num matches W-reg-num. (Execute-Execute Bypass)
#
# This is done even if the current E-cyc will overwrite the data that is
# just bypassed.  In such cases, the new correct data in WDTi is used
# instead of OPi-DT.  No problem.
#

#if 0
E-LS-OPS-DT := 
	   E-INTLK & (E-LS-OPS-IS-GR & W-WE1 & (E-LS-RADS == W-WAD1)) 
	| !E-INTLK & (B-LS-OPS-IS-GR & W-WE1 & (B-LS-RADS == W-WAD1)) ? W-WDT1 :
	   E-INTLK & (E-LS-OPS-IS-GR & W-WE2 & (E-LS-RADS == W-WAD2)) 
	| !E-INTLK & (B-LS-OPS-IS-GR & W-WE2 & (B-LS-RADS == W-WAD2)) ? W-WDT2 :
	  !E-INTLK                                         ? GR-DT-S :
  		 					     E-LS-OPS-DT
#else
E-LS-OPS-DT := 
	!E-INTLK & (B-LS-OPS-IS-GR & B-WE2 & (B-LS-RADS == B-WAD2)) 
		&  B-FIRST-IS-EX ? B-EX-RES :
	!E-INTLK & (B-LS-OPS-IS-GR & E-WE1 & (B-LS-RADS == E-WAD1)) ? 
								EE-ALU-OUTPUT :
	!E-INTLK & (B-LS-OPS-IS-GR & E-WE2 & (B-LS-RADS == E-WAD2)) ? E-EX-RES :
	!E-INTLK & (B-LS-OPS-IS-GR & W-WE1 & (B-LS-RADS == W-WAD1)) ? W-WDT1 :
	!E-INTLK & (B-LS-OPS-IS-GR & W-WE2 & (B-LS-RADS == W-WAD2)) ? W-WDT2 :
	!E-INTLK                                         ? GR-DT-S :
  		 					     E-LS-OPS-DT
#endif

# E-OPCLH-LCH should     be updated when LMD-INTLK,
#             should not be updated when STB-INTLK

#
# LD-DT : set DT, maybe SLB
#
# No need to bypass from B-LBS-DT ;  No concurrent LD and ST

E-OPCLH-LCH  := !E-STB-INTLK ? B-OPCLH 		: E-OPCLH-LCH
E-LS-INTCODE := !E-STB-INTLK ? OP-B-INTCODE 	: E-LS-INTCODE
#if 0
E-LS-LD-DT   := !E-STB-INTLK & (B-LS-LD-V & STB-V & (B-LS-LOG-AD == STB-AD)) ?
                	  STB-DT : 
		!E-STB-INTLK ? OP-LBS-DATA 	: E-LS-LD-DT
#else
BB-MEM-DATA   = 
	(B-LS-LD-V & E-LS-ST-V & (B-LS-LOG-AD == E-LS-LOG-AD)) ? EE-ALU-OUTPUT :
	(B-LS-LD-V & STB-V & (B-LS-LOG-AD == STB-AD)) ? STB-DT : 
	 OP-LBS-DATA
E-LS-LD-DT   := !E-STB-INTLK ? BB-MEM-DATA 	: E-LS-LD-DT
#endif

