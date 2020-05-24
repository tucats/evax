

	.entry	main, ^m<r2,r3,r4,r5>

	moval	@#src, r1
	moval	@#dst, r3

	movc3	#5,(r1),(r3)
	movc3   #5,(r1),(r3)
	movc3	#5,(r1),(r3)
	movl	#1, r0
	ret

src:	.ascii  "This is a string of text to be moved around."
dst:	.blkb	100

	.end	main

