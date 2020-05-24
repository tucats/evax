
; Vforth--a 32 bit forth system using subroutine threading for
;   increased speed.
;
;   By Andy Valencia, 1984
;
;   Minor tweaks and changes to make this work with eVAX
;   By Tom Cole, 1999
;
;
; Registers with fixed uses:
;   PC - Since we're using direct threading, this operates as the actual
;       execution vector for each instruction.
;   SP - Maintains the return stack
;   R11 - The operand stack
;   R10 - Next open byte in the dictionary--"HERE"
;   R9  - Index into current input line
;   R8  - Points to last entry in the dictionary chain
;

    .console set radix dec
    .console set verify
    .region s0
    .align 512
;
; These are the constants which are compiled into the executable code
;
    .set    jsb_header,0x9F16   ; jsb @#...
    .set    lit_header,0x8FD0   ; pushl #...
    .set    lit_tailer,0x7B
    .set    rsb_header,0x5      ; rsb
    .set    Again_header,0x9F17 ; jmp @#...
    .set    Skipt,0x6128BD5     ; tstl (r11)+; bnequ .+6

;
; These are the other constants
;
    .set    XRecursive,1        ; SFA bits: recursive function
    .set    XSmudged,2      ;   SMUDGE bit
    .set    Priority,4      ;   IMMEDIATE
    .set    Primitive,8     ;   PRIMITIVE--is a code macro

    .set    NL,10           ; Newline
    .set    Spc,32          ; Space
    .set    Tab,9           ; Tab

    .set    Mrkcolon,1      ; For control structure matching
    .set    Mrkif,2
    .set    Mrkdo,3
    .set    Mrkbegin,4
    .set    Mrkwhile,5

    ; .data 0

    .entry  exe$cforth, ^m<r2,r3,r4,r5,r6,r7,r8,r9,r10,r11>

    movl    4(ap), r2
    movl    #inline, r9
    pushl   r2
    pushl   r9
    calls   #2, @#decc$strcpy
    brw     exe$forth_suffix

    .entry  exe$forth,^m<r2,r3,r4,r5,r6,r7,r8,r9,r10,r11>       ; Procedure entry mask

    tstl    (ap)
    bneq    _move
    brw     go1             ; if no string argument, then done

_move:
    movl    4(ap),r0        ; get address of descriptor
    movl    #inline,r9      ; copy string here

    cvtwl   (r0),r2
    pushl   r2              ; length to copy

    pushl   4(r0)           ; source
    pushal  @#inline        ; destination
    calls   #3,@#decc$strncpy

    clrb    (r2)[r9]        ; null terminate it

exe$forth_suffix:

    pushal  @#_pad          ; tack on " halt "
    pushl   r9
    calls   #2,@#decc$strcat

    movl    @#dictend,r10       ; r10 is end of dictionary
    movl    sp,sp_hold      ; For resetting SP later
    movl    @#latest,r8     ; Setup R8 to end of dict.
    movl    sp_hold,sp      ; Start SP from its initial value
    subl3   #80,sp,r11      ; Leave 80 bytes for opstack
    movl    r11,stacklim        ; For underflow checking
    clrl    @#state         ; Turn off compile mode
    movl    #istk,isp       ; Reset I/O system

    clrl    istk
    clrl    iunit
    movl    #ostk,osp
    cvtbl   #1,ostk
    cvtbl   #1,ounit
    jbr interp          ; Start up the interpretive loop

_pad: .asciz " halt "
        
go1:    movl    @#dictend,r10       ; r10 is end of dictionary
    movl    sp,sp_hold      ; For resetting SP later
    movl    @#latest,r8     ; Setup R8 to end of dict.
abort:  movl    sp_hold,sp      ; Start SP from its initial value
    subl3   #80,sp,r11      ; Leave 80 bytes for opstack
    movl    r11,stacklim        ; For underflow checking
    clrl    @#state         ; Turn off compile mode
    movl    #istk,isp       ; Reset I/O system

    movl    #inline,r9      ; Set up input line as empty
    clrb    (r9)

    clrl    istk
    clrl    iunit
    movl    #ostk,osp
    cvtbl   #1,ostk
    cvtbl   #1,ounit
    jbr interp          ; Start up the interpretive loop

;
; Some data area
;
sp_hold: .space 4           ; Holds return stack base
stacklim: .space 4          ; Holds bottom of stack
inline: .space  1025            ; Room for a block of input
wrd:    .space  81          ;  and up to 80-char word
latest:                 ; Last intrinsic word in dictionary
    .long   interp1

;
; Pushdown list of input & output file descriptors
istk:   .long   0,0,0,0,0,0,0,0
isp:    .long   istk
ideep:  .long   0
iunit:  .long   0
ostk:   .long   1,1,1,1,1,1,1,1
osp:    .long   ostk
odeep:  .long   0
ounit:  .long   1

;
; KLUDGE city! When we push down an input file, we have to save the buffer,
;   otherwise the new input file will abuse it in various undesireable
;   ways. So we make room for a save image of each input unit.
ibufs:  .space  1024@8  ; The input buffers
ibufx:  .space  4@8 ;  and the current position within them

;
; Open the given file for output; add it to the pushdown stack. Error
;   if it can't be opened.
;
outfcb: .long   3
outname: .space 4
    .long   0x201,0x1FF
outopen:
    movl    r0,outname
    movl    #outfcb,ap
    chmk    #5
    bcs outop1
    movl    osp,r1
    addl2   #4,r1
    movl    r0,(r1)
    movl    r0,ounit
    movl    r1,osp
    incl    odeep
    rsb
outop1: movl    #outop2,r0  ; Couldn't open--complain
    jsb prstr
    jbr abort
outop2: .asciz  " Could not open output file\n"

;
; Open the given file for input; add it to the pushdown stack. Error
;   if it can't be opened.
;
infcb:  .long   3       ; parms to do a OPEN for READ syscall
inname: .space  4
    .long   0,0x1FF

inopen: movl    r0,inname   ; Set up name for open
    movl    #infcb,ap
    chmk    #5
    bcs inop1

                ; Open successful, save previous buffer
    movl    #256,r2     ; R2 is the number of bytes to move
    movl    ideep,r3
    mull2   #1024,r3
    addl2   #ibufs,r3   ; R3 now points to our save location
    movl    #inline,r1  ; R1 points to the buffer to save
