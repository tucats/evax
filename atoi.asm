
;
;	atoi test
;

	entry test
	
	pushal	@#s1
	calls	#1, decc$atoi
	
	pushl	r0
	pushal	@#s2
	calls	#2, decc$printf
	ret

s1:	.asciz	"1234"
s2: .asciz	"The answer is %d\n"

	end
	