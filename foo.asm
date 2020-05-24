;
;  Test program for autorun function in eVAX
;

	.entry test

	pushal	msg
	calls	#1,@#lib$put_output

        calls   #0, @#lib$quit_emulation

	ret

msg:	.ascid	"Test execution of program"

	.end	test

