# ロードのバスエラー例外のテスト (AXI4 版 stm_axi_top 用, Verilog 版で追加)
#   テスト用スレーブは E0000000〜 の読み書きに SLVERR を返す。
#   エラー応答のロードはデータアクセス例外 (INTCODE 3) になり,
#   XPC = ロードの番地, XLA = アクセスした番地, 行き先のレジスタは変わらない。
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
SETHI 11,%-2000		# GR11 = E0000000 (%-2000 = E000) (エラー領域)
O   3,0,%77
L   3,11(10)		# 408: E0000010 を読む → 例外
B   DEAD
#
EQU 500
# 割り込みルーチン
SETHI 2,%0003		# 期待する PSW : INTCODE = 3
RSR   4,0		# PSW
C     4,2
BNE   DEAD
RSR   9,5		# XPC
C     9,%408
BNE   DEAD
RSR   8,6		# XLA
SETHI 5,%-2000
A     5,5,%10
C     8,5
BNE   DEAD
C     3,%77		# GR3 は書き換わっていない
BNE   DEAD
B     SUCCESS