inop3:  movl    (r1)+,(r3)+ ; Move the bytes
    sobgtr  r2,inop3
    movl    ideep,r3    ; Now save the input index
    movl    r9,ibufx[r3]
    movl    #inline,r9  ; Clear the input buffer
    clrb    (r9)

    movl    isp,r1      ; Push down the old file descriptor
    addl2   #4,r1
    movl    r0,(r1)
    movl    r0,iunit
    movl    r1,isp
    incl    ideep
    rsb
inop1:  movl    #inop2,r0   ; Bad open, complain & abort
    jsb prstr
    jbr abort
inop2:  .asciz  " Could not open input file.\n"

;
; ----Start of FORTH dictionary
;

;
; over--copy second to new top
;
over2:  .long   0,over1
    .word   4,Primitive
    .asciz  "over"
over1:  movl    4(r11),-(r11)
    rsb

;
; abs,fabs--get absolute value
;
abs2:   .long   over2,abs1,0
    .asciz  "abs"
abs1:   tstl    (r11)
    bgeq    abs3
    mnegl   (r11),(r11)
abs3:   rsb
fabs2:  .long   abs2,fabs1,0
    .asciz  "fabs"
fabs1:  tstf    (r11)
    bgeq    abs3
    mnegf   (r11),(r11)
    rsb

;
; max,fmax--get maximum value
;
max2:   .long   fabs2,max1,0
    .asciz  "max"
max1:   movl    (r11)+,r0
    cmpl    r0,(r11)
    bleq    max3
    movl    r0,(r11)
max3:   rsb
fmax2:  .long   max2,fmax1,0
    .asciz  "fmax"
fmax1:  movf    (r11)+,r0
    cmpf    r0,(r11)
    bleq    max3
    movf    r0,(r11)
fmax3:  rsb

;
; min,fmin--get minimum value
;
min2:   .long   fmax2,min1,0
    .asciz  "min"
min1:   movl    (r11)+,r0
    cmpl    r0,(r11)
    bgeq    min3
    movl    r0,(r11)
min3:   rsb
fmin2:  .long   min2,fmin1,0
    .asciz  "fmin"
fmin1:  movf    (r11)+,r0
    cmpf    r0,(r11)
    bgeq    min3
    movf    r0,(r11)
fmin3:  rsb

;
; c@, c!--byte fetch/store operators
;
cfet2:  .long   fmin2,cfet1
    .word   6,Primitive
    .asciz  "c@"
cfet1:  movl    (r11),r0
    cvtbl   (r0),(r11)
    rsb
csto2:  .long   cfet2,csto1
    .word   6,Primitive
    .asciz  "c!"
csto1:  movl    (r11)+,r0
    cvtlb   (r11)+,(r0)
    rsb

;
; negate & fnegate
;
neg2:   .long   csto2,neg1
    .word   3,Primitive
    .asciz  "negate"
neg1:   mnegl   (r11),(r11)
    rsb
fneg2:  .long   neg2,fneg1
    .word   3,Primitive
    .asciz  "fnegate"
fneg1:  mnegf   (r11),(r11)
    rsb

;
; HERE--provide the address of the next open byte in the dictionary
;
here2:  .long   fneg2,here1
    .word   3,Primitive
    .asciz  "here"
here1:  movl    r10,-(r11)
    rsb

;
; "r>" & ">r"--move a word between op & return stacks
;
to_r2:  .long   here2,to_r1
    .word   2,Primitive
    .asciz  ">r"
to_r1:  pushl   (r11)+
    rsb
from_r2:
    .long   to_r2,from_r1
    .word   3,Primitive
    .asciz  "r>"
from_r1:
    movl    (sp)+,-(r11)
    rsb

;
; fill--fill an area of memory with a constant
;
fill2:  .long   from_r2,fill1,0
    .asciz  "fill"
fill1:  cvtlb   (r11)+,r0
    movl    (r11)+,r1
    movl    (r11)+,r2
fill3:  movb    r0,(r2)+
    sobgtr  r1,fill3
fill4:  rsb

;
; pick--get a word in the stack
;
pick2:  .long   fill2,pick1,0
    .asciz  "pick"
pick1:  movl    (r11)+,r0
    movl    (r11)[r0],-(r11)
    rsb

;
; 'c,' & ','--push word to HERE
;
comma2: .long   pick2,comma1
    .word   3,Primitive
    .asciz  ","
comma1: movl    (r11)+,(r10)+
    rsb
ccomm2: .long   comma2,ccomm1
    .word   3,Primitive
    .asciz  "c,"
ccomm1: cvtlb   (r11)+,(r10)+
    rsb

;
; rot,-rot --the rotational operators
;
rot2:   .long   ccomm2,rot1,0
    .asciz  "rot"
rot1:   movl    (r11)+,r0
    movl    (r11)+,r1
    movl    (r11),r2
    movl    r1,(r11)
    movl    r0,-(r11)
    movl    r2,-(r11)
    rsb
drot2:  .long   rot2,drot1,0
    .asciz  "-rot"
drot1:  movl    (r11)+,r0
    movl    (r11)+,r1
    movl    (r11),r2
    movl    r0,(r11)
    movl    r2,-(r11)
    movl    r1,-(r11)
    rsb

;
; allot--move the end of the dictionary forward a number of bytes
;
allot2: .long   drot2,allot1
    .word   3,Primitive
    .asciz  "allot"
allot1: addl2   (r11)+,r10
    rsb

;
; 2dup, 2swap--double-int stack operators
;
tdup2:  .long   allot2,tdup1,0
    .asciz  "2dup"
tdup1:  movl    (r11)+,r0
    movl    (r11),r1
    movl    r0,-(r11)
    movl    r1,-(r11)
    movl    r0,-(r11)
    rsb
tswap2: .long   tdup2,tswap1,0
    .asciz  "2swap"
tswap1: movl    (r11)+,r0
    movl    (r11)+,r1
    movl    (r11)+,r2
    movl    (r11),r3
    movl    r1,(r11)
    movl    r0,-(r11)
    movl    r3,-(r11)
    movl    r2,-(r11)
    rsb

;
; "("--handle forth comments
;
comm2:  .long   tswap2,comm1
    .word   0,Priority
    .asciz  "("
