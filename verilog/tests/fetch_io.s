# I/O 領域からの命令フェッチのテスト (AXI4 版 stm_axi_top 用, Verilog 版で追加)
#   I/O 領域の命令は (バスに出さずに) 不正命令として扱うので,
#   そこへ飛ぶと不正命令例外 (INTCODE 1) になり, XPC = 飛んだ先の番地。
#
# Header start
#
USING   14,300
USING_I 14,300
EQU 300
main:
X   0,0,0
O   14,0,%300
O   13,0,%500
WSR 2,13		# TBR = 500
B   L1
#
EQU 3D0
DEAD:
DD000000
EQU 3F0
SUCCESS:
DF000000
#
# Header end
##########################################
EQU 400
L1:
SETHI 9,%-1000		# GR9 = F0000000 (%-1000 = F000) (I/O 領域)
J   9(100)		# F0000100 へ飛ぶ → 不正命令例外
B   DEAD
#
EQU 500
# 割り込みルーチン
SETHI 2,%0001		# 期待する PSW : INTCODE = 1 (不正命令)
RSR   4,0		# PSW
C     4,2
BNE   DEAD
RSR   8,5		# XPC
SETHI 5,%-1000
A     5,5,%100
C     8,5
BNE   DEAD
B     SUCCESS
