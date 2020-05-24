;
;   Terminal output test module
;
;
;       write( p1 [, p2...]);
;
;       Writes output strings to the console.  The parameters may be
;       pointers to descriptors or single byte values.  If they are
;       single byte values, that byte is written to the console.  For
;       example,
;
;       write( dsc$msg, 0x0d, 0x0A );
;
;       will write the contents of the string descriptor dsc$msg and
;       then a carriage return/line feed sequence.
;

	.print " "
	.print "Performance test for eVAX.  After assembling, invoke"
	.print "by typing:"
	.print " "
	.print "VAX> time call main( ^d10000 )"
	.print " "
	.print "This times how long it takes to determine the largest"
	.print "prime number less than 10,000 (base ten)."
	.print " "

;
;       Format a number for printing.  Returns number of bytes written
;       to the buffer.
;
;       len = fmt_int( long word, char * buffer );
;
;


        .entry  fmt_int, ^m<r2,r3,r4,r5,r6,r7,r8>

;
;   We're going to allocate some stack space.  So move the SP down to
;   prepare room for it.

        subl2   #4,sp


        movl    b^4(ap), r2                     ; Get the value to format
        tstl    r2                              ; Is it zero?

        beql    _zero                           ; If so, special case

;
;   Allocate some "automatic storage" on the stack by marking where we
;   are (since we want the end of the buffer anyway) and move the SP
;   down in case we need it for something else.
;

        movl    sp,r6                           ; Point to end of space
        subl2   #20,sp                          ; and move end of stack down

        clrl    r7                              ; init the counter

_loop:  divl3   #^d10, r2, r3                   ; Shift off digit
        mull3   r3, #^d10, r4                   ; And back again
        subl3   r4, r2, r5                      ; Difference is digit
        addl2   #30, r5                         ; Make ASCII

        movb    r5, -(r6)                       ; copy to buffer, decrement
        incl    r7                              ; and increment counter

        tstl   r4                               ; Is there more?
        beql   _exit                            ; No, done

        movl   r3, r2                           ; Yes, set it up
        brb    _loop                            ; And loop again

_zero:  movl   sp, r6                           ; Get address of stack buffer
        movb   #30, (r6)                        ; Write "0" to buffer
        movl   #1, r7                           ; return length of 1

_exit:  movl   b^8(ap), r8                      ; Get address of buffer
        movc3  r7, (r6), (r8)                   ; Copy to user's buffer
        movl   r7, r0                           ; and return the length
        ret                                     ; Go home.

;
;       Write a list of items, passed as parameters via standard calling
;       conventions.
;

         .entry  write, ^m<r3,r4>
         movl    (ap), r3                        ; Count of arguments
         tstl    r3                              ; Are there any?
         beql    _exit                           ; No, we're done
         addl3   #4, ap, r4                      ; Yes, find first one

_loop:   pushl   (r4)+                           ; push the parameter
         calls   #1, @#put_output                ; call output
         sobgtr  r3, _loop                       ; loop if more
         movl    #1, r0                          ; else done
         ret

_exit:   movl    #1, r0
         ret


;
;       Write a single item.  This is where we test to see if the 
;       argument is a byte versus a pointer, based purely on the
;       size of the argument -- pointers cannot be less than 512.
;

         .entry  put_output, ^m<r2,r3,r4>

         movl    b^4(ap), r0                     ; Get descriptor address

         cmpl    r0, #7f                         ; see if it's one char.
         blss    _byte                           ; if so, print it

         clrl    r1                              ; Empty counter register
         movw    (r0), r1                        ; Get count word from desc
         beql    _exit                           ; If zero, then no work
         movl    b^4(r0), r2                     ; Else get address
         clrl    r4                              ; Clear data register

_loop:   movb    (r2)+, r4                       ; Get byte, advance ptr
         mtpr    r4, #VAX$PR_TXDB                ; Write next byte
         sobgtr  r1, _loop                       ; Decrement counter and rpt
         brb     _exit

_byte:   mtpr    r0, #VAX$PR_TXDB                ; Output single byte

_exit:   movl    #1, r0                          ; Signal success
         ret                                     ; And flee
        