comm1:  movb    (r9)+,r0    ; Get next byte of input
    cmpb    r0,0        ; Get another buffer-full if hit end of cur.
    beql    comm3
    cmpb    r0,#10      ; End comment on newline or close paren
    beql    comm4
    cmpb    r0,#41
    bneq    comm1
comm4:  rsb
comm3:  jsb getlin      ; Get another buffer
    brb comm1

;
; "abort"--calls the forth abort code
;
abo2:   .long   comm2,abo1,0
    .asciz  "abort"
abo1:   jbr abort

;
; "halt"--cause forth to exit
;
halt3:  .long   1,0
halt2:  .long   abo2,halt1,0
    .asciz  "halt"
exit:
halt1:  movl    #halt3,ap
    movl    r10, @#dictend  ; save end of dictionary storage area
    movl    r8, @#latest;   ; end of dictionary linked list
    ret ; chmk  #1

;
; "outpop"--do for the output list what EOF does for the input list;
;   close the current output file & pop back a level
;
outp4:  .long   1
outp3:  .space  4
outp2:  .long   halt2,outp1,0
    .asciz  "outpop"
outp1:  movl    osp,r0      ; Get the stack pointer to R0
    cmpl    r0,#ostk    ; Don't pop off end of stack
    beql    outp5
    movl    ounit,outp3 ; Close the current unit
    moval   outp4,ap
    chmk    #6
    movl    osp,r0
    subl2   #4,r0       ; Move back a position
    movl    (r0),ounit  ;  and set output to that file descriptor
    movl    r0,osp
    decl    odeep       ; Decrement nesting count
outp5:  rsb

;
; "output"--open the named output file & make it the new output unit
;
out2:   .long   outp2,out1,0
    .asciz  "output"
out1:   jsb getw
    movl    #wrd,r0
    jsb outopen
    rsb

;
; "input"--open the named file & make it the new input unit
;
inp2:   .long   out2,inp1,0
    .asciz  "input"
inp1:   jsb getw        ; Get the name of the file
    movl    #wrd,r0
    jsb inopen
    rsb

;
; Push logical constants to stack
;
false2: .long   inp2,false1
    .word   2,Primitive
    .asciz  "false"
false1: clrl    -(r11)
    rsb
true2:  .long   false2,true1
    .word   4,Primitive
    .asciz  "true"
true1:  cvtbl   #-1,-(r11)
    rsb

;
; the logical operators. Note that they serve for both logical and
;   bitwise purposes, as "true" is defined as -1.
;
lor2:   .long   true2,lor1
    .word   3,Primitive
    .asciz  "or"
lor1:   bisl2   (r11)+,(r11)
    rsb
land2:  .long   lor2,land1,0
    .asciz  "and"
land1:  bitl    (r11)+,(r11)
    bneq    land3
    clrl    (r11)
    rsb
land3:  cvtbl   #-1,(r11)
    rsb

;
; the floating relational operators
;
feq2:   .long   land2,feq1,0
    .asciz  "f="
feq1:   cmpf    (r11)+,(r11)
    beql    feq3
    clrl    (r11)
    rsb
feq3:   cvtbl   #-1,(r11)
    rsb
fgt2:   .long   feq2,fgt1,0 ; Greater than
    .asciz  "f>"
fgt1:   cmpf    (r11)+,(r11)
    blss    fgt3
    clrl    (r11)
    rsb
fgt3:   cvtbl   #-1,(r11)
    rsb
flt2:   .long   fgt2,flt1,0 ; Less than
    .asciz  "f<"
flt1:   cmpf    (r11)+,(r11)
    bgtr    flt3
    clrl    (r11)
    rsb
flt3:   cvtbl   #-1,(r11)
    rsb

;
; the relational operators
;
eq2:    .long   flt2,eq1,0
    .asciz  "="
eq1:    cmpl    (r11)+,(r11)
    beql    eq3
    clrl    (r11)
    rsb
eq3:    cvtbl   #-1,(r11)
    rsb
gt2:    .long   eq2,gt1,0   ; Greater than
    .asciz  ">"
gt1:    cmpl    (r11)+,(r11)
    blss    gt3
    clrl    (r11)
    rsb
gt3:    cvtbl   #-1,(r11)
    rsb
lt2:    .long   gt2,lt1,0   ; Less than
    .asciz  "<"
lt1:    cmpl    (r11)+,(r11)
    bgtr    lt3
    clrl    (r11)
    rsb
lt3:    cvtbl   #-1,(r11)
    rsb

;
; drop,2drop--get rid of top item(s)
;
tdrop2: .long   lt2,tdrop1
    .word   3,Primitive
    .asciz  "2drop"
tdrop1: addl2   #8,r11
    rsb
drop2:  .long   tdrop2,drop1
    .word   3,Primitive
    .asciz  "drop"
drop1:  movl    (r11)+,r0
    rsb

;
; swap--exchange top & second
;
swap2:  .long   drop2,swap1
    .word   12,Primitive
    .asciz  "swap"
swap1:  movl    (r11)+,r0
    movl    (r11),r1
    movl    r0,(r11)
    movl    r1,-(r11)
    rsb

;
; dup--duplicate top
;
dup2:   .long   swap2,dup1
    .word   3,Primitive
    .asciz  "dup"
dup1:   movl    (r11),-(r11)
    rsb

;
; "if"--conditional control structure
;
if2:    .long   dup2,if1
    .word   0,Priority
    .asciz  "if"
if1:    movl    #0x6128BD5,(r10)+   ; tstl (r11)+; bneq .+6
    movw    #0x9F17,(r10)+      ; jmp @#...
    movl    r10,-(r11)
    addl2   #4,r10
    movl    #Mrkif,-(r11)       ; Mark the control structure
    rsb

;
; "else"
;
else2:  .long   if2,else1
    .word   0,Priority
    .asciz  "else"
else1:  cmpl    #Mrkif,(r11)+       ; Check for matching 'if'
    bneq    else3
    movw    #0x9F17,(r10)+      ; jmp @#...
    movl    r10,r0
    addl2   #4,r10          ; Leave room for the jump address
    movl    r10,@(r11)+     ; Have 'false' branch here
    movl    r0,-(r11)       ; Put our fill-in addr.
    movl    #Mrkif,-(r11)       ;  and put back the marker
    rsb
else3:  movl    #else4,r0       ; Complain
    jsb prstr
    jbr abort
else4:  .asciz  " 'else' does not match an 'if'\n"

