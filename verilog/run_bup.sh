#!/bin/sh
# samples/subbup の Verilog 版。bup0/bup1 の全テストを Icarus Verilog で実行する。
#   使い方:  sh run_bup.sh            (verilog ディレクトリで実行)
# 必要なもの: python3, iverilog/vvp   (アセンブラは Python 版 tools/asm.py を使う)
set -e
cd "$(dirname "$0")"
mkdir -p work
iverilog -g2001 -Wall -I rtl -o work/sim.vvp \
  tb/tb_stm.v rtl/stm_sys.v rtl/stm_cntl.v rtl/stm_exu.v rtl/stm_regfile.v rtl/stm_memory.v

PY=python3; command -v $PY >/dev/null 2>&1 || PY=python
ok=0; ng=0
for lv in 0 1; do
  for x in ../bup$lv/*; do
    name=$(basename "$x")
    [ "$name" = head ] && continue
    $PY tools/asm.py "$x" 250 -o work/mem.dat
    set -- $($PY tools/mem2hex.py work/mem.dat work/mem.hex)
    pc=${1#PC=}; cyc=${2#CYCLES=}
    for mode in "" "+RANDOM"; do
      # 乱数モードはキャッシュミスで遅くなるため 250 サイクルでは足りない
      # テストがある (byp-r-rb1 などは 220~275 サイクル) ので 2 倍にする
      c=$cyc; [ -n "$mode" ] && c=$((cyc*2))
      r=$(vvp -n work/sim.vvp +HEX=work/mem.hex +PC=$pc +CYCLES=$c $mode | grep RESULT)
      tag="bup$lv/$name${mode:+ (r)}"
      case "$r" in
        *"-> OK"*) ok=$((ok+1)); printf '%-28s ok   %s\n' "$tag" "${r#RESULT: }" ;;
        *)         ng=$((ng+1)); printf '%-28s ERR  %s\n' "$tag" "${r#RESULT: }" ;;
      esac
    done
  done
done
echo "ok=$ok  err=$ng"
