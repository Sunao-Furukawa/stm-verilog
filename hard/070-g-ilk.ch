# g-ilk : interlock conditions

# E-STB-INTLK and B-LMD-INTLK can never simultaneously occur.  When
# STB-V & E-V-NOCAN & E-LS-ST-V B-V-NOCAN & B-LS-V , 
# i.e. (1)ST, (2)ST, (3)L/ST have passed SU consecutively and (1) is at W,
# (2) at E, (3) at B, SU must give (1)ST the highest priority -- higher 
# than MI or MO --.  Otherwise (3) cannot issue OP-CLH and SU gets deadlock.

E-STB-INTLK	= E-LS-ST-V & E-OPCLH-LCH & STB-V & !WW-ST-GO 
E-LMD-INTLK	= (E-LS-LD-V | E-LS-ST-V) & !E-OPCLH-LCH
A-SBS-INTLK	= (A-LS-LD-V | A-LS-ST-V) & !AA-LD-GO

# D-V-NOCAN	= !( (NIP == 6) | (NIP >= 4) & !V45  )
D-V-NOCAN	= I0-V & !CANCEL-BY-INT
D-BC-2ND-INTLK	= DD-FIRST-IS-JB & DD-ISSUEING-UNSOLVED-BC
			 & G-BC-PENDING
D-PIPECLR-INTLK	= (DD-PRIVCODE == PRIVCODE-RSR) &
   ( (A-PRIVCODE != 0)|(B-PRIVCODE != 0)|(E-PRIVCODE != 0)|(W-PRIVCODE != 0) | 
			  (A-V | B-V | E-V) & (DD-RAD2 == 0) )

E-INTLK 	= E-V-NOCAN & (E-STB-INTLK | E-LMD-INTLK) 	# E: STBFUL,LMD
B-INTLK 	= B-V-NOCAN &  E-INTLK                  	# B: no intlk
A-INTLK 	= A-V-NOCAN & (A-SBS-INTLK | A-EAB | B-INTLK )	# A:EAB,SUBUSY
D-INTLK		= D-V-NOCAN & (D-BC-2ND-INTLK | D-PIPECLR-INTLK) # D:BC2ND,PCLR

E-FWD   	= E-V-NOCAN & ! E-STB-INTLK & ! E-LMD-INTLK
B-FWD   	= B-V-NOCAN & ! E-INTLK
A-FWD   	= A-V-NOCAN & !(A-SBS-INTLK | A-EAB | B-INTLK)
D-FWD		= D-V-NOCAN & ! D-INTLK & !A-INTLK

##################################################################
## These are solely for simulation convenience (serve as probe) ##
##################################################################

#ifndef VHDL
E-STAT = (E-FWD << 3) | E-V
B-STAT = (B-FWD << 3) | B-V
A-STAT = (A-FWD << 3) | A-V
D-STAT = (D-FWD << 3) | D-V-NOCAN
#endif

