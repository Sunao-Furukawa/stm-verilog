#!/bin/sh
# AXI4 マスタ版 (stm_axi_top) で bup0/bup1 の全テストと, AXI4 版用のテスト
# (tests/*.s: I/O 領域, バスエラー例外) とベンチマーク (bench/*.s), RTOS (rtos/rtos.s) を
# Icarus Verilog で実行する。
# メモリは AXI4 スレーブモデル (tb/axi4_mem_slave.v)。各テストを 5 通りで動かす:
#   (axi)       ウェイト無しのスレーブ                     (命令キャッシュ 4KB)
#   (axi r)     乱数でウェイト・応答順の入れ替え           (SEED=1)
#   (axi r bs)  同上 + BYTE_SWAP=1 (バイトレーン入れ替え)  (SEED=2)
#   (axi r tc)  同上, 命令キャッシュ 16 バイト x 2 ライン   (SEED=3, 入れ替えが多い)
#   (axi r nc)  同上, 命令キャッシュ無し                   (SEED=4)
#   使い方:  sh run_bup_axi.sh            (verilog ディレクトリで実行)
# 必要なもの: python3, iverilog/vvp
set -e
cd "$(dirname "$0")"
mkdir -p work
SRC="tb/tb_stm_axi.v tb/axi4_mem_slave.v rtl/stm_axi_top.v rtl/stm_icache.v
     rtl/stm_axi_master.v rtl/stm_cntl.v rtl/stm_exu.v rtl/stm_regfile.v"
iverilog -g2001 -Wall -I rtl -o work/axi.vvp $SRC
iverilog -g2001 -Wall -I rtl -P tb_stm_axi.BYTE_SWAP=1 -o work/axi_bs.vvp $SRC
iverilog -g2001 -Wall -I rtl -P tb_stm_axi.IC_LINE_W=4 -P tb_stm_axi.IC_SET_W=1   -o work/axi_tc.vvp $SRC
iverilog -g2001 -Wall -I rtl -P tb_stm_axi.ICACHE=0 -o work/axi_nc.vvp $SRC

PY=python3; command -v $PY >/dev/null 2>&1 || PY=python
ok=0; ng=0
for x in ../bup0/* ../bup1/* tests/*.s bench/*.s rtos/rtos.s; do
    name=$(basename "$x")
    [ "$name" = head ] && continue
    # ベンチマークと RTOS は長いので最大サイクル数を増やす
    case "$x" in bench/*) n=2000 ;; rtos/*) n=20000 ;; *) n=250 ;; esac
    $PY tools/asm.py "$x" $n -o work/mem.dat
    set -- $($PY tools/mem2hex.py work/mem.dat work/mem.hex)
    pc=${1#PC=}; cyc=${2#CYCLES=}
    # バスの往復が入るので、サイクル数は 20 倍まで許す
    c=$((cyc*20))
    for mode in "axi" "axi r" "axi r bs" "axi r tc" "axi r nc"; do
      case "$mode" in
        "axi")      r=$(vvp -n work/axi.vvp    +HEX=work/mem.hex +PC=$pc +CYCLES=$c | grep RESULT) ;;
        "axi r")    r=$(vvp -n work/axi.vvp    +HEX=work/mem.hex +PC=$pc +CYCLES=$c +RANDOM +SEED=1 | grep RESULT) ;;
        "axi r bs") r=$(vvp -n work/axi_bs.vvp +HEX=work/mem.hex +PC=$pc +CYCLES=$c +RANDOM +SEED=2 | grep RESULT) ;;
        "axi r tc") r=$(vvp -n work/axi_tc.vvp +HEX=work/mem.hex +PC=$pc +CYCLES=$c +RANDOM +SEED=3 | grep RESULT) ;;
        "axi r nc") r=$(vvp -n work/axi_nc.vvp +HEX=work/mem.hex +PC=$pc +CYCLES=$c +RANDOM +SEED=4 | grep RESULT) ;;
      esac
      tag="${x#../} ($mode)"
      case "$r" in
        *"-> OK"*) ok=$((ok+1)); printf '%-34s ok   %s\n' "$tag" "${r#RESULT: }" ;;
        *)         ng=$((ng+1)); printf '%-34s ERR  %s\n' "$tag" "${r#RESULT: }" ;;
      esac
    done
done
echo "ok=$ok  err=$ng"
