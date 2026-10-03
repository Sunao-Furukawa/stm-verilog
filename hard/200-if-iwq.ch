# if-iwq
# Next State of Insn Word Queue

# IWQ :

  IWQ-A-0   := SFTUP-A ?  IWQ-A-2   : IWQ-A-0
  IWQ-A-1   := SFTUP-A ?  IWQ-A-3   : IWQ-A-1
  IWQ-A-2   := SFTUP-A ?  IWQ-A-4   : IWQ-A-2
  IWQ-A-3   := SFTUP-A ?  IWQ-A-5   : IWQ-A-3
  IWQ-A-V01 := SFTUP-A ?  IWQ-A-V23   : IWQ-A-V01
  IWQ-A-V23 := SFTUP-A ?  IWQ-A-V45   : IWQ-A-V23

  IWQ-B-0   := SFTUP-B ?  IWQ-B-2   : IWQ-B-0
  IWQ-B-1   := SFTUP-B ?  IWQ-B-3   : IWQ-B-1
  IWQ-B-2   := SFTUP-B ?  IWQ-B-4   : IWQ-B-2
  IWQ-B-3   := SFTUP-B ?  IWQ-B-5   : IWQ-B-3
  IWQ-B-V01 := SFTUP-B ?  IWQ-B-V23   : IWQ-B-V01
  IWQ-B-V23 := SFTUP-B ?  IWQ-B-V45   : IWQ-B-V23

IWQ-A-4  := SFTUP-A | !IWQ-A-V45 ? I-LBS-H : IWQ-A-4
IWQ-A-5  := SFTUP-A | !IWQ-A-V45 ? I-LBS-L : IWQ-A-5
 
IWQ-B-4  := SFTUP-B | !IWQ-B-V45 ? I-LBS-H : IWQ-B-4
IWQ-B-5  := SFTUP-B | !IWQ-B-V45 ? I-LBS-L : IWQ-B-5
 

IWQ-A-V45  := IWQ-A-V45 & !SFTUP-A | SU-IF-CLH-NOCAN & !IB-ID
IWQ-B-V45  := IWQ-B-V45 & !SFTUP-B | SU-IF-CLH-NOCAN &  IB-ID

