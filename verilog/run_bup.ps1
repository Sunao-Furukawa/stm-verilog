# run_bup.sh の PowerShell 版。bup0/bup1 の全テストを Icarus Verilog で実行する。
#   使い方 (verilog フォルダで):  powershell -ExecutionPolicy Bypass -File run_bup.ps1
# 必要なもの: python, iverilog/vvp   (Perl も sh も不要)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force work | Out-Null

iverilog -g2001 -Wall -I rtl -o work/sim.vvp `
  tb/tb_stm.v rtl/stm_sys.v rtl/stm_cntl.v rtl/stm_exu.v rtl/stm_regfile.v rtl/stm_memory.v
if ($LASTEXITCODE -ne 0) { throw 'iverilog でのコンパイルに失敗しました' }

$ok = 0; $ng = 0
foreach ($lv in 0, 1) {
  foreach ($f in Get-ChildItem "../bup$lv" -File) {
    if ($f.Name -eq 'head') { continue }
    python tools/asm.py $f.FullName 250 -o work/mem.dat
    $info = python tools/mem2hex.py work/mem.dat work/mem.hex   # "PC=300 CYCLES=250"
    $pc  = ($info -split ' ')[0] -replace 'PC=', ''
    $cyc = [int](($info -split ' ')[1] -replace 'CYCLES=', '')
    foreach ($mode in '', '+RANDOM') {
      # 乱数モードはキャッシュミスで遅くなるので 2 倍のサイクルを与える
      $c = if ($mode) { $cyc * 2 } else { $cyc }
      $simArgs = @('-n', 'work/sim.vvp', '+HEX=work/mem.hex', "+PC=$pc", "+CYCLES=$c")
      if ($mode) { $simArgs += $mode }
      $r = (& vvp @simArgs | Select-String 'RESULT').Line
      $tag = "bup$lv/$($f.Name)" + $(if ($mode) { ' (r)' } else { '' })
      if ($r -match '-> OK') { $ok++; $st = 'ok ' } else { $ng++; $st = 'ERR' }
      '{0,-28} {1}  {2}' -f $tag, $st, ($r -replace '^RESULT: ', '')
    }
  }
}
"ok=$ok  err=$ng"
