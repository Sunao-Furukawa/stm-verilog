
CH_TOOLS = \
	../soft/head.c  \
	../soft/mid.c  \
	../soft/output.c  \
	../soft/chc  \
	../soft/perlcmd1 

CH_SRC = \
	../hard/010-d-pre.ch \
	../hard/015-d-i01.ch \
	../hard/020-d-iss.ch \
	../hard/030-d-sec.ch \
	../hard/035-d-ixx.ch \
	../hard/040-d-bra.ch \
	../hard/045-g-ram.ch \
	../hard/050-op-lb1.ch \
	../hard/060-g-srq.ch \
	../hard/070-g-ilk.ch \
	../hard/080-w-act.ch \
	../hard/090-e-act.ch \
	../hard/100-b-dat.ch \
	../hard/110-b-act.ch \
	../hard/120-a-dat.ch \
	../hard/130-a-act.ch \
	../hard/140-d-dat.ch \
	../hard/150-d-act.ch \
	../hard/160-op-lb2.ch \
	../hard/170-if-req.ch \
	../hard/180-if-lbs.ch \
	../hard/190-if-stm.ch \
	../hard/200-if-iwq.ch \
	../hard/210-g-bc.ch \
	../hard/const.h \
	../hard/defs.h \
	../hard/exu.h \
	../hard/fmt-jb.h \
	../hard/fmt-ls-ex.h \
	../hard/vdefs.h

siml.res:	stmsiml form.dat mem.dat
	stmsiml
sub.rpt:	stmsiml
	./subbup a
stmsiml:	$(CH_TOOLS) $(CH_SRC)
	../soft/chc
mem.dat:	tst.s 
	../soft/asm.pl tst.s 200 > mem.dat
archsim:	../soft/archsim.c
	cc -g -o archsim ../soft/archsim.c
asim.res:	archsim mm.dat
	./archsim mm.dat > asim.res
mm.dat:	tst.s 
	../soft/asm.pl tst.s 200 > mm.dat
clean: 
	rm -f ../work/cchdl.c ../work/chdl ../work/mem.dat ../work/siml.res
	rm -f ../work/stmsiml ../work/mm.dat ../work/archsim ../work/asim.res
	rm -f ../work/sub.rpt

