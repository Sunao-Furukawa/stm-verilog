# d-pre : Insn Presentation 
# Selecting insn from IWQs

#                                                                     #
#    IWQ-A0 B0  A1 B1         A5 B5                                   #
#         | |    | |           | |                                    #
#        -----  -----  ...    -----  <-- EID                          #
#          |      |             |                                     #
#         C0     C1            C5  (IWQ)                              #
#                                                                     #
#       C0 C1    C5      C1    C5                                     #
#        |  | ..  |       | ..  |                                     #
#       ------------     ---------   <-- NIPA/B                       #
#             |              |                                        #
#           INSN0          INSN1                                      #
#                                                                     #

# 'Effective' ID, which should be presented
# Dont forget to CUR-ID := EID even if !DRel.

EID = CUR-IWQ-ID ^ (G-BC-JUST-SOLVED & (G-BC-JUST-TAKEN ^ G-BC-TKN-PREDICTED) )

IWQ-0  = (EID ? IWQ-B-0 : IWQ-A-0)
IWQ-1  = (EID ? IWQ-B-1 : IWQ-A-1)
IWQ-2  = (EID ? IWQ-B-2 : IWQ-A-2)
IWQ-3  = (EID ? IWQ-B-3 : IWQ-A-3)
IWQ-4  = (EID ? IWQ-B-4 : IWQ-A-4)
IWQ-5  = (EID ? IWQ-B-5 : IWQ-A-5)

NIP-A	= NIP-A-REG ^ 6
NIP	= (EID ? NIP-B     : NIP-A)
NIP-0	= (NIP == 0)
NIP-1	= (NIP == 1)
NIP-2	= (NIP == 2)
NIP-3	= (NIP == 3)
NIP-4	= (NIP == 4)
NIP-5	= (NIP == 5)

V01 	= (EID ? IWQ-B-V01 : IWQ-A-V01)
V23 	= (EID ? IWQ-B-V23 : IWQ-A-V23)
V45 	= (EID ? IWQ-B-V45 : IWQ-A-V45)

I0-V = (NIP-0 | NIP-1) ? V01 : (NIP-2 | NIP-3) ? V23 : (NIP-4 | NIP-5) ? V45 : 0
I1-V = (NIP-0        ) ? V01 : (NIP-1 | NIP-2) ? V23 : (NIP-3 | NIP-4) ? V45 : 0

I0-CANDID = NIP-0 ? IWQ-0 : NIP-1 ? IWQ-1 : NIP-2 ? IWQ-2 : 
            NIP-3 ? IWQ-3 : NIP-4 ? IWQ-4 : NIP-5 ? IWQ-5 : 0
I0	  = I0-V ? I0-CANDID : 0

I1-CANDID = NIP-0 ? IWQ-1 : NIP-1 ? IWQ-2 : NIP-2 ? IWQ-3 : 
            NIP-3 ? IWQ-4 : NIP-4 ? IWQ-5 : 0
I1	  = I1-V ? I1-CANDID : 0

##################################################################
## These are solely for simulation convenience (serve as probe) ##
##################################################################
#IWQA-PROBE-H = ((IWQ-A[0] & 0xff000000)>>8)|((IWQ-A[1] & 0xff000000)>>16)
#                                           |((IWQ-A[2] & 0xff000000)>>24)
#IWQA-PROBE-L = ((IWQ-A[3] & 0xff000000)>>8)|((IWQ-A[4] & 0xff000000)>>16)
#                                           |((IWQ-A[5] & 0xff000000)>>24)
#IWQB-PROBE-H = ((IWQ-B[0] & 0xff000000)>>8)|((IWQ-B[1] & 0xff000000)>>16)
#                                           |((IWQ-B[2] & 0xff000000)>>24)
#IWQB-PROBE-L = ((IWQ-B[3] & 0xff000000)>>8)|((IWQ-B[4] & 0xff000000)>>16)
#                                           |((IWQ-B[5] & 0xff000000)>>24)
#
