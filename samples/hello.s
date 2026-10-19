# "Hello World" を表示するサンプル (Verilog 版で追加)
#
#   文字列を 1 バイトずつ読み, コンソール (番地 F000_0008) に語でストアする。
#   コンソールはテストベンチにあり, ストアした語の下位 8bit を 1 文字として表示する
#   (verilog/tb/tb_stm.v, verilog/tb/axi4_mem_slave.v)。
#   文字列の終わり (0) まで出したら SUCCESS (0x3F0) で止まる。
#
#   verilog フォルダで:
#     python tools/asm.py ../samples/hello.s 1000 -o work/hello.dat
#     python tools/mem2hex.py work/hello.dat work/hello.hex
#     iverilog -g2001 -I rtl -o work/sim.vvp tb/tb_stm.v rtl/stm_sys.v rtl/stm_cntl.v rtl/stm_exu.v rtl/stm_regfile.v rtl/stm_memory.v
#     vvp work/sim.vvp +HEX=work/hello.hex +PC=300 +CYCLES=1000
#
# GR1 = コンソールの番地, GR2 = 次に出す文字の番地, GR3 = 文字
USING   14,0
USING_I 14,0
EQU 300
main:
SETHI 1,%-1000
O   2,0,%800
LOOP:
L.b 3,2(0)
C   3,%0
BE  DONE
ST  3,1(8)
A   2,2,%1
B   LOOP
# 止まる前に最後のストアが終わるのを待つ。AXI4 版では I/O 領域のロードは先行する
# ストアがすべて書き終わってからバスに出るので, コンソールを 1 回読めばよい
# (読んだ値は使わない)。これが無いと, 最後の文字がバスに出る前に止まることがある
DONE:
L   4,1(8)
B   SUCCESS
#
EQU 3D0
DEAD:
DD000000
EQU 3F0
SUCCESS:
DF000000
#
# 文字列 "Hello World\n" (ビッグエンディアン, 0 で終わる)
EQU 800
MSG:
48656C6C
6F20576F
726C640A
00000000