;
; endif--finish off the conditional
;
endif2: .long   else2,endif1
    .word   0,Priority
    .asciz  "endif"
endif1: cmpl    (r11)+,#Mrkif       ; Check match
    bneq    endif3
    movl    r10,@(r11)+
    rsb
endif3: movl    #endif4,r0      ; Complain on no match
    jsb prstr
    jbr abort
endif4: .asciz  " 'endif' does not match 'else'/'if'\n"

;
; begin--start of all looping conditionals
;
beg2:   .long   endif2,beg1
    .word   0,Priority
    .asciz  "begin"
beg1:   movl    r10,-(r11)      ; Save current address
    cvtbl   #Mrkbegin,-(r11)    ;  and control structure marker
    rsb

;
; "while".."repeat" looping construct
;
while4: .asciz  "'while' does not match a 'begin'\n"
while2: .long   beg2,while1
    .word   0,Priority
    .asciz  "while"
while1: cmpl    #Mrkbegin,(r11)+    ; Check match
    bneq    while3
    movl    #0x6128BD5,(r10)+   ; tstl (r11)+; bequ @#<forward>
    movw    #0x9F17,(r10)+
    movl    r10,-(r11)      ; Mark where to plug in
    addl2   #4,r10          ; Leave room for the patch
    movl    #Mrkwhile,-(r11)
    rsb
while3: movl    #while4,r0      ; Bad match, complain
    jsb prstr
    jbr abort

rep4:   .asciz  "'repeat' does not match a 'while'\n"
rep2:   .long   while2,rep1
    .word   0,Priority
    .asciz  "repeat"
rep1:   cmpl    #Mrkwhile,(r11)+    ; Check match
    bneq    rep3
    movl    (r11)+,r0       ; Save where to patch
    movw    #0x9F17,(r10)+      ; jmp @#<back>
    movl    (r11)+,(r10)+
    movl    r10,(r0)        ; Backpatch
    rsb
rep3:   movl    #rep4,r0        ; Complain
    jsb prstr
    jbr abort

;
; again--unconditional back branch
;
again4: .asciz  "'again' does not match with a 'begin'\n"
again2: .long   rep2,again1
    .word   0,Priority
    .asciz  "again"
again1: cmpl    #Mrkbegin,(r11)+    ; verify match of control structures
    bnequ   again3
    movw    #Again_header,(r10)+    ; compile in back branch
    movl    (r11)+,(r10)+
    rsb
again3: movl    #again4,r0      ; Complain
    jsb prstr
    jbr abort

;
; until--loop until condition becomes true
;
until4: .asciz  "'until' doesn not match a 'begin'\n"
until2: .long   again2,until1
    .word   0,Priority
    .asciz  "until"
until1: cmpl    #Mrkbegin,(r11)+    ; Verify match
    bnequ   until3
    movl    #Skipt,(r10)+       ; Branch over backbranch if true
    movw    #Again_header,(r10)+    ; compile in backbranch
    movl    (r11)+,(r10)+
    rsb
until3: movl    #until4,r0      ; Complain
    jsb prstr
    jbr abort

;
; leave--setup innermost loop so it will exit at next iteration
;
leave2: .long   until2,leave1
    .word   4,Primitive
    .asciz  "leave"
leave1: movl    (sp),4(sp)
    rsb

;
; "k"--return index of third loop
;
k_idx2: .long   leave2,k_idx1
    .word   4,Primitive
    .asciz  "k"
k_idx1: movl    20(sp),-(r11)
    rsb

;
; "j"--return index of second loop
;
j_idx2: .long   k_idx2,j_idx1
    .word   4,Primitive
    .asciz  "j"
j_idx1: movl    12(sp),-(r11)
    rsb

;
; "i"--return index of innermost loop
;
i_idx2: .long   j_idx2,i_idx1
    .word   4,Primitive
    .asciz  "i"
i_idx1: movl    4(sp),-(r11)
    rsb

;
; "do"--start a loop
;
    .set    XDo1,0xD07E8BD0 ; movl (r11)+,-(sp); movl (r11)+,-(sp)
    .set    XDo2,0x7E8B

    .set    XDo3,0xD0508ED0 ; movl (sp)+,r0; movl (sp)+,r1
    .set    XDo4,0x51D1518E ;   cmpl r1,r0; blss .+6
    .set    XDo5,0x17061950 ;   jmp @#<forward>
    .set    XDo6,0x9F

    .set    XDo7,0xD07E51D0 ; movl r1,-(sp); movl r1,-(sp)
    .set    XDo8,0x7E50

do2:    .long   i_idx2,do1
    .word   0,Priority
    .asciz  "do"
do1:    movl    #XDo1,(r10)+
    movw    #XDo2,(r10)+
    movl    r10,-(r11)  ; Save current pos. for back branch
    movl    #XDo3,(r10)+
    movl    #XDo4,(r10)+
    movl    #XDo5,(r10)+
    movb    #XDo6,(r10)+
    movl    r10,-(r11)  ; Save this loc for fill-in as forward branch
    addl2   #4,r10
    movl    #XDo7,(r10)+
    movw    #XDo8,(r10)+

    movl    #Mrkdo,-(r11)   ; Flag our control structure
    rsb

;
; loop--branch back to the opening "DO"
;
    .set    XLoop1,0x1704AED6   ; incl 4(sp); jmp @#<back>
    .set    XLoop2,0x9F
loop3:  .asciz  "'loop' does not match a 'do'\n"
loop2:  .long   do2,loop1
    .word   0,Priority
    .asciz  "loop"
loop1:  cmpl    #Mrkdo,(r11)+   ; Check for match of control structures
    bnequ   loop4
    movl    (r11)+,r0   ; Keep where to fill in forward branch addr.
    movl    #XLoop1,(r10)+  ; Build code to increment loop
    movb    #XLoop2,(r10)+
    movl    (r11)+,(r10)+
    movl    r10,(r0)    ; Fill in this location as loop exit addr.
    rsb
loop4:  movl    #loop3,r0   ; Bad match--complain
    jsb prstr
    jbr abort

;
; +loop--like loop, but add by the top item instead of 1
;
    .set    XLoop1,0x4AE8BC0        ; incl 4(sp); jmp @#<back>
    .set    XLoop2,0x9F17
