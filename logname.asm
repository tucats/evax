
	.entry main


	pushab	accmode
        pushal	itmlst
       	pushal	@#lognam
	pushal	@#tabnam
	pushl	#0		; attribute flags
	calls 	#5, @#sys$trnlnm
	ret

tabnam:	.ascid	"LNM$PROCESS"
lognam:
	.ascid	"FOO"
itmlst:	.long	0
accmode: .byte  0

	.end main

