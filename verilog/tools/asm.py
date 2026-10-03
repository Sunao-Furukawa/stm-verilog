#!/usr/bin/env python3
"""STM アセンブラ (soft/asm.pl の Python 移植版)

Windows の Perl (Strawberry Perl など) は、日本語を含むフォルダの中で
  Can't open perl script "...": Unicode 文字のマッピングがターゲットの
  マルチバイト コード ページにありません。
というエラーになることがあるため、Perl を使わずに済むよう移植した。
出力は tools/asm64.pl (= soft/asm.pl の 64bit 対応版) と 1 文字単位で同じになる
ようにしてある (元のスクリプトの細かい癖もそのまま再現している)。

使い方:
    python tools/asm.py <ソース.s> [サイクル数] [-o 出力ファイル]
  -o を省略すると標準出力に書く。
  PowerShell 5 の '>' は UTF-16 で書いてしまうので、PowerShell では -o を使うこと。

出力 (mem.dat) の形式:
    1 行目: 開始番地 (main ラベル, 16 進)
    2 行目: サイクル数
    '# ラベル=番地' のコメント行, 'adr:' 行, 命令/データの 16 進 1 語
"""
import re
import sys

OPC_ARY = {"A": 1, "S": 2, "C": 3, "AU": 5, "SU": 6, "CU": 7, "N": 8, "O": 9,
           "X": 10, "SL": 11, "SRA": 12, "SRL": 13}
MASK_ARY = {"E": 8, "L": 4, "G": 2, "LE": 12, "GE": 10, "NE": 6}


class AsmError(Exception):
    pass


def num(s):
    """Perl の数値変換と同じく、未定義 (None) や空文字は 0 とみなす"""
    return int(s) if s else 0


def mytrunc(leng, val):
    """ラベル差分を leng 桁 (16 進) に収める。収まらなければエラー"""
    mask = 0xffffffff << (4 * leng - 1)
    mask2 = (1 << (4 * leng)) - 1
    if val < 0:
        if (val & mask) != mask:
            raise AsmError("label not resolved")
    elif (val & mask) != 0:
        raise AsmError("label not resolved")
    return val & mask2


def signed_hex(leng, s):
    """'-1a' のような符号付き 16 進文字列を leng 桁の 2 の補数にする"""
    mask = 0xffffffff << (4 * leng - 1)
    mask2 = (1 << (4 * leng)) - 1
    if s.startswith("-"):
        v = -int(s[1:], 16)
        if (v & mask) != mask:
            raise AsmError("Value of %s is bad" % s)
    else:
        v = int(s, 16)
        if (v & mask) != 0:
            raise AsmError("Value of %s is bad" % s)
    return v & mask2