poop3:  .asciz  "'+loop' does not match a 'do'\n"
poop2:  .long   loop2,poop1
    .word   0,Priority
    .asciz  "+loop"
poop1:  cmpl    #Mrkdo,(r11)+   ; Check for match of control structures
    bnequ   poop4
    movl    (r11)+,r0   ; Keep where to fill in forward branch addr.
    movl    #XLoop1,(r10)+  ; Build code to increment loop
    movw    #XLoop2,(r10)+
    movl    (r11)+,(r10)+
    movl    r10,(r0)    ; Fill in this location as loop exit addr.
    rsb
poop4:  movl    #poop3,r0   ; Bad match--complain
    jsb prstr
    jbr abort

;
; "@"--fetch the contents of the addressed word
;
fetch2: .long   poop2,fetch1
    .word   4,Primitive
    .asciz  "@"
fetch1: movl    @(r11),(r11)
    rsb

;
; "!"--store the word (second) to address (top)
;
store2: .long   fetch2,store1
    .word   6,Primitive
    .asciz  "!"
store1: movl    (r11)+,r0
    movl    (r11)+,(r0)
    rsb

;
; "variable"--build a variable
;
    .set    XVar1,0x8FD0        ; movl #<addr>,-(r11)
    .set    XVar2,0x7B
var2:   .long   store2,var1,0
    .asciz  "variable"
var1:   jsb getw            ; Build the header
    movl    r8,r2           ; Add this word to the chain
    movl    r10,r8
    movl    r2,(r10)+
    movl    r10,r0          ; Save this position (PFA)
    clrl    (r10)+
    cvtbw   #7,(r10)+       ; SFP = 7
    cvtbw   #Primitive,(r10)+   ; SFA = "primitive"
    movl    #wrd,r1         ; Now copy the name in
var3:   movb    (r1)+,(r10)
    tstb    (r10)+
    bnequ   var3
    movl    r10,(r0)        ; Update the PFA
    movw    #XVar1,(r10)+       ; Our in-line code
    addl3   #6,r10,(r10)+
    movb    #XVar2,(r10)+
    movb    #rsb_header,(r10)+
    clrl    (r10)+          ; The first word of space (= 0)
    rsb

;
; "constant"--build a constant value
;
const2: .long   var2,const1,0
    .asciz  "constant"
const1: jsb getw            ; Build the header
    movl    r8,r2           ; Add this word to the chain
    movl    r10,r8
    movl    r2,(r10)+
    movl    r10,r0          ; Save this position (PFA)
    clrl    (r10)+
    cvtbw   #7,(r10)+       ; SFP = 7
    cvtbw   #Primitive,(r10)+   ; SFA = "primitive"
    movl    #wrd,r1         ; Now copy the name in
const3: movb    (r1)+,(r10)
    tstb    (r10)+
    bnequ   const3
    movl    r10,(r0)        ; Update the PFA
    movw    #XVar1,(r10)+       ; Our in-line code
    movl    (r11)+,(r10)+       ; the value to push
    movb    #XVar2,(r10)+
    movb    #rsb_header,(r10)+
    rsb


;
; ":"--start a colon definition
;
colon2: .long   const2,colon1,0
    .asciz  ":"
colon1: cvtbl   #1,state        ; Set our state to "compile"
    jsb getw            ; Get the name of the new word
    movl    r8,r2           ; Add this word to the chain
    movl    r10,r8
    movl    r2,(r10)+
    movl    r10,r0          ; Save this position (PFA)
    clrl    (r10)+
    clrw    (r10)+          ; SFP = 0
    cvtbw   #XSmudged,(r10)+        ; SFA = "smudged"
    movl    #wrd,r1         ; Now copy the name in
colon3: movb    (r1)+,(r10)
    tstb    (r10)+
    bnequ   colon3
    movl    r10,(r0)        ; Finally, update the PFA
    movl    #Mrkcolon,-(r11)    ; and leave our mark on the stack
    rsb

;
; ";"--end compile mode
;
semi4:  .asciz  "; not matched to ':'\n"
semi2:  .long   colon2,semi1
    .word   0,Priority
    .asciz  ";"
semi1:  clrl    state           ; Reset compile state
    cmpl    #Mrkcolon,(r11)+    ; Check the mark
    beql    semi3           ;  Uh-oh, bad match
    movl    #semi4,r0       ; Complain
    jsb prstr
    rsb
semi3:  clrw    10(r8)      ; All OK, so clear the smudge
    movb    #rsb_header,(r10)+ ; Add the closing RSB
    rsb

;
; "mod"--get remainder of division
;
mod2:   .long   semi2,mod1,0
    .asciz  "mod"
mod1:   movl    (r11)+,r0
    movl    (r11),r2
    clrl    r3
    ediv    r0,r2,r2,(r11)
    rsb

;
; "/"--divide second by top
;
div2:   .long   mod2,div1
    .word   3,Primitive
    .asciz  "/"
div1:   divl2   (r11)+,(r11)
    rsb

;
; "*"--multiply top two items on stack
;
mul2:   .long   div2,mul1
    .word   3,Primitive
    .asciz  "*"
mul1:   mull2   (r11)+,(r11)
    rsb

;
; "-"--subtract top two integers, push result
;
minus2: .long   mul2,minus1
    .word   3,Primitive
    .asciz  "-"
minus1: subl2   (r11)+,(r11)
    rsb

;
; "f+"--add floating
;
fplus2: .long   minus2,fplus1
    .word   3,Primitive
    .asciz  "f+"
fplus1: addf2   (r11)+,(r11)
    rsb

;
; "f-"--subtract floating
;
fminus2:
    .long   fplus2,fminus1
    .word   3,Primitive
    .asciz  "f-"
fminus1:
    subf2   (r11)+,(r11)
    rsb

;
; "f*"--multiply floating
;
fmul2:  .long   fminus2,fmul1
    .word   3,Primitive
    .asciz  "f*"
fmul1:  mulf2   (r11)+,(r11)
    rsb

;
; "f/"--divide floating
;
fdiv2:  .long   fmul2,fdiv1
    .word   3,Primitive
    .asciz  "f/"
fdiv1:  divf2   (r11)+,(r11)
    rsb

;
; "i->f"--convert int to float
;
i2f2:   .long   fdiv2,i2f1
    .word   3,Primitive
    .asciz  "i->f"
i2f1:   cvtlf   (r11),(r11)
    rsb

