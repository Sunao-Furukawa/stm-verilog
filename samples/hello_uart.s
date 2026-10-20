# "Hello World" を AXI UART Lite に出力するサンプル (Verilog 版で追加)
#
#   verilog/syn/vivado/create_bd.tcl で作るブロックデザイン用。UART Lite は
#   番地 F000_0000 (CPU の I/O 領域) にあり, レジスタは
#     +0 受信 FIFO   +4 送信 FIFO   +8 ステータス (ビット 3 = 送信 FIFO が満杯)   +C 制御
#   送信 FIFO に空きがあるのを確かめてから, 1 文字ずつ語で書く。
#   最後まで出したら, その場で止まる (無限ループ)。
#
#   I/O 領域のロードは投機的に実行されないので, ステータスを読むループで
#   予測ミス側の読み出しがデバイスに届くことはない。
#
#   verilog フォルダで:
#     python tools/asm.py ../samples/hello_uart.s 1000 -o work/hello_uart.dat
#     python tools/mem2hex.py work/hello_uart.dat work/hello_uart.hex
#   できた .hex を create_bd.tcl の 2 番目の引数に渡す。
#
#   テストベンチ (tb_stm.v, tb_stm_axi.v) には UART が無いので, シミュレーションでは
#   何も表示されず, 最後は TIMEOUT になる (HALT で止まり続けるため)。
#
# GR1 = UART の番地, GR2 = 次に出す文字の番地, GR3 = 文字, GR4 = ステータス
USING   14,0
USING_I 14,0
EQU 300
main:
SETHI 1,%-1000
O   2,0,%800
LOOP:
L.b 3,2(0)
C   3,%0
BE  HALT
# 送信 FIFO が満杯 (ステータスのビット 3 が 1) なら待つ
WAIT:
L   4,1(8)
N.c 4,4,%8
BNE WAIT
ST  3,1(4)
A   2,2,%1
B   LOOP
HALT:
B   HALT
#
# 文字列 "Hello World\r\n" (ビッグエンディアン, 0 で終わる)
EQU 800
MSG:
48656C6C
6F20576F
726C640D
0A000000