def assemble(lines, cycles):
    out = []
    # ---- 1 パス目: ラベルの番地を求める ----
    labels = {}
    ad = 0
    main = 0
    for line in lines:
        line = re.sub(r"#.*", "", line)
        if re.search(r"EQU\s+([0-9A-Fa-f]+)", line):
            ad = int(re.search(r"EQU\s+([0-9A-Fa-f]+)", line).group(1), 16)
        elif re.search(r"(\w+):", line):
            name = re.search(r"(\w+):", line).group(1)
            labels[name] = ad
            if name == "main":
                main = ad
        elif re.search(r"^(([ASC]U?|[NOX]|S[RL][AL]?)(.c)?|(L|ST)(.[bh])?"
                       r"|B(|AL|GE?|E|LE?|NE)|JA?L?)\s", line):
            ad += 4
        elif re.search(r"USING", line):
            pass
        elif re.search(r"^([0-9A-Fa-f]+$)", line):
            d = re.search(r"^([0-9A-Fa-f]+$)", line).group(1)
            ad += len(d) // 2
            if len(d) % 8 != 0:
                raise AsmError("data not multiple of 4B")

    out.append("%x\n%d\n" % (main, cycles))
    for k, v in labels.items():
        out.append("# %5s=%6x\n" % (k, v))

    # ---- 2 パス目: 命令を 16 進に変換する ----
    ad = 0
    basereg = baseval = ibasereg = ibaseval = 0
    for line in lines:
        line = re.sub(r"#.*", "", line)
        is_insn = True
        m = None

        def s(p):
            nonlocal m
            m = re.search(p, line)
            return m

        # 特権命令
        if s(r"([RW])SR\s+(\d+)\s*,\s*(\d+)"):          # RSR 3,14 -> C230E000
            out.append("C2" if m.group(1) == "R" else "C3")
            out.append("%x0%x000\n" % (num(m.group(2)), num(m.group(3))))
        elif s(r"RFE"):
            out.append("C1000000\n")
        # LS 命令
        elif s(r"^(L|ST)(\.[bh])?\s+(\d+)\s*,\s*(.*)"):
            out.append("8" if m.group(1) == "L" else "9")               # OPCODE
            out.append("1" if m.group(2) == ".b" else
                       "2" if m.group(2) == ".h" else "0")              # LENG
            out.append("%x" % num(m.group(3)))                          # RD
            memop = m.group(4)
            m2 = re.search(r"(\d+)\((-?[0-9A-Za-f]+)\)", memop)        # "L 3,6(840)"
            if m2:
                out.append("%x%4.4x\n" % (num(m2.group(1)), signed_hex(4, m2.group(2))))
            else:
                m2 = re.search(r"(\w+)", memop)                         # "ST.b 3,LBL1"
                if m2:
                    out.append("%x%4.4x\n" % (
                        basereg, mytrunc(4, labels.get(m2.group(1), 0) - baseval)))
        # EX 命令          OPC                    SETCC      RD            RS1        OP2
        elif s(r"([ASC]U?|[NOX]|S[RL][AL]?)(\.c)?\s+((\d+)\s*,)?\s*(\d+)\s*,\s*(.*)"):
            opc = m.group(1)
            setcc = 1 if (m.group(2) == ".c" or opc in ("C", "CU")) else 0
            opcode = OPC_ARY.get(opc, 0)
            if opc in ("C", "CU") and m.group(3):
                raise AsmError("bad format")
            rd = 0 if opc in ("C", "CU") else num(m.group(4))
            rs1 = num(m.group(5))
            rb_etc = m.group(6)
            if re.search(r"%(-?[0-9A-Fa-f]+)", rb_etc):                 # RI モード
                v = re.search(r"%(-?[0-9A-Fa-f]+)", rb_etc).group(1)
                out.append("%x%x%x" % (6 + setcc, opcode, rd))
                out.append("%x%4.4x\n" % (rs1, signed_hex(4, v)))
            elif re.search(r"(\d+)\((-?[0-9A-Fa-f]+)\)", rb_etc):       # RM モード
                m2 = re.search(r"(\d+)\((-?[0-9A-Fa-f]+)\)", rb_etc)
                out.append("%x%x%x" % (4 + setcc, opcode, rd))
                out.append("%x%x%3.3x\n" % (num(m2.group(1)), rs1, signed_hex(3, m2.group(2))))
            elif re.search(r"^(\d+)\s*$", rb_etc):                      # RR モード
                r2 = re.search(r"^(\d+)\s*$", rb_etc).group(1)
                out.append("%x%x%x" % (2 + setcc, opcode, rd))
                out.append("%x%x000\n" % (rs1, num(r2)))
            elif re.search(r"(\w+)", rb_etc):                           # RM モード (ラベル)
                lbl = re.search(r"(\w+)", rb_etc).group(1)
                out.append("%x%x%x" % (4 + setcc, opcode, rd))
                out.append("%x%x%3.3x\n" % (
                    basereg, rs1, mytrunc(3, labels.get(lbl, 0) - baseval)))
        elif s(r"SETHI\s+(\d+)\s*,\s*%(-?[0-9A-Fa-f]+)"):
            out.append("6E%x0%4.4x\n" % (num(m.group(1)), signed_hex(4, m.group(2))))
        # JB 命令 (分岐)
        elif s(r"B(AL|E|L|G|[LGN]E)?\s+((\d+)\s*,\s*)?(.*)"):
            cond = m.group(1) or ""
            if cond == "":
                out.append("B00")                                       # "B %4e4"
            elif cond == "AL":
                out.append("B2%x" % num(m.group(3)))                    # "BAL L1"
            else:
                out.append("B8%x" % MASK_ARY.get(cond, 0))              # "BNE L2"
            tgt = m.group(4)
            if re.search(r"%(-?[0-9A-Fa-f]+)", tgt):
                v = re.search(r"%(-?[0-9A-Fa-f]+)", tgt).group(1)
                out.append("%5.5x\n" % signed_hex(5, v))
            elif re.search(r"(\w+)", tgt):
                lbl = re.search(r"(\w+)", tgt).group(1)
                out.append("%5.5x\n" % mytrunc(5, labels.get(lbl, 0) - ad))
        # JB 命令 (ジャンプ)  "J L1", "JAL 3,9(54)"
        elif s(r"J(A?L?)\s+((\d+)\s*,\s*)?(.*)"):
            if m.group(1) == "AL":
                out.append("B6%x" % num(m.group(3)))
            else:
                out.append("B40")
            tgt = m.group(4)
            if re.search(r"(\d+)\((-?[0-9A-Fa-f]+)\)", tgt):
                m2 = re.search(r"(\d+)\((-?[0-9A-Fa-f]+)\)", tgt)
                out.append("%x%4.4x\n" % (num(m2.group(1)), signed_hex(4, m2.group(2))))
            elif re.search(r"(\w+)", tgt):
                lbl = re.search(r"(\w+)", tgt).group(1)
                out.append("%x%4.4x\n" % (ibasereg, mytrunc(4, labels.get(lbl, 0) - ibaseval)))
        elif s(r"USING_I\s+(\d+)\s*,\s*(\w+)"):                         # USING_I 14,3a8
            is_insn = False
            ibasereg, ibaseval = num(m.group(1)), int(m.group(2), 16)
        elif s(r"USING\s+(\d+)\s*,\s*(\w+)"):                           # USING 14,3a8
            is_insn = False
            basereg, baseval = num(m.group(1)), int(m.group(2), 16)
        elif s(r"EQU\s+(\w+)"):                                         # EQU 3ac
            is_insn = False
            ad = int(m.group(1), 16)
            out.append(m.group(1) + ":\n")
        elif s(r"^[0-9A-Fa-f]+\s*(#.*)?$"):                             # データ
            is_insn = False
            # 元の asm.pl は ($1 が未定義のため) ここで $ad を 0 にしてしまう。
            # 出力を同じにするため、その動作もそのまま再現している。
            ad = len(m.group(1) or "") // 2
            out.append(line)
        else:
            is_insn = False                                             # ラベル, 空行など
        if is_insn:
            ad += 4
    return "".join(out)


def main():
    args = sys.argv[1:]
    outfile = None
    if "-o" in args:
        i = args.index("-o")
        outfile = args[i + 1]
        del args[i:i + 2]
    if not args:
        print(__doc__)
        sys.exit(2)
    src = args[0]
    cycles = int(args[1]) if len(args) > 1 else 100
    with open(src, encoding="ascii", errors="replace") as f:
        lines = f.readlines()
    try:
        text = assemble(lines, cycles)
    except AsmError as e:
        print(e)
        sys.exit(8)
    if outfile:
        with open(outfile, "w", encoding="ascii", newline="\n") as f:
            f.write(text)
    else:
        sys.stdout.buffer.write(text.encode("ascii"))


if __name__ == "__main__":
    main()
