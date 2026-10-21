#!/usr/bin/env python3
"""STM-1.2 のハードウェアの 2 つの不具合 (rtos/README.ja.md 参照) を静的に検査する。

1. 条件分岐の予測ミス: 取り消された命令 (A サイクル) の結果が, 同じサイクルに
   D で発行される正しい側の最初の命令組 (最大 2 命令) にバイパスされてしまう。
   各条件分岐について, 予測で先に進む側 (後方分岐は taken, 前方分岐は not taken)
   の最初の WRONG_N 命令が書くレジスタを, 反対側の最初の FIRST_N 命令が読まないこと
   を調べる。無条件分岐 (B, BAL) はたどり, J / RFE / SVC / 次の条件分岐で打ち切る。
   正しい側で先に書いたレジスタを後の命令が読むのは問題ない (その命令は次の組になる)。
2. ロードの結果を待たない命令: A サイクルのインタロック (A_EAB) は GR を書く命令
   しか見ていないため, WSR の GR, ストアと J のベースレジスタは, 直前のロードの
   結果を待たずに古い値を使う。これらの直前 LOAD_N 命令に, そのレジスタへの
   ロードがないことを調べる (間に GR を書く EX 命令でコピーすればよい)。
3. RFE の後ろの条件分岐: RFE はパイプラインの命令を取り消すが, 未解決の BC の印
   (G_BC_PENDING) は消さない (消すのは割り込みだけ)。RFE の後ろで先に発行された
   条件分岐が残り, 復帰先で CC を作る最初の命令で「解決」されて, 予測と違えば
   復帰先の命令が取り消され, その条件分岐の飛び先 (カーネル) へ進んでしまう。
   I/O 領域へのロードは未解決の BC がある間は待つので, そこで止まる。
   RFE の後ろ RFE_N 命令 (無条件分岐はたどる) に条件分岐がないことを調べる。

使い方: python rtos/check_bc.py rtos/rtos.s    (問題があれば終了コード 1)
"""
import re
import sys

WRONG_N = 4     # 取り消し時に誤って発行されている命令数 (実際は 1 組 = 2 命令, 余裕を見て 2 組)
FIRST_N = 2     # 取り消しと同じサイクルに D にいる正しい側の命令数
LOAD_N = 4      # WSR の前に見る命令数
RFE_N = 8       # RFE の後ろで見る命令数 (RFE が W に着くまでに D を通りうる数より多め)

EX_RE = re.compile(r"^([ASC]U?|[NOX]|S[RL][AL]?)(\.c)?\s+(.*)$")


def parse(path):
    """(番地 -> 命令テキスト, ラベル -> 番地) を作る (asm.py と同じ数え方)"""
    insns, labels, ad = {}, {}, 0
    for raw in open(path, encoding="utf-8"):
        line = re.sub(r"#.*", "", raw).rstrip()
        if not line.strip():
            continue
        m = re.search(r"EQU\s+([0-9A-Fa-f]+)", line)
        if m:
            ad = int(m.group(1), 16)
            continue
        m = re.match(r"^(\w+):$", line.strip())
        if m:
            labels[m.group(1)] = ad
            continue
        if line.startswith("USING"):
            continue
        if re.match(r"^[0-9A-Fa-f]+$", line):
            ad += len(line) // 2
            continue
        insns[ad] = line.strip()
        ad += 4
    return insns, labels


