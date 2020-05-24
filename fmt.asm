
; Test of C format handling.

		entry test
		pushl #1
                pushl #8
		pushal @#fmt_str
		calls #3, @#decc$printf
		ret

fmt_str:	asciz "Test %d %08lX\n"
		end test

