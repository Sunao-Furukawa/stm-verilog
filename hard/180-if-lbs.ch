# if-lbs

# For cache miss simulation

#ifndef VHDL
RANDOM-FOR-IFRDY = random_clh ? ((random() & 0xf) >= 8) : 1
RANDOM-FOR-IFCLH = random_clh ? ((random() & 0xf) >= 8) : 1
#endif

SU-IF-CLH	= IB-V     & RANDOM-FOR-IFCLH
SU-IF-RDY	= IF-REQ-V & RANDOM-FOR-IFRDY & (!IB-V | SU-IF-CLH) 
		 | START-TRIGGER

  I-LBS-H	= SU-IF-CLH ? MEM-DT-IF-H : 0xf0f0f0f0
  I-LBS-L	= SU-IF-CLH ? MEM-DT-IF-L : 0xff0f0f0f

