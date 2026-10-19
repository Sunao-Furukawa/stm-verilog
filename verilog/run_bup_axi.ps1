# run_bup_axi.sh の PowerShell 版。AXI4 マスタ版 (stm_axi_top) で bup0/bup1 の全テストを実行する。
# 各テストを 5 通りで動かす:
#   (axi)       ウェイト無しのスレーブ                     (命令キャッシュ 4KB)
#   (axi r)     乱数でウェイト・応答順の入れ替え           (SEED=1)
#   (axi r bs)  同上 + BYTE_SWAP=1 (バイトレーン入れ替え)  (SEED=2)
#   (axi r tc)  同上, 命令キャッシュ 16 バイト x 2 ライン   (SEED=3, 入れ替えが多い)
#   (axi r nc)  同上, 命令キャッシュ無し                   (SEED=4)
#   使い方 (verilog フォルダで):  powershell -ExecutionPolicy Bypass -File run_bup_axi.ps1
# 必要なもの: python, iverilog/vvp
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force work | Out-Null

$src = @('tb/tb_stm_axi.v', 'tb/axi4_mem_slave.v', 'rtl/stm_axi_top.v', 'rtl/stm_icache.v',
         'rtl/stm_axi_master.v', 'rtl/stm_cntl.v', 'rtl/stm_exu.v', 'rtl/stm_regfile.v')
iverilog -g2001 -Wall -I rtl -o work/axi.vvp @src
if ($LASTEXITCODE -ne 0) { throw 'iverilog でのコンパイルに失敗しました' }
iverilog -g2001 -Wall -I rtl -P tb_stm_axi.BYTE_SWAP=1 -o work/axi_bs.vvp @src
if ($LASTEXITCODE -ne 0) { throw 'iverilog でのコンパイルに失敗しました' }
iverilog -g2001 -Wall -I rtl -P tb_stm_axi.IC_LINE_W=4 -P tb_stm_axi.IC_SET_W=1 -o work/axi_tc.vvp @src
if ($LASTEXITCODE -ne 0) { throw 'iverilog でのコンパイルに失敗しました' }
iverilog -g2001 -Wall -I rtl -P tb_stm_axi.ICACHE=0 -o work/axi_nc.vvp @src
if ($LASTEXITCODE -ne 0) { throw 'iverilog でのコンパイルに失敗しました' }

$modes = @(
  @{ Tag = 'axi';      Vvp = 'work/axi.vvp';    Args = @() },
  @{ Tag = 'axi r';    Vvp = 'work/axi.vvp';    Args = @('+RANDOM', '+SEED=1') },
  @{ Tag = 'axi r bs'; Vvp = 'work/axi_bs.vvp'; Args = @('+RANDOM', '+SEED=2') },
  @{ Tag = 'axi r tc'; Vvp = 'work/axi_tc.vvp'; Args = @('+RANDOM', '+SEED=3') },
  @{ Tag = 'axi r nc'; Vvp = 'work/axi_nc.vvp'; Args = @('+RANDOM', '+SEED=4') }
)
$ok = 0; $ng = 0
foreach ($lv in 0, 1) {
  foreach ($f in Get-ChildItem "../bup$lv" -File) {
    if ($f.Name -eq 'head') { continue }
    python tools/asm.py $f.FullName 250 -o work/mem.dat
    $info = python tools/mem2hex.py work/mem.dat work/mem.hex   # "PC=300 CYCLES=250"
    $pc  = ($info -split ' ')[0] -replace 'PC=', ''
    $cyc = [int](($info -split ' ')[1] -replace 'CYCLES=', '')
    # バスの往復が入るので、サイクル数は 20 倍まで許す
    $c = $cyc * 20
    foreach ($m in $modes) {
      $simArgs = @('-n', $m.Vvp, '+HEX=work/mem.hex', "+PC=$pc", "+CYCLES=$c") + $m.Args
      $r = (& vvp @simArgs | Select-String 'RESULT').Line
      $tag = "bup$lv/$($f.Name) ($($m.Tag))"
      if ($r -match '-> OK') { $ok++; $st = 'ok ' } else { $ng++; $st = 'ERR' }
      '{0,-34} {1}  {2}' -f $tag, $st, ($r -replace '^RESULT: ', '')
    }
  }
}
"ok=$ok  err=$ng"
