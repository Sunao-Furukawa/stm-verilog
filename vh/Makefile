CH_SRC = \
	../../hard/010-d-pre.ch   \
	../../hard/045-g-ram.ch   \
	../../hard/100-b-dat.ch    \
	../../hard/160-op-lb2.ch \
	../../hard/015-d-i01.ch  \
	../../hard/050-op-lb1.ch  \
	../../hard/110-b-act.ch  \
	../../hard/170-if-req.ch \
	../../hard/020-d-iss.ch  \
	../../hard/060-g-srq.ch  \
	../../hard/120-a-dat.ch  \
	../../hard/180-if-lbs.ch \
	../../hard/030-d-sec.ch  \
	../../hard/070-g-ilk.ch  \
	../../hard/130-a-act.ch  \
	../../hard/190-if-stm.ch \
	../../hard/035-d-ixx.ch  \
	../../hard/080-w-act.ch  \
	../../hard/140-d-dat.ch  \
	../../hard/200-if-iwq.ch   \
	../../hard/040-d-bra.ch  \
	../../hard/090-e-act.ch  \
	../../hard/150-d-act.ch  \
	../../hard/210-g-bc.ch     \
	../../hard/const.h  \
	../../hard/fmt-jb.h  \
	../../hard/fmt-ls-ex.h  \
	../../hard/vdefs.h

world:	memory.vbe stmcntl.vbe

stmcntl.vbe:	all.vh
	sed -e '/VHDL decl/,/VHDL source/d' all.vh > stmcntl.vbe
all.vh:	c2v all.vp
	c2v < all.vp > all.vh
all.vp:	$(CH_SRC)
	../delcom a
c2v:	lex.yy.c y.tab.c c2v.c sym.dcl
	cc -o c2v c2v.c -ll
lex.yy.c:	../src.lex
	lex ../src.lex
y.tab.c:	../gram.yac
	yacc ../gram.yac
sym.dcl:	../assi.tab ../prop.tab ../mktab
	../mktab
mem.dat:	../../work/tst.s
	../../soft/asm.pl ../../work/tst.s 200 > mem.dat
memory.vbe:	mem.dat rommake
	./rommake mem.dat  memory.vbe
rommake:	../rommake.c
	cc -o rommake ../rommake.c
clean:
	rm lex.yy.c y.tab.c sym*.dcl c2v all.v? stmcntl.vbe rommake memory.vbe
	rm mem.dat

