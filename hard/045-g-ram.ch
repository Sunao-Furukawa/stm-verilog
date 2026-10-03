#  g-ram : RAM and Register File

#ifndef VHDL

if (W-WE1) { GR[W-WAD1] := W-WDT1 } 
if (W-WE2) { GR[W-WAD2] := W-WDT2 } 

GR-DT-1	= GR[DD-RAD1]
GR-DT-2	= GR[DD-RAD2]
GR-DT-B	= GR[DD-RADB]
GR-DT-S	= GR[B-LS-RADS]


if (LBS-WE)  { Mem[LBS-AD >> 2] := LBS-DT }

MEM-DT-OP   = Mem[LBS-AD >> 2]
MEM-DT-IF-H = Mem[(IB-AD >> 2) & ~1]
MEM-DT-IF-L = Mem[(IB-AD >> 2) |  1]

#endif