;
; "f->i"--convert float to int
;
f2i2:   .long   i2f2,f2i1
    .word   3,Primitive
    .asciz  "f->i"
f2i1:   cvtfl   (r11),(r11)
    rsb

;
; "+"--add top two integers, push result back to stack
;
plus2:  .long   f2i2,plus1
    .word   3,Primitive
    .asciz  "+"
plus1:  addl2   (r11)+,(r11)
    rsb

;
; emit--print the specified character
;
emit5:  .space  1
emit3:  .long   3
emit4:  .space  4
    .long   emit5,1
emit2:  .long   plus2,emit1,0
    .asciz  "emit"
emit1:  cvtlb   (r11)+,emit5        ; Put the desired char into the buffer
    movl    #emit3,ap       ; Print the buffer
    movl    ounit,emit4
    chmk    #4
    rsb

;
; cr--print newline
;
cr5:    .asciz  "\n"
cr3:    .long   3
cr4:    .space  4
    .long   cr5,1
cr2:    .long   emit2,cr1,0
    .asciz  "cr"
cr1:    movl    #cr3,ap
    movl    ounit,cr4
    chmk    #4
    rsb

;
; "f."--print a floating point number
;
fprbuf: .space  10          ; Output buffer for fractional part

fprn2:  .long   cr2,fprn1,0
    .asciz  "f."
fprn1:  movf    (r11),r2        ; Handle negative numbers
    cmpf    r2,#0.0     ; If it's negative...
    bgeq    fprn9
    movl    #fprbuf,r0      ;  Print a '-'
    movl    r0,r1
    movb    #'-',(r1)+
    clrb    (r1)
    jsb prstr
    mnegf   (r11),(r11)     ;  And negate it
fprn9:  cvtfl   (r11),-(r11)        ; Dup the number for "."
    jsb prnum1
    movl    #fprbuf,r3      ; R3 points to buffer position
    movf    (r11)+,r0       ; Get the number
    cvtfl   r0,r1           ; Get the integer part
    cvtlf   r1,r1
    subf2   r1,r0           ; And take it off the number
    movb    #'.',(r3)+      ; The decimal point
    cvtbl   #6,r4           ; We always print 6 places

fprn3:  mulf2   #10.0,r0        ; Get the next digit
    cvtfl   r0,r1           ; R1 is the next digit
    cvtlf   r1,r5           ; Take this digit off the number
    subf2   r5,r0
    cvtlb   r1,r1           ; Turn it into the ASCII byte
    addb3   #'0',r1,(r3)+
    sobgtr  r4,fprn3        ; Loop 6 times

    clrb    (r3)
    movl    #fprbuf,r0      ; Now print it
    jsb prstr

    rsb

;
; ." --if compiling, generate code to print a string, otherwise just
;   print the string
;
dotqbuf:
    .space  133
dotq2:  .long   fprn2,dotq1
    .word   0,Priority
    .byte   '.','"', 0
    
dotq1:  movl    #dotqbuf,r1
    cmpb    (r9),#32    ; Skip char if it's the separating blank
    bneq    dotq7
    incl    r9
dotq7:  movb    (r9)+,r0    ; get the next char of the string
    cmpb    #'"',r0     ; End string on newline or '"'
    beql    dotq4
    cmpb    #10,r0
    beql    dotq4
    tstb    r0      ; At end of current input buffer?
    beql    dotq5
    movb    r0,(r1)+    ;  No. Add this char to our output line
    brb dotq7
dotq5:  jsb getlin      ;  Yes. Get another buffer
    brb dotq7

dotq4:  clrb    (r1)        ; Make the resulting string NULL-terminated
    movl    #dotqbuf,r0 ; Point R0 to head of this string
    tstl    @#state     ; Check state
    beql    dotq3

    movw    #jsb_header,(r10)+ ; Compile in reference to (.")
    movl    #pdotq1,(r10)+
dotq6:  movb    (r0)+,(r10)+    ; Copy in the string
    bneq    dotq6
    rsb

dotq3:  jsb prstr       ; Print the string
    rsb