def regs_of(text):
    """命令の (読むレジスタ, 書くレジスタ, 種類, 分岐先ラベル)"""
    op, _, rest = text.partition(" ")
    args = [a.strip() for a in rest.split(",")] if rest.strip() else []
    rd, wr = set(), set()

    def mem(a):      # "13(4C)" -> base reg
        m = re.match(r"^(\d+)\(", a)
        return {int(m.group(1))} if m else {14}      # ラベルなら USING の GR14

    if op in ("L", "L.b", "L.h"):
        wr.add(int(args[0])); rd |= mem(args[1]); return rd, wr, "seq", None
    if op in ("ST", "ST.b", "ST.h"):
        rd.add(int(args[0])); rd |= mem(args[1]); return rd, wr, "seq", None
    if op == "SETHI":
        wr.add(int(args[0])); return rd, wr, "seq", None
    if op == "RSR":
        wr.add(int(args[0])); return rd, wr, "seq", None
    if op == "WSR":
        rd.add(int(args[1])); return rd, wr, "seq", None
    if op in ("RFE", "SVC"):
        return rd, wr, "stop", None
    if op == "J":
        return mem(args[0]), wr, "stop", None
    if op == "B":
        return rd, wr, "jump", args[0]
    if op == "BAL":
        wr.add(int(args[0])); return rd, wr, "jump", args[1]
    if op in ("BE", "BNE", "BL", "BG", "BLE", "BGE"):
        return rd, wr, "cond", args[0]
    m = EX_RE.match(text)
    if m:
        name = m.group(1)
        if name in ("C", "CU"):
            rs1, op2 = args[0], args[1]
        else:
            wr.add(int(args[0])); rs1, op2 = args[1], args[2]
            if name == "X" and rs1 == op2:      # X r,r,r は値に依らず 0
                return rd, wr, "seq", None
        rd.add(int(rs1))
        if op2.startswith("%"):
            pass
        elif re.match(r"^\d+$", op2):
            rd.add(int(op2))
        else:
            rd |= mem(op2)
        return rd, wr, "seq", None
    raise SystemExit("unknown instruction: " + text)


def path(insns, labels, ad, n):
    """ad から実行順に最大 n 命令の (番地, 読む, 書く) を返す"""
    out = []
    while len(out) < n and ad in insns:
        rd, wr, kind, tgt = regs_of(insns[ad])
        out.append((ad, rd, wr))
        if kind == "stop" or (kind == "cond" and out[1:]):
            break
        ad = labels[tgt] if kind == "jump" else ad + 4
    return out


def main():
    insns, labels = parse(sys.argv[1])
    bad = 0
    for ad, text in sorted(insns.items()):
        _, _, kind, tgt = regs_of(text)
        if kind != "cond":
            continue
        sides = {"taken": labels[tgt], "fall": ad + 4}
        # 静的予測: 後方分岐は taken, 前方分岐は not taken と予測して先に進む。
        # 誤って進むのは予測した側だけなので, 検査するのは 1 方向でよい。
        if labels[tgt] <= ad:
            pairs = (("fall", "taken"),)
        else:
            pairs = (("taken", "fall"),)
        for good, wrong in pairs:
            first = path(insns, labels, sides[good], FIRST_N)
            other = path(insns, labels, sides[wrong], WRONG_N)
            written = set().union(*[w for _, _, w in other]) if other else set()
            own = set()
            for a, rd, wr in first:
                hit = (rd - own) & written
                if hit:
                    bad += 1
                    print("%03x %-14s %s side: %03x %-16s reads GR%s written on %s side"
                          % (ad, text, good, a, insns[a],
                             ",".join(map(str, sorted(hit))), wrong))
                own |= wr
    # ロードの結果を待たないもの: WSR の GR, ストアと J のベースレジスタ
    for ad, text in sorted(insns.items()):
        op, _, rest = text.partition(" ")
        args = [a.strip() for a in rest.split(",")]
        if op == "WSR":
            src = int(args[1])
        elif op in ("ST", "ST.b", "ST.h", "J"):
            m = re.match(r"^(\d+)\(", args[-1])
            src = int(m.group(1)) if m else 14
        else:
            continue
        for k in range(1, LOAD_N + 1):
            prev = insns.get(ad - 4 * k)
            if prev is None:
                break
            rd, wr, kind, _ = regs_of(prev)
            if src in wr:
                if prev.split()[0] in ("L", "L.b", "L.h"):
                    bad += 1
                    print("%03x %-14s uses GR%d loaded at %03x %s"
                          % (ad, text, src, ad - 4 * k, prev))
                break
            if kind != "seq":
                break
    # RFE の後ろの条件分岐
    for ad, text in sorted(insns.items()):
        if text.split()[0] != "RFE":
            continue
        a, seen = ad + 4, 0
        while seen < RFE_N and a in insns:
            _, _, kind, tgt = regs_of(insns[a])
            if kind == "cond":
                bad += 1
                print("%03x %-14s is followed by %03x %s" % (ad, text, a, insns[a]))
                break
            seen += 1
            a = labels[tgt] if kind == "jump" else a + 4
    print("conflicts: %d" % bad)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
