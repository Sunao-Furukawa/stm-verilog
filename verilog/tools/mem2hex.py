#!/usr/bin/env python3
"""soft/asm.pl が出力する mem.dat を $readmemh 形式に変換する。

mem.dat の形式 (soft/mid.c 参照):
    1 行目: 開始番地 (16 進)
    2 行目: サイクル数 (10 進)
    以降  : "adr:" 行 (16 進バイト番地) と データ行 (16 進 1 語), '#' はコメント

使い方: mem2hex.py mem.dat out.hex
        標準出力に "PC=<hex> CYCLES=<dec>" を表示する。
"""
import sys


def main():
    src, dst = sys.argv[1], sys.argv[2]
    # PowerShell 5 の '>' でリダイレクトすると UTF-16 (BOM 付き) になるので、
    # BOM を見て文字コードを判定する
    raw = open(src, "rb").read()
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        text = raw.decode("utf-16")
    else:
        text = raw.decode("utf-8-sig", errors="replace")
    lines = text.splitlines()
    start = int(lines[0].strip(), 16)
    cycles = int(lines[1].strip())
    out = []
    for s in lines[2:]:
        s = s.strip()
        if not s or s.startswith("#"):
            continue
        if s.endswith(":"):
            out.append("@%x" % (int(s[:-1], 16) // 4))
        else:
            out.append(s.lower())
    with open(dst, "w") as f:
        f.write("\n".join(out) + "\n")
    print("PC=%x CYCLES=%d" % (start, cycles))


if __name__ == "__main__":
    main()