;
; (.")--run-time code to print a string
;
pdotq2: .long   dotq2,pdotq1,0
    .byte    '(','.', '"',')', 0
pdotq1: movl    (sp)+,r0    ; Get the address of our return loc.
    jsb prstr       ; Print the string
    pushl   r2      ; Return to addr following string
    rsb

;
; "."--pop and print the top number on the stack
;
    .space  14          ; Null-terminated string buffer
prnbuf: .byte   0
prnum2: .long   pdotq2,prnum1,0
    .asciz  "."
prnum1: movl    base,r5         ; Get the base
    movl    (r11)+,r0       ; R0 holds the number
    movl    #prnbuf,r1      ; R1 points to the char positions
    movl    r0,r2           ; Keep a copy to do the sign
    tstl    r0          ; Negate if negative
    bgeq    prnum3
    mnegl   r0,r0
prnum3: divl3   r5,r0,r3        ; R3 holds new number
    mull3   r5,r3,r4        ; Calculate remainder the hard way
    subl3   r4,r0,r4
    cmpl    r4,#9           ; See if it's a HEX digit
    bleq    prnu5
    .set a_offset 'a'-10
    addb3   #a_offset,r4,-(r1)
    brb prnu6
prnu5:  addb3   #'0',r4,-(r1)       ; Put it in as the next digit
prnu6:  movl    r3,r0           ; Update number
    tstl    r0
    bnequ   prnum3
    tstl    r2          ; Now check sign
    bgeq    prnum4
    movb    #'-',-(r1)
prnum4: movl    r1,r0           ; print the number
    jsb prstr
    rsb

;
; sin & cos (and the corresponding fsin & fcos)
;
sintab:
    .long 0, 174, 348, 523, 697, 871, 1045, 1218, 1391, 1564, 1736
    .long 1908, 2079, 2249, 2419, 2588, 2756, 2923, 3090, 3255, 3420
    .long 3583, 3746, 3907, 4067, 4226, 4383, 4539, 4694, 4848, 5000
    .long 5150, 5299, 5446, 5591, 5735, 5877, 6018, 6156, 6293, 6427
    .long 6560, 6691, 6819, 6946, 7071, 7193, 7313, 7431, 7547, 7660
    .long 7771, 7880, 7986, 8090, 8191, 8290, 8386, 8480, 8571, 8660
    .long 8746, 8829, 8910, 8987, 9063, 9135, 9205, 9271, 9335, 9396
    .long 9455, 9510, 9563, 9612, 9659, 9702, 9743, 9781, 9816, 9848
    .long 9876, 9902, 9925, 9945, 9961, 9975, 9986, 9993, 9998, 10000

sin2:   .long   prnum2,sin1,0
    .asciz  "sin"
sin1:   movl    (r11)+,r0       ; Get angle
    clrl    r1          ; Negative quadrant flag
sin3:   tstl    r0          ; Fold negative angles
    bgeq    sin4
    addl2   #360,r0
    brb sin3
sin4:   cmpl    r0,#360         ; Fold angles > 360
    blss    sin5
    subl2   #360,r0
    brb sin4
sin5:   cmpl    r0,#181         ; Flag & fold negative quadrant vals
    blss    sin6
    movb    #-1,r1
    subl3   r0,#360,r0
sin6:   cmpl    r0,#91          ; Fold equivalent 2nd quadrant
    blss    sin7
    subl3   r0,#180,r0
sin7:   movl    sintab[r0],r0       ; Get the value
    tstl    r1          ; Negate if needed
    beql    sin8
    mnegl   r0,r0
sin8:   movl    r0,-(r11)       ; Push result
    rsb

cos2:   .long   sin2,cos1,0
    .asciz  "cos"
cos1:   subl3   (r11),#90,(r11)     ; sin(90-a) = cos(a)
    jsb sin1
    rsb

fsin2:  .long   cos2,fsin1,0
    .asciz  "fsin"
fsin1:  cvtfl   (r11),(r11)     ; Change to int & call sin
    jsb sin1
    cvtlf   (r11),r0
    divf3   #10000.0,r0,(r11)   ; Scale down to true float
    rsb

fcos2:  .long   fsin2,fcos1,0
    .asciz  "fcos"
fcos1:  cvtfl   (r11),(r11)     ; Change to int & call sin
    jsb cos1
    cvtlf   (r11),r0
    divf3   #10000.0,r0,(r11)   ; Scale down to true float
    rsb

;
; decimal--set FORTH's base to decimal
;
decim2: .long   fcos2,decim1,0
    .asciz  "decimal"
decim1: cvtbl   #10,base
    rsb

;
; hex--set FORTH's base to hexadecimal
;
hex2:   .long   decim2,hex1,0
    .asciz  "hex"
hex1:   cvtbl   #16,base
    rsb

;
; BASE variable--holds the current base
;
base2:  .long   hex2,base1,0
    .asciz  "base"
base1:  movl    #base,-(r11)
    rsb
base:   .long   10

;
; STATE variable--0=interp, 1=compiling
;
state2: .long   base2,state1,0
    .asciz  "state"
state1: movl    #state,-(r11)
    rsb
state:  .long   0

;
; isdig--return whether the first character in the current word is
;   a numeric digit (watch out for HEX!)
;
isdig:  movb    (r7),r3         ; Put the char in question into R3
    cmpb    r3,#48          ; Check for 0..9
    blss    isdig1
    cmpb    r3,#58
    blss    isdig2
    movl    r6,r4           ; The base comes into us in R6
    cmpl    r4,#11          ; For higher bases, check A..?
    blss    isdig1
    addl2   #54,r4          ; Change the base into the highest char
    cmpb    r3,#97          ; Map a..? to A..?
    blss    isdig3
    subb2   #32,r3
isdig3: cmpb    r3,#65          ; Check against 'A'
    blss    isdig1
    cmpb    r4,r3           ; Check against highest char
    blss    isdig1
    brb isdig2

isdig1: clrb    r3          ; KLUDGE to return NZ
    decb    r3
    rsb

isdig2: clrb    r3          ; Likewise for Z
    tstb    r3
    rsb

interp6: .asciz " ?Stack empty\n"
interp1:
    .long   state2,interp,0
    .asciz  "interp"
interp: cmpl    r11,stacklim        ; Check for underflow
    bleq    interp5
    movl    #interp6,r0     ; Underflowed. Complain & abort
    jsb prstr
    jbr abort
interp5:
    jsb getw            ; Get next word
    jsb lookup          ; In the dictionary?
    bneq    cknum           ;  No, see if it's a number
    tstb    state           ; Yes, either compile or execute
    bneq    interp2
interp4:
    jsb (r0)            ; execute via its address
    brb interp
interp2:
    bitl    #Priority,r1        ; See if it's immediate
    jnequ   interp4
    bitl    #Primitive,r1       ; See if it generates in-line code
    bnequ   interp7
    movw    #jsb_header,(r10)+  ; compile it with a "jsb" header
    movl    r0,(r10)+
    jbr interp 
interp7:
    cvtwl   8(r2),r1        ; Get number of bytes in def.
interp8:
    movb    (r0)+,(r10)+        ; Copy bytes of insructions
    decl    r1          ; See if done
    bnequ   interp8
    jbr interp

sign:   .space  1           ; Flags the sign
cknum:  movl    #wrd,r7         ; R7 is our index to the line
    clrb    sign            ; Take care of negative ;'s here
    cmpb    (r7),#'-'
    bneq    cknu1
    movb    #-1,sign
    incl    r7
cknu1:  movl    base,r6         ; Keep base in R6
    jsb isdig           ; Is this a number?
    jneq    badwrd          ;  No, complain

    clrl    r1
ckn1:   cvtbl   (r7)+,r0        ; Loop. Get next digit
    subl2   #'0',r0
    cmpl    r0,#10          ; Fix things up for HEX
    blss    ckn2
    subl2   #17,r0
    cmpl    r0,#6
    blss    ckn8            ; Turn R0 into the hex value
    subl2   #32,r0
ckn8:   addl2   #10,r0
ckn2:   mull2   r6,r1           ; Scale up R1, add in R0
    addl2   r0,r1
    jsb isdig           ; Loop if have more chars
    
    bneq    _1001
    jmp     ckn1
_1001:

    cmpb    #'.',(r7)+      ; If has decimal point, is floating pt.
    bneq    ckn4
    cvtlf   r1,r1
    movf    #0.1,r0     ; R0 is our scaling factor
ckn5:   jsb isdig           ; See if more digits
    bneq    ckn6
    subb3   #48,(r7)+,r2        ; Get next digit, convert to float num
    cvtbf   r2,r2
    mulf2   r0,r2           ; Scale by current factor
    addf2   r2,r1           ; Add it in to the current number
    divf2   #10.0,r0        ; Move our factor down one place
    brb ckn5
ckn6:   tstb    sign            ; Do negation if needed
    beql    cknu2
    mnegf   r1,r1
    brb cknu2

ckn4:   tstb    sign            ; negate if it started with '-'
    beql    cknu2
    mnegl   r1,r1

cknu2:  tstb    state           ; Compile or push this number
    .jneq   ckn3
    movl    r1,-(r11)
    jbr interp
ckn3:   movw    #lit_header,(r10)+  ; pushl #...
    movl    r1,(r10)+
    movb    #lit_tailer,(r10)+
    jbr interp

;
; badwrd--print the offending word, then call abort to restart the
;   interpreter.
;
dunno:  .asciz  ": not found\n"
badwrd: movl    #wrd,r0         ; First print the offending word
    jsb prstr
    movl    #dunno,r0       ; then, ": not found"
    jsb prstr
    jbr abort

;
; prstr--print the null-terminated string pointed to by r0 on STDOUT
;
wrprm:  .long   3           ; Parm block for WRITE syscall
wrunit: .space  4   ; Output unit
wradr:  .space  4   ; BufAddr
wrcnt:  .space  4   ; Nbytes

prstr:  movl    ounit,wrunit        ; Set the output descriptor
    clrl    r1          ; Count the bytes -> R1
    movl    r0,wradr
prst1:  tstb    (r0)+
    .jeql   prst2
    incl    r1
    jbr prst1
prst2:  movl    r0,r2           ; Make next open addr. available in R2
    movl    r1,wrcnt
    movl    #wrprm,ap       ; Now do the syscall
    chmk    #4
    rsb

;
; lookup--take the current word in "wrd" and see if it's in the dictionary
;   chain. If it is, return with address in R0 and Z; otherwise
;   return with NZ. If it is found, R1 will contain the SF.
;
lookup: movl    #wrd,r0         ; R0 -> word
    movl    r8,r1           ; R1 -> next entry to check against
look1:  addl3   #12,r1,r2       ; R2 -> cur entry's name
    movl    r0,r3           ; R3 -> our word
    bitw    #XSmudged,10(r1)        ; XSmudged?
    bnequ   look3

look2:  cmpb    (r3)+,(r2)      ; Compare the names
    bnequ   look3           ;  they didn't match
    tstb    (r2)+           ; They did; at end of names?
    bnequ   look2           ; No, keep going

    movl    4(r1),r0        ; We have a match. R0 -> entry
    movl    r1,r2           ; R2 -> top of entry
    cvtwl   10(r1),r1       ; R1 = (SFA)
    clrb    r3          ; Return Z
    tstb    r3
    rsb
look3:  movl    (r1),r1         ; Move to next entry
    tstl    r1
    bnequ   look1
    clrb    r0          ; No match, return NZ
    decb    r0
    rsb

;
; iswhite--return whether the character pointed to by R9 is a white
;   space character
;
iswhite:
    movb    (r9),r3         ; Keep this char in register
    cmpb    #Tab,r3     ; Tab
    jeql    iswh1
    cmpb    #Spc,r3     ; Space
    jeql    iswh1
    cmpb    #NL,r3      ; Newline
    jeql    iswh1
    tstb    r3      ; NULL
iswh1:  rsb

;
; getlin--read another line of input from the current input file descriptor.
;   Note that we do some fancy things here to allow either a file or a TTY
;   to be read equivalently (and with reasonable efficiency). Namely,
;   installing NULLS at the end of buffers, and reading (potentially) a
;   full disk block from the input file descriptor.
;
rdprm:  .long   3
rdunit: .space  4
    .long   inline,1024
prompt: .asciz  "> "
getlin: movl    iunit,r0        ; Get the input unit, put it in the
    movl    r0,rdunit       ;  the read area, prompt if ==0
    tstl    r0
    bneq    getl2
    movl    #prompt,r0
    jsb prstr
getl2:  movl    #rdprm,ap       ; Read a block
    chmk    #3
    tstl    r0          ; Test for EOF
    .jeql   getl1
    clrb    inline(r0)      ; Terminate the buffer with NULL
    movl    #inline,r9      ; Set the input line pointer
    rsb

getl1:  decl    ideep       ; Decrement nesting depth count
    movl    #256,r2     ; R2 is the number of bytes to move
    movl    ideep,r0
    mull2   #1024,r0
    addl2   #ibufs,r0   ; R0 now points to our save location
    movl    #inline,r1  ; R1 points to the buffer to restore
getl3:  movl    (r0)+,(r1)+ ; Move the bytes
    sobgtr  r2,getl3
    movl    ideep,r0    ; Now save the input index
    movl    ibufx[r0],r9

    movl    iunit,outp3     ; EOF--Close the unit
    movl    #outp4,ap
    chmk    #6
    movl    isp,r0          ; If we're not at top, pop item
    cmpl    r0,#istk
    .jeql   exit            ; If at top, forth exits
    subl2   #4,r0
    movl    r0,isp
    movl    (r0),iunit
    rsb             ; Return with the restored input buffer

;
; getw--get the next word in the current input line. If there are no
;   more words in this line, get another from the input
;
getw:   jsb iswhite         ; Skip initial white space
    bnequ   getw1
    tstb    (r9)+           ; Is white. If NULL, need new line
    bnequ   getw
    jsb getlin
    brb getw
getw1:  movl    #wrd,r0         ; Found word. Copy into "wrd"
getw2:  movb    (r9)+,(r0)+
getw4:  jsb iswhite
    bnequ   getw2
    tstb    (r9)            ; Read new buffer if at end
    bneq    getw5
    pushl   r0          ; Save R0, then call "getlin"
    jsb getlin
    movl    (sp)+,r0
    brb getw4
getw5:  clrb    (r0)            ; add NULL at end of word
    rsb
dictend:    .long   exe$forth_dict  ; Initially here
exe$forth_dict:
    .space  30000           ; Dictionary space

;
;  Startup 
;

	.entry exe$forth_init
	pushal @#_msg
	calls #1,@#exe$forth
        clrl r0
	ret
_msg:	.ascid ' ." Forth initialized..." cr'

    .console clear sym/temp
    .console set radix hex
;    .region p0
    
