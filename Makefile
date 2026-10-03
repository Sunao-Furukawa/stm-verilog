E_DOC = doc/english
E_FILE =  \
	$(E_DOC)/overview	\
	$(E_DOC)/arch		\
	$(E_DOC)/hard1		\
	$(E_DOC)/hard2		\
	$(E_DOC)/hard3		\
	$(E_DOC)/dummyend

J_DOC = doc/japanese
J_FILE = $(J_DOC)/History \
	$(J_DOC)/ReleaseNote \
	$(J_DOC)/contents		\
	$(J_DOC)/intro		\
	$(J_DOC)/arch-hard-ov1		\
	$(J_DOC)/arch-hard-ov2		\
	$(J_DOC)/arch-hard-ov3		\
	$(J_DOC)/arch-hard-ov4		\
	$(J_DOC)/arch-hard-ov5		\
	$(J_DOC)/arch-hard-ov6		\
	$(J_DOC)/arch-hard-ov7		\
	$(J_DOC)/comments		\
	$(J_DOC)/soft1		\
	$(J_DOC)/soft2		\
	$(J_DOC)/soft3-or-install		\
	$(J_DOC)/soft4		\
	$(J_DOC)/vhdl-overview		\
	$(J_DOC)/vhdl-install		\
	$(J_DOC)/future		\
	$(J_DOC)/chdl-truth		\
	$(J_DOC)/arch-details01		\
	$(J_DOC)/arch-details02		\
	$(J_DOC)/arch-details03		\
	$(J_DOC)/arch-details04		\
	$(J_DOC)/arch-details05		\
	$(J_DOC)/arch-details06		\
	$(J_DOC)/arch-details07		\
	$(J_DOC)/arch-details08		\
	$(J_DOC)/arch-details09		\
	$(J_DOC)/arch-details10		


doc.e:	$(E_FILE)
	cat $(E_FILE) > doc.e
doc.j:	$(J_FILE)
	cat $(J_FILE) > doc.j
clean:
	rm doc.?