;
;       n = sum( n1 [, n2...]);
;
;

        .entry  calcsum, ^m<r2,r3>

        clrl    r0
        movl    (ap), r2
        tstl    r2
        beql    _exit

        moval   b^4(ap), r3

_sum:   addl2   (r3)+, r0
        sobgtr  r2, _sum

_exit:  ret


;
;       Print the sum of all arguments passed.
;

        .entry  printsum, ^m<r2>

        callg   ap, @#calcsum
        movl    r0, r2

        pushl   #0d                       ; last parts of message are the
        pushl   #0a                       ; carriage control

        pushal  @#msgb                    ; Format the number into buffer
        pushl   r2
        calls   #2,@#fmt_int

        movw    r0, @#msg2                ; Make it a descriptor and push
        pushal  @#msg2

        pushal  @#msg1                   ; Message prefix

        calls   #4, @#write

        ret

msg1:   .ascid "The sum of the arguments is "

msg2:   .word  0, 0
        .long  msgb

msgb:   .blkb  ^d20


;
;       Main test program.  Calculate and print the sum of the arguments.
;

        .entry  sumtest, ^m<r2>

        moval   @#table, r2
        callg   r2, @#printsum
        ret

table:  .long   3
        .long   ^d100
        .long   ^d20
        .long   ^d3

        .entry  psltst

        clrl    r0
        tstl    r0
        calls   #0, @#main

;
;       Main test program.  Find the largest prime less than 1000 and
;       print it out.
;

        .entry  main, ^m<r2>

        tstl    (ap)                      ; see if we have an argument?
        bneq    _10                       ; yes we have one
        movl    #^d10000,r2               ; no, invent one
        brb     _20

_10:    movl    b^4(ap),r2

_20:    pushl   #0d                       ; last parts of message are the
        pushl   #0a                       ; carriage control

        pushal  @#_msgb                    ; Format the number into buffer

        pushl   r2                         ; Calculate largest prime <1000
        calls   #1, @#sieve

        pushl   r0
        calls   #2,@#fmt_int

        movw    r0, @#_msg2                ; Make it a descriptor and push
        pushal  @#_msg2

        pushal  @#_msg1                   ; Message prefix

        calls   #4, @#write

        ret

_msg1:  .ascid "The largest prime number is "

_msg2:  .word  0, 0
        .long  _msgb

_msgb:   .blkb  ^d20


;
;   SIEVE of ERISTOTHANIES
;
;   maxprime = sieve( maxnum );
;
;   Returns the largest prime number less than maxnum.
;


        .entry  sieve, ^m<r2,r3,r4,r5,r6,iv>

;
;       Let's get the size of the array.  Create an automatic storage
;       area on the stack to hold it.
;


        movl    b^4(ap),r5
        subl2   r5, sp
        movl    sp, r6

;
;       Establish a condition handler
;

        movab   @#errors, (fp)

;
;   Initialize the array
;

        movl    r5, r0

_init:  movab   (r6)[r0], r4    ;   Get address of cell (debug)
        clrb    (r4)            ;   and zap it.
        sobgtr  r0, _init

;
;   Choose the first prime number
;

        movl    #2, r1

;
;   Mark out the nth elements of the array
;

        movl    r1, r2       ;   prime is index

_mark:  movb    #1, (r6)[r2]    ;   write the marker byte
        addl2   r1, r2       ;   stride by prime
        cmpl    r2, r5       ;   are we done?

        bleq    _mark        ;   nope, go some more

;
;   Find the next free element
;

        movl    r1, r3       ;   make copy of last prime

_find:  incl    r1           ;   step to next cell
        cmpl    r1, r5       ;   are we at end of array?
        bgtr    _done        ;   yes, all done

        tstb    (r6)[r1]     ;   see if cell empty
        bneq    _find        ;   no, look some more

        movl    r1, r2       ;   yes, cell empty, so mark
        brb _mark            ;   this as new prime

_done:   movl    r3, r0      ;   we return last prime
                             ;   as function result
        ret

;
;   Condition handler (currently does nothing)
;
        .entry errors, ^m<>
        movl #1, r0         ;   just signal success
        ret


        .end                ; main

