;
;  Test of CVTLD, EXTZV sequence from LIB$INITIALIZE
;

	.entry	main, ^m<>

; Test 1,  writes

        cvtld   #3, @#three
        cvtld   #4, @#four

; Test 2, reads

;        movd    @#three, r3

; Test 3, math

        muld3   @#three,@#four, @#twelve

; Test 4, RTL init sequence

	movl	#^x03F, R0
	cvtld	r0, loc1
	extzv	#4, #^x0A, loc1, loc2

	ret

three:  .long   0,0
four:   .long   0,0
twelve: .long   0,0

loc1:	.blkb	16
loc2:	.blkb   16
	.end	main

