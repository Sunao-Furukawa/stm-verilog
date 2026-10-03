# stm-verilog

STM-1.2 (2-way superscalar 32-bit RISC CPU, 1995) のハードウェア記述 (CHDL) を
**Verilog HDL 2001** に変換したものです。元の配布物一式と、変換した Verilog を含みます。

*A Verilog-2001 translation of STM-1.2, a 2-way superscalar 32-bit RISC CPU written in 1995
in a C-like HDL called CHDL. The translation is cycle-exact against the original C simulator.*

## 内容

| パス | 内容 |
|------|------|
| `verilog/` | **Verilog 2001 版** (今回追加)。詳しくは [verilog/README_ja.md](verilog/README_ja.md) |
| `hard/` | 元のハードウェア記述 (CHDL `*.ch` と C ヘッダ `*.h`) |
| `soft/` | 元のツール (CHDL→C 変換, アセンブラ, 命令セットシミュレータ) |
| `vh/` | 元の CHDL→VHDL 変換ツールと VHDL モデル |
| `bup0/`, `bup1/` | 回帰テスト用のアセンブリプログラム |
| `samples/`, `work/` | サンプルと作業用ディレクトリ |
| `doc/` | 元のドキュメント (英語 / 日本語) |

## Verilog 版の検証

* `iverilog -g2001 -Wall` で警告なし
* `bup0` / `bup1` の全 64 本 × (キャッシュミス無し / 乱数キャッシュミス有り) = 128/128 成功
* 元の C シミュレータと、65 本のプログラムで全サイクルの内部状態が完全一致

## 動かし方

Python 3 と Icarus Verilog が必要です (Perl は不要)。

```powershell
cd verilog
powershell -ExecutionPolicy Bypass -File run_bup.ps1   # Windows PowerShell
sh run_bup.sh                                          # sh / Git Bash
```

## ドキュメントの文字コードについて

`doc/japanese/` などの元の日本語ファイルは **EUC-JP** です (1995 年当時のまま)。
GitHub 上では文字化けして表示されるので、読むときは `iconv -f EUC-JP -t UTF-8` などで変換してください。
`verilog/` 以下の追加ファイルはすべて UTF-8 です。

## ライセンス

元の STM について、作者は次のように記しています。

* `doc/english/overview`: "It is free hardware; it is distributed under a condition similar to GPL."
* `doc/japanese/intro`: 「STMはフリー・ハードウェアとします。… その他もろもろはGPLに従う、としましょう。」

元の記述では GPL のバージョンが指定されていないため、このリポジトリ (Verilog 版を含む) は
**GNU General Public License version 2 (GPL v2)** で配布します。全文は [LICENSE](LICENSE) を参照してください。
