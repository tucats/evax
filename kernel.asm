;
;       MicroKernel OS for VAX.
;
;       This is used to support development and testing of VAX programs.
;       It is not a full OS but provides minimal support for basic functions
;       like writing output to the console
;
;
;       SERVICES SUPPORTED
;
;       The microkernel supports a small (but growing!) list of basic VMS
;       services.  These include some kernel-mode operations such as
;       console I/O, some user-mode operations like str*() runtime library
;       support, and some "shim" operations that are supported by the 
;       emulator in lieu of a runtime library, such as the malloc() and
;       related routines.
;
;
;       NATIVE VERSUS VAX CONSOLE
;
;       Most console commands are implemented natively, in the actual emulator
;       code itself, and outside the emulated VAX.  However, some console
;       commands can be written in VAX assembler directly.  These commands
;       are identified by the /ENTRY= qualifier in the evax.dcl grammar
;       definition file.  Commands with an /ENTRY case the associated entry
;       point in the microkernel to be called when the command is given.  A
;       set of services (DCL$PRESENT, DCL$STRING, etc.) can be used to determine
;       if a parameter, qualifier, or keyword value is present, negated, or
;       what it's string or numeric value is.
;
;
;       HOW TO ADD A USER-MODE ROUTINE
;
;       User mode routines don't require special manipulation of the 
;       processor or use of privileged memory, instructions, etc.  There
;       is a section below for LIB$ and DECC$ support routines.  Simply
;       write the entry point as a normal assembler routine.
;
;       If you need the runtime to be available to a native VAX/VMS image
;       that you plan to run, add an entry in the _second_ section that
;       contains .SHIM declarations.  These declarations create bindings
;       that the image activator uses to link calls to sharable images to
;       your code instead.  Routines that are written as native VAX code
;       (such as DECC$STRCPY, for example) have a shim dispatch code of
;       zero.
;
;
;       HOW TO ADD A SHIM ROUTINE
;
;       A SHIM routine is one that is not written in native VAX code at
;       all.  Instead, a stub (shim) is created by the pseudo-assembler
;       that generates an appropriate XFC instruction.  This instruction
;       causes the emulator to read the native VAX argument list and
;       dispatch to a runtime support routine written in the emulator
;       itself.  An example of this is DECC$MALLOC(), which is implemented
;       by the routine decc_malloc() located in the file librtl_memory.c
;
;       You must write the shim routine itself (see any of the librtl*.c
;       files for how to read the argument list, access string descriptors
;       easily, etc.).  Add a prototype for the runtime in shim.h, and
;       an entry in the shim dispatch table in "shim.c".  Note that there
;       is a table entry for each routine, plus a second call that at runtime
;       fills in the function pointer value.  You must code both parts.
;
;       Finally, go to the _first_ section containing .SHIM declarations
;       below and add an entry for your routine.  The second parameter
;       must be the index into the shim table that contains your routine.
;
;
;       HOW TO ADD A NEW KERNEL-mode SERVICE
;
;       Services have two parts, the user mode part and the kernel mode
;       part.  The user mode part should validate that the arguments are
;       valid for user mode (to prevent calling with Kernel addresses,
;       for example) and otherwise check the arguments for correctness.
;       Note that for some services (lib$format_dec, for example) the
;       entire service runs in user mode and requires no system service.
;
;       When it's time to run the portion(s) of the service that must
;       run in kernel mode, write the routine as a function.  You must
;       assume that the user mode part will put it's arguments in 
;       registers for the call.  By convention, R5 is used for the
;       argument or the pointer to the arguments as appropriate.
;
;       The function should return any information it needs to via
;       the argument list by address, and a return code in R0.
;
;       Place the address of the kernel handler in the EXE$TABLE
;       below.  The position in the table must match the kernel mode
;       selector that invokes it.
;

;       Indicate that we are building the microkernel.  This enables a number
;       of pseudo directives, etc. and tells the console it can use commands
;       like RUN that depend on the microkernel.

                .microkernel

;       Build the P1 system service vector to support VMS images

                .p1vector
                
;
;       We must have the system return codes defined for us

                .if defined( "SS$_NORMAL") = 0  .include       "ssdef.asm"
                
;       Note that this can only be built if we are in kernel mode.  The
;       system initializes in kernel mode at IPL 31 to prevent interrupts,
;       etc. from occuring.  We assume this state for the system to work
;       correctly.

                .region         system
exe$base:       .byte 0


;--------------------------------------------------------------------
;   CONSOLE TRANSMIT INTERRUPT HANDLER
;--------------------------------------------------------------------


                .align          8
exe$tx:         movl            #1, @#exe$tx_ready
                rei


;--------------------------------------------------------------------
;   CONSOLE RECIEVE INTERRUPT HANDLER
;--------------------------------------------------------------------


                .align          8
                
exe$rx:         pushl           r0
                pushl           r1
                mfpr            #VAX$PR_RXDB, -(sp)
                calls           #1, @#EXE$RX_GET
                movl            (sp)+, r1
                movl            (sp)+, r0

                rei


;--------------------------------------------------------------------
;   CHMK EXCEPTION HANDLER
;--------------------------------------------------------------------

                .align          8

;       Turn the exception into a call.  This lets us use registers
;       much more easily.  The #2 makes the stack a two-element arg
;       list.  When done with the call, we must discard the #1 and
;       the PSL, leaving just the PC for the REI.

exe$chmk:       movl            r0, @#exe$chmk_r0
                movl            r1, @#exe$chmk_r1
                pushl           ap          ; Save the AP at time of call
                pushl           #2
                callg           sp, @#exe$dispatch
                movl            @#exe$chmk_r1, r1
                moval           b^0x0C(sp), sp
                rei

;--------------------------------------------------------------------
;   ACCVIO EXCEPTION HANDLER
;--------------------------------------------------------------------

                .align          8

;       Turn the exception into a call.  Add the signal value, and
;       account for the fault addr, mode, PC, and PSL arguments.

exe$accvio:     pushl           #SS$_ACCVIO
                pushl           #5
                callg           sp, @#exe$signal
                moval           b^10(sp), sp
                moval           @#exe$halt, (sp)
                rei

;--------------------------------------------------------------------
;   RESERVED OPCODE EXCEPTION HANDLER
;--------------------------------------------------------------------

                .align          8

;       Turn the exception into a call.  Add the signal value, and
;       account for the PC, and PSL arguments.

exe$resop:      pushl           #SS$_ROPRAND
                pushl           #3
                callg           sp, @#exe$signal
                moval           b^0C(sp), sp
                moval           @#exe$halt, (sp)
                rei

;--------------------------------------------------------------------
;   PRIVILEGED INSTRUCTION EXCEPTION HANDLER
;--------------------------------------------------------------------

                .align          8

;       Turn the exception into a call.  Add the signal value, and
;       account for the PC, and PSL arguments.

exe$priv:       pushl           #SS$_NOPRIV
                pushl           #3
                callg           sp, @#exe$signal
                moval           b^0C(sp), sp
                moval           @#exe$halt, (sp)
                rei

;--------------------------------------------------------------------
;   SOFTWARE INTERRUPT 2 (AST HANDLER)
;--------------------------------------------------------------------

                .align          8

exe$deliver_ast:nop

_next:          remque          @#exe$ast_list, r0
                bvs             _done
                pushl           r0
                pushl           r1
                pushl           r0
                calls           #1, @#exe$handle_ast
                blbc            r0, _err
                movl            (sp)+, r1
                movl            (sp)+, r0
                brb             _next

;   Handle errors in ast services if needed, and then pop R1 and R0
;   before getting out.

_err:           movl            -(sp), r1
                movl            -(sp), r0

_done:          rei

;--------------------------------------------------------------------
;   RESERVED ADDRESSING MODE EXCEPTION HANDLER
;--------------------------------------------------------------------

                .align          8

;       Turn the exception into a call.  Add the signal value, and
;       account for the  PC, and PSL arguments.

exe$resaddr:    pushl           #SS$_RADRMOD
                pushl           #3
                callg           sp, @#exe$signal
                moval           b^0C(sp), sp
                moval           @#exe$halt, (sp)
                rei

;--------------------------------------------------------------------
;   EXCEPTIONS LAND HERE AFTER FINISHING HANDLER
;--------------------------------------------------------------------


exe$halt:       pushal          _haltmsg
                calls           #1, @#decc$printf
exe$silenthalt: xfc             #xfc$halt_silent    ; no fault halt
                halt            ; if you push it, it blows

_haltmsg:       .asciz          "\n%%MKHALT-I-HALT, microkernel halted\n"

;--------------------------------------------------------------------
;   INTERVAL TIMER HANDLER
;--------------------------------------------------------------------

                .align          8
exe$interval:   incl            @#exe$int_count
                pushl           r0                ; save R0
                mfpr            #VAX$PR_TODR,r0
                tstl		r0                ; if zero, no TODR update
                beql		_no_inc
                
                incl		r0
                mtpr		r0, #VAX$PR_TODR
                
_noinc:         mtpr            #0FF, #VAX$PR_ICCS
                movl            (sp)+,r0          ; restore R0
                rei

;--------------------------------------------------------------------
;   GENERAL SIGNAL HANDLER
;--------------------------------------------------------------------

;       This is called when a hardware or software exception occurs.
;       At the time of the call, a varying number of arguments are
;       on the stack.  The last two are always the PC and PSL where
;       the fault occurred.  The first is always the exception.  Any
;       in between make up the signal vector.

                .entry          exe$signal, ^m<r2,r3, r4>

                pushal          @#_sigmsg
                calls           #1, @#decc$printf

                movl            (ap), r2
                movl            #1,r4

                pushl		b^4(ap)
                calls           #1, exe$printmsg
                
                pushal          @#_sigmsg2
                calls           #1, @#decc$printf

_sigloop:       tstl            r2
                blss            _done
                movl            #8, @#exe$sig_buff_len
                pushl           (ap)+
                pushl           r4
                incl            r4
                pushal          _sigfmt
                calls           #3,decc$printf
                
                decl            r2
                brb             _sigloop
                
_done:          ret

_sigmsg:        .asciz          "%%MKTRAP-E-TRAP, the microkernel has trapped an error\n-MKTRAP-I-MSG, "
_sigfmt:        .asciz          "  %ld   %08lX\n"
_sigmsg2:       .asciz          " \n Signal vector:\n"


;--------------------------------------------------------------------
;   GENERAL MESSAGE TEXT PRINTING
;--------------------------------------------------------------------

;       This is called to convert a numeric text message code to a
;       string, and print it.  This is usually called from the
;       general error handler, but can be called from any user-mode
;       or higher code.
;
;       Messages are printed on the console with a trailing newline.
;       If the message is unknown, then it is formatted as a hex
;       number.
;


                .entry          exe$printmsg, ^m< r2, r3 >

                movl            b^4(ap), r2
                moval           @#exe$msgs, r3

_findmsg:       tstl            (r3)
                beql            _nomsg
                cmpl            (r3)+, r2
                beql            _print
                addl2           #4, r3
                brb             _findmsg       

_print:         pushl           (r3)
                calls           #1,decc$printf
                brb             _done

_nomsg:         pushl           r2
                pushal          _msgfmt
                calls           #2,decc$printf

_done:          pushal          _msgcr
                calls           #1, decc$printf
                movl            #SS$_NORMAL, r0
                ret

_msgfmt:        .asciz          "Unrecognized error %08lX"
_msgcr:         .asciz          "\n"



;--------------------------------------------------------------------
;   MESSAGE TABLE
;--------------------------------------------------------------------

;
;  Define the table of mappings of error codes to message texts
;  known to the kernel.  Note use of ".scope" which sets up a new
;  local symbol scope without creating an entry, etc.
;

                .align          4
                .scope          EXE$MSGS

                .long           SS$_NOPRIV,     _nopriv
                .long           SS$_NORMAL,     _normal
                .long           SS$_ACCVIO,     _accvio
                .long           SS$_ROPRAND,    _resop
                .long           SS$_RADRMOD,    _radrmod
                .long           SS$_INVARG,     _invarg
                .long           SS$_BUFFEROVF,  _bufferovf
                .long           0, 0

_bufferovf:   .asciz          "Buffer overflow"
_nopriv:      .asciz          "Privileged instruction fault"
_normal:      .asciz          "Normal successful completion"
_accvio:      .asciz          "Access violation"
_resop:       .asciz          "Reserved operation fault"
_radrmod:     .asciz          "Reserved addressing mode"
_invarg:      .asciz          "Invalid argument"


;--------------------------------------------------------------------
;   CHMK SELECTOR DISPATCHER
;--------------------------------------------------------------------

;       Here's the real dispatcher.  It validates the kernel selector
;       value, and if it's okay, generates a call to an address stored
;       in the exe$table array.  The first argument is the real AP for
;       the call, and the second argument is the dispatcher code.

                .entry          exe$dispatch, ^m<r2,r3>
                movl            b^8(ap), r2
                movl            b^4(ap), ap
                tstl            r2
                bgeq            _10
                movl            #SS$_INVARG, r0
                brb             exe$exit
_10:            cmpl            r2, @#exe$table_len
                blss            _20
                movl            #SS$_INVARG, r0
                brb             exe$exit
_20:            moval           @#exe$table, r3
                movl            (r3)[r2], r0
                
                callg           ap, (r0)

exe$exit:       ret

;--------------------------------------------------------------------
;   CHMK 0    WRITE BYTE TO CONSOLE
;--------------------------------------------------------------------

                .set            EXE$PUT_CONSOLE 0
                .entry          exe$$put_console

;       First, see if the device is ready or not.  This is set
;       by the ready interrupt service routine when a byte is
;       successsfully written.


_wait:          tstl            @#exe$tx_ready
                beql            _wait

;       Mark the device as busy, and write a byte to it.

                clrl            @#exe$tx_ready                              
                mtpr            r5, #VAX$PR_TXDB
                
                movl            #SS$_NORMAL, r0
                ret

;--------------------------------------------------------------------
;   CHMK 1    READ BYTE FROM CONSOLE
;--------------------------------------------------------------------

                .set            EXE$GET_CONSOLE 2
                .entry          exe$$get_console
                
                mfpr            #VAX$PR_RXDB, r0
                ret

;--------------------------------------------------------------------
;   CHMK 3    READ BUFFER FROM FILE
;--------------------------------------------------------------------

;       AP points to a legitimate argument block.
;
;           4(AP)   file id  (ignored for now, assume console)
;           8(AP)   address of buffer to write
;           12(AP)  length of buffer to write
;

                .set            EXE$GET_FILE 3
                .entry          exe$$get_file, ^m<r2>

                moval           b^0f0(sp),sp        ; Make automatic storage
                
                movl            b^08(ap),b^0FC(fp)  ; addr part of descriptor   
                movl            b^0c(ap),b^0F8(fp)  ; len  part of descriptor
                clrl            B^0f4(fp)           ; space to write length

                pushal          b^0f4(fp)           ; addr of length 
                pushl           #0                  ; no prompt
                pushal          b^0f8(fp)           ; addr of descriptor
                
                calls           #3, @#LIB$GET_INPUT
                
                movl            b^0f4(fp), r0       ; Get length
                movl            b^08(ap), r2        ; Get buffer addr
                clrb            (r2)[r0]            ; Null terminate it
                
                ret                                 ; And return length in R0

;--------------------------------------------------------------------
;   CHMK 4    WRITE BUFFER TO FILE
;--------------------------------------------------------------------

;       AP points to a legitimate argument block.
;
;           4(AP)   file id  (ignored for now, assume console)
;           8(AP)   address of buffer to write
;           12(AP)  length of buffer to write
;

                .set            EXE$PUT_FILE 4
                .entry          exe$$put_file
            
                pushl           b^08(ap)        ; addr part of descriptor   
                pushl           b^0c(AP)        ; len  part of descriptor
            
                pushl           sp              ; Make addr of descriptor on stack
                calls           #1, @#lib$put_one
                ret
                
;--------------------------------------------------------------------
;   CHMK 7    QUIT EMULATION
;--------------------------------------------------------------------

;       No arguments
;

                .set            EXE$QUIT_EMULATION 7
                .entry          exe$$quit_emulation
            
                xfc		#XFC$QUIT_EMULATION
                ret					; Really should never return.
                


;--------------------------------------------------------------------
;   CHMK SELECTOR FUNCTION DISPATCH TABLE
;--------------------------------------------------------------------

;       This is the dispatch table.  There must be a entry point
;       address in each slot that is in the table.

exe$table:      .long           exe$$put_console    ; CHMK 0
                .long           exe$halt            ; CHMK 1 - Halt emulation
                .long           exe$$get_console    ; CHMK 2
                .long           decc$read           ; CHMK 3 - direct to SHIM
                .long           decc$write          ; CHMK 4 - direct to SHIM
                .long           decc$open           ; CHMK 5 - direct to SHIM
                .long           decc$close          ; CHMK 6 - direct to SHIM
                .long           exe$$quit_emulation ; CHMK 7 - exit eVAX
                

;       Store the length in longwords of the table

exe$table_len:  .long         ( . - exe$table ) / 4


;--------------------------------------------------------------------
;   AST HANDLER
;--------------------------------------------------------------------

;       This is called by the AST interrupt handler to process an
;       item that had been queued up for AST delivery.  The single
;       parameter is the AST control block.  The first two longwords
;       are undefined (part of the AST queue block).  The remaining
;       data after the linkages are where the AST data resides.

                .entry          exe$handle_ast

                ret

;--------------------------------------------------------------------
;   CONSOLE READ A BYTE
;--------------------------------------------------------------------

;       This is called by the CONREAD interrupt handler to process a
;       single byte of data, passed as the parameter to this routine.
;       We file this away in the console read buffer.

                .entry          exe$rx_get
                
                cmpl            #100,@#exe$rxlen
                beql            _done
    
                incl            @#exe$rxlen
                
                movl            @#exe$rxptr, r0
                movb            b^4(ap),(r0)+
                movl            r0,@#exe$rxptr  
                        
_done:          ret
                
;--------------------------------------------------------------------
;   KERNEL INITIALIZATION
;--------------------------------------------------------------------

;       This is called by the vax.init file after the kernel is built.
;       This completes the runtime initialization of the system.  Put
;       things here that you want to have built by the VAX as opposed
;       to the assembler.  You must GO this code, not CALL it because
;       the console CALL code will screw up the registers on the RET
;       instruction.


exe$initialize: tstl            @#exe$init_done ; If we've already done
                bneq            exe$init_exit   ; this, just return

;       Set the bit in the TXCS register that says to interrupt
;       us when the data is successfully written.  This will cause
;       the EXE$TX interrupt handler to be hit again, which resets 
;       our internal ready flag at exe$tx_ready.

                mtpr            #40,#VAX$PR_TXCS

;       Similarly, let's indicate that we accept interrupts for the
;       console input.

                mtpr            #40,#VAX$PR_RXCS
                

;       We want an interval timer interrupt every 10 10ms intervals
;       or so.  
                mcoml           #^d10, r0
                mtpr            r0, #VAX$PR_NICR

;	The TODR register only increments if it is non-zero.

                mtpr		#1, #VAX$PR_TODR
                

;       Now that NICR is set up, turn on interrupts, and reload the
;       ICR from the NICR.

                mtpr            #0ff,#VAX$PR_ICCS
                
;       Mark the flag that says we're done

                movl            #1, @#exe$init_done

;       We've got to get out of kernel mode.  To do this at runtime,
;       we fake out a REI instruction.  Push the desired PSL and PC
;       on the stack and do an REI.  This will take us to the exit
;       point, in user mode with IPL of zero (so interrupts will
;       start happening).

                pushl           #03000000       ; desired PSL
                pushal          @#exe$init_exit ; desired PC
                rei                             ; do it

;       This is the exit point from the initialization routine.

exe$init_exit:  tstl		@#exe$verbose
                bneq		exe$printinitmsg
                brw		exe$silenthalt

exe$printinitmsg:
                pushal          @#exe$init_msg
                calls           #1, @#LIB$PUT_OUTPUT
                brw		exe$silenthalt

;       Let's protect the dispatcher so that you can't even read/see it
;       unless you are in kernel mode.  This keeps prying eyes out of 
;       the system.  But, we can't do it yet because doing so would prevent
;       forward references to fix up in the assembler.  So, save where we 
;       are and use it later.

                .set            exe$end .

 
;       Because of that, we need to be sure to start on a new boundary.

                .align          0200
                .set            exe$ubase .

;--------------------------------------------------------------------
;   DCL/CLI SUPPORT ROUTINES
;--------------------------------------------------------------------

;  Determine if an item is present
;
;  sts = dcl$present( long type, long id );
;

               .entry           dcl$present, ^m<r1,r2,r3>

               movl             b^4(ap), r1
               movl             b^8(ap), r2
               movl             #1, r0
               xfc              #xfc$dcl
               ret

;  Determine if a keyword is present
;
;  sts = dcl$keyword( long type, long id, long keyid );
;
               .entry           dcl$keyword, ^m<r1,r2,r3>

               movl             b^4(ap), r1
               movl             b^8(ap), r2
               movl             b^0C(ap), r3
               movl             #2, r0
               xfc              #xfc$dcl
               ret

;  Get a string item
;
;  char * p = dcl$string( long type, long id );
;

               .entry           dcl$string, ^m<>
               movl             b^4(ap), r1
               movl             b^8(ap), r2
               movl             #3, r0
               xfc              #xfc$dcl
               ret

;  Get an integer item
;
;  n = dcl$integer( long type, long id );
;

               .entry           dcl$integer, ^m<>
               movl             b^4(ap), r1
               movl             b^8(ap), r2
               movl             #4, r0
               xfc              #xfc$dcl
               ret


;
;  XTEST demo command.  This is used to test DCL command functions.  You
;  can add to the console command set, and if the microkernel is up, you
;  can have those commands executed as VAX instructions.  This lets you
;  extend the kernel without adding new C code to the console functions.
;  The instructions run in user mode in all cases, and must arrange (via
;  CHMK, etc. instructions to perform privileged operations.
;
;  You can call the DCL$ library functions to query the state of the
;  parameter(s) and qualifier(s) of the command as needed.  The entry
;  point for the command is defined in the /ENTRY= qualifier of the
;  evax.dcl definition.
;

               .entry           exe$xtest,^m<>

;     FIRST, get the /CODE= qualifier value, id 5005 in the evax.dcl file

               pushl            #^d5005
               pushl            #DCL$_QUALIFIER
               calls            #2, @#dcl$integer

               pushl            r0
               pushal           @#_msg4
               calls            #2, @#decc$printf

;     SECOND, see if the P1 parameter is present, id 5002

               pushl            #^d5002
               pushl            #DCL$_PARAMETER
               calls            #2, @#dcl$present
               blbs             r0, _present

               pushal           @#_msg1
               brb              _done

_done:         calls            #1, decc$printf
               movl             #SS$_NORMAL, r0
               brb              _name
               ret

;     THIRD, if it's present, see if the keyword value is negated or not

_present:      pushl            #^d5003
               pushl            #^d5002
               pushl            #DCL$_PARAMETER
               calls            #2, @#dcl$keyword
               tstl             r0
               bleq             _neg
               pushal           @#_msg2
               brb              _done

_neg:          pushal           @#_msg3
               brb              _done

_name:         pushl            #^d5004
               pushl            #DCL$_PARAMETER
               calls            #2, @#dcl$string
               tstl             r0
               beql             _noname
               pushl            r0
               pushal           @#_msg5
               calls            #2, @#decc$printf
               ret

_noname:       pushal           @#_msg6
               calls            #2, @#decc$printf
               ret

_msg1:         .asciz           "DEBUG not present\n"
_msg2:         .asciz           "DEBUG set\n"
_msg3:         .asciz           "DEBUG negated\n"
_msg4:         .asciz           "CODE value is %d\n"
_msg5:         .asciz           "Name is %s\n"
_msg6:         .asciz           "No name given\n"

;--------------------------------------------------------------------
;   "FORTH" console command
;--------------------------------------------------------------------

               .entry           exe$forth_dcl

               pushl            #^d6001
               pushl            #DCL$_PARAMETER
               calls            #2, @#dcl$string
               tstl             r0
               beql             _nocmd
               pushl            r0
               ; calls            #1, @#exe$cforth
               ret

_nocmd:        ; calls            #0, @#exe$forth
               ret

;--------------------------------------------------------------------
;   "ABOUT" console command
;--------------------------------------------------------------------

		.entry 		exe$about

		pushal		@#_msg1
		calls		#1, @#lib$put_output

		pushal		@#_msg2
		calls		#1, @#lib$put_output
		ret

_msg1:		.ascid		"eVAX 1.1  MicroKernel 2.0"
_msg2:		.ascid		"By Tom Cole"




;--------------------------------------------------------------------
;   USER MODE FRONT-END TO SYSTEM SERVICES
;--------------------------------------------------------------------

              
;
;       Write a list of items, passed as parameters via standard calling
;       conventions.  Each item is passed to lib$put_output() as a single
;       item for output.
;

                .entry          lib$put_output, ^m<r3,r4>
                movl            (ap), r3                ; Count of arguments
                tstl            r3                      ; Are there any?
                beql            _exit                   ; No, we're done
                addl3           #4, ap, r4              ; Yes, find first one

_loop:          pushl           (r4)+                   ; push the parameter
                calls           #1, @#lib$put_one       ; call output
                sobgtr          r3, _loop               ; loop if more
                
                pushl           #0a                     ; else end with LF
                calls           #1, @#lib$put_one
                
                pushl           #0d                     ; and CR
                calls           #1, @#lib$put_one
                
                movl            #1, r0                  ; now done
                ret

_exit:          movl            #1, r0
                ret

;               LIB$PUT_ONE( struct dsc$descriptor_s * msg );

                .entry          lib$put_one, ^m<r2,r3,r4,r5,r6>

                movl            b^4(ap), r5          ; Get descriptor address

                cmpl            r5, #0ff             ; see if it's one char.
                blequ           _byte                ; if so, print it

                clrl            r6                   ; Empty counter register
                movw            (r5), r6             ; Get count word from desc
                beql            _exit                ; If zero, then no work
                movl            b^4(r5), r2          ; Else get address
                clrl            r4                   ; Clear data register

_loop:          movb            (r2)+, r5            ; Get byte, advance ptr
                chmk            #EXE$PUT_CONSOLE     ; Output single byte
                blbc            r0, _errexit         ; If bad RC, done
                sobgtr          r6, _loop            ; Decrement counter, rpt
                brb             _exit

_byte:          chmk            #EXE$PUT_CONSOLE     ; Output single byte in R5
                blbc            r0, _errexit         ; If bad RC, done

_exit:          movl            #SS$_NORMAL, r0      ; Signal success
_errexit:       ret                                  ; And flee


;               LIB$QUIT_EMULATION( void )

                .entry  lib$quit_emulation
                chmk           #EXE$QUIT_EMULATION
                ret
                
                
;               rc = LIB$GET_INPUT( DESCRIPTOR * buff [, DESCRIPTOR * prompt [, short * len ]]);

                .entry  lib$get_input, ^m<r2,r3,r4>
                
                movl            b^4(ap),    r2      ; Address of descriptor
                movl            b^8(ap),    r3      ; Address of prompt
                tstl            r3
                beql            _get                ; If no prompt, skip it
                pushl           r3
                calls           #1, lib$put_one     ; Else put out prompt
                
_get:           cvtwl           (r2),r4             ; Get length
                pushl           r4                  ; push length of buffer
                pushl           b^4(r2)             ; push address of buffer
                calls           #2,exe$input        ; Get input from user
                movl            b^0c(ap),   r3      ; Get address of length
                tstl            r3
                beql            _done
                cvtlw           r0, (r3)            ; Write length to caller

_done:          movl            #SS$_NORMAL, r0
                ret
                

;               len = LIB$FORMAT_DEC( long value, char * buffer, long *size );

                .entry  lib$format_dec, ^m<r2,r3,r4,r5,r6,r7,r8, r9>

;
;   We're going to allocate some stack space.  So move the SP down to
;   prepare room for it.

                subl2   #4,sp

                movl    b^0C(ap), r9            ; Get length pointer

                movl    b^4(ap), r2             ; Get the value to format
                tstl    r2                      ; Is it zero?

                beql    _zero                   ; If so, special case

;
;   Allocate some "automatic storage" on the stack by marking where we
;   are (since we want the end of the buffer anyway) and move the SP
;   down in case we need it for something else.
;

                movl    sp,r6                   ; Point to end of space
                subl2   r9, sp                  ; and move end of stack down
                                                ; by size of user's buffer

                clrl    r7                      ; init the counter

_loop:          divl3   #^d10, r2, r3           ; Shift off digit
                mull3   r3, #^d10, r4           ; And back again
                subl3   r4, r2, r5              ; Difference is digit
                addl2   #30, r5                 ; Make ASCII

                movb    r5, -(r6)               ; copy to buffer, decrement
                incl    r7                      ; and increment counter
                cmpl    r7, (r9)                ; too big?
                bgtr    _oflow                  ; yes, bail out

                tstl   r4                       ; Is there more?
                beql   _exit                    ; No, done

                movl   r3, r2                   ; Yes, set it up
                brb    _loop                    ; And loop again

_oflow:         movl   #SS$_BUFFEROVF, r0       ; Return overflow
                ret

_zero:          movl   sp, r6                   ; Get address of stack buffer
                movb   #30, (r6)                ; Write "0" to buffer
                movl   #1, r7                   ; return length of 1

_exit:          movl   b^8(ap), r8              ; Get address of buffer
                movc3  r7, (r6), (r8)           ; Copy to user's buffer
                movl   b^0c(ap),r8
                movl   r7, (r8)                 ; and return the length
                movl   #SS$_NORMAL, r0          ; signal success
                ret                             ; Go home.


;               len = LIB$FORMAT_HEX( long value, char * buffer, long *size );

                .entry  lib$format_hex, ^m<r2,r3,r4,r5,r6,r7,r8, r9>

;
;   We're going to allocate some stack space.  So move the SP down to
;   prepare room for it.

                subl2   #4,sp
                moval   @#lib$hex_table, r8     ; get address of table
                
                movl    b^0C(ap), r9            ; Get length pointer

                movl    b^4(ap), r2             ; Get the value to format
                tstl    r2                      ; Is it zero?

                beql    _zero                   ; If so, special case

;
;   Allocate some "automatic storage" on the stack by marking where we
;   are (since we want the end of the buffer anyway) and move the SP
;   down in case we need it for something else.
;

                movl    sp,r6                   ; Point to end of space
                subl2   (r9), sp                ; and move end of stack down
                                                ; by size of user's buffer

                clrl    r7                      ; init the counter

_loop:          divl3   #^d16, r2, r3           ; Shift off digit
                mull3   r3, #^d16, r4           ; And back again
                subl3   r4, r2, r5              ; Difference is digit
                
                movb    (r8)[r5],-(r6)          ; Look up in table to make HEX,
                                                ;   copy to buffer, decrement
                                                
                incl    r7                      ; and increment counter
                cmpl    r7, (r9)                ; too big?
                bgtr    _oflow                  ; yes, bail out

                tstl   r4                       ; Is there more?
                beql   _exit                    ; No, done

                movl   r3, r2                   ; Yes, set it up
                brb    _loop                    ; And loop again

_oflow:         movl   #SS$_BUFFEROVF, r0       ; Return overflow
                ret

_zero:          movl   sp, r6                   ; Get address of stack buffer
                movb   #30, (r6)                ; Write "0" to buffer
                movl   #1, r7                   ; return length of 1

_exit:          movl   b^8(ap), r8              ; Get address of buffer
                movc3  r7, (r6), (r8)           ; Copy to user's buffer
                movl   b^0c(ap),r8
                movl   r7, (r8)                 ; and return the length
                movl   #SS$_NORMAL, r0          ; signal success
                ret                             ; Go home.


;--------------------------------------------------------------------
;   DECC$SHR runtime support
;--------------------------------------------------------------------

;   *** Note that the MAIN entry initialization is via JSB not CALL

decc$main:      nop             ; Currently, no work done.
                rsb

                .entry          decc$exit
                nop
                ret

                .entry  cma$tis_errno_get_addr, ^m<>
                moval   @#vaxc$errno, r0
                ret

                .entry  decc$calloc, ^m<r2,r3>

                mull3   b^4(ap),b^8(ap), r3 ; How much storage?
                pushl   r3
                calls   #1, @#decc$malloc   ; Get the storage

                tstl    r0                  ; If no memory, done
                beql    _done
                movl    r0,r2

_zero:          clrb    (r2)+               ; Clear byte
                sobgtr  r3, _zero           ; for as many bytes as needed

_done:          ret                         ; Done


                .entry  decc$strcat, ^m<r2>

                pushl   b^4(ap)             ; Find length of dst
                calls   #1, @#decc$strlen
                addl3   b^4(ap), r0, r2     ; Add to addr of dst
                pushl   b^8(ap)             ; push src
                pushl   r2                  ; and dst   
                calls   #2, @#decc$strcpy   ; and copy there
                addl2   r2,r0               ; return total length
                ret

                .entry  decc$strcpy, ^m<r2,r3>
                movl    b^4(ap), r2
                movl    b^8(ap), r3
                clrl    r0
                
_loop:          movb    (r3),(r2)
                tstb    (r2)
                beql    _done
                incl    r0
                incl    r2
                incl    r3
                brb     _loop
_done:          ret

                .entry  decc$strlen, ^m<r2>
                movl    b^4(ap), r2
                clrl    r0
_loop:          tstb    (r2)
                beql    _done
                incl    r0
                incl    r2
                brb     _loop
_done:          ret

;--------------------------------------------------------------------
;   SOFTWARE SHIM DEFINITIONS FOR XFC EXITS
;
;   The first parameter is the local entry point name, that can be
;   called by assembler code, etc.
;
;   The second parameter defines the function code in the XFC handler
;   as defined in "shim.c"
;
;   The third parameter is the name of the sharable image that this
;   routine is a shim for.  This is used by the RUN command's image
;   activator to map runtime libraries to families of shims.
;
;   The fourth parameter is the offset in the sharable image of the
;   real sharable image that supports this routine.  This is used by
;   the image activator to bind a specific sharable image .ADDRESS
;   or G^ references to this shim entry.
;
;--------------------------------------------------------------------

		.align	8

;                       ------------        -----  --------   ------
;                       Entry Name             ID  RTL        Offset
;                       ------------        -----  --------   ------
                .shim   lib$adawi,            ^d1, LIBRTL,      0778
                .shim   str$upcase,           ^d2, LIBRTL,      0A70
                .shim   exe$input,            ^d3, EVAX,        0004
                .shim   decc$open,            ^d4, DECC$SHR,    04E8
                .shim   decc$close,           ^d5, DECC$SHR,    0490
                .shim   decc$read,            ^d6, DECC$SHR,    04F0
                .shim   decc$write,           ^d7, DECC$SHR,    0508
                .shim   decc$printf,          ^d8, DECC$SHR,    0380
                .shim   decc$sprintf,         ^d9, DECC$SHR,    03E0
                .shim   decc$strcmp,         ^d10, DECC$SHR,    06C0
                .shim   decc$strncmp,        ^d11, DECC$SHR,    06F8
                .shim   decc$strncpy,        ^d12, DECC$SHR,    0700
                .shim   decc$atoi,           ^d13, DECC$SHR,    0568
                .shim   decc$gets,           ^d14, DECC$SHR,    0370
                .shim   decc$malloc,         ^d15, DECC$SHR,    0548
                .shim   decc$free,           ^d16, DECC$SHR,    0538
                .shim   decc$isalnum,        ^d17, DECC$SHR,    0018
                .shim   decc$isalpha,        ^d18, DECC$SHR,    0020
                .shim   decc$iscntrl,        ^d19, DECC$SHR,    0030
                .shim   decc$isdigit,        ^d20, DECC$SHR,    0038
                .shim   decc$isgraph,        ^d21, DECC$SHR,    0040
                .shim   decc$islower,        ^d22, DECC$SHR,    0048
                .shim   decc$isprint,        ^d23, DECC$SHR,    0050
                .shim   decc$ispunct,        ^d24, DECC$SHR,    0058
                .shim   decc$isspace,        ^d25, DECC$SHR,    0060
                .shim   decc$isupper,        ^d26, DECC$SHR,    0068
                .shim   decc$isxdigit,       ^d27, DECC$SHR,    0070
                .shim   decc$isascii,        ^d28, DECC$SHR,    0028
                .shim   lib$get_vm,          ^d29, LIBRTL,      0550
                .shim   lib$free_vm,         ^d30, LIBRTL,      0548
                .shim   lib$delete_vm_zone,  ^d31, LIBRTL,      0A48
                .shim   decc$time,           ^d32, DECC$SHR,    0768
;                       ------------        -----  --------   ------
;                       Entry Name             ID  RTL        Offset
;                       ------------        -----  --------   ------


                .set    exe$uend    .
    
;--------------------------------------------------------------------
;   WRITABLE STORAGE AREA FOR KERNEL
;--------------------------------------------------------------------

;       This is the kernel writable data area.  It has different page
;       attributes so it must be aligned on a new page boundary.

                .align          0200
                .set            exe$wbase .
                
exe$tx_ready:   .long           1               ; Is TXCS available?
exe$rx_ready:   .long           0               ; Is RXCS available?
exe$init_done:  .long           0               ; Is kernel initialized?
exe$int_count:  .long           0               ; Interval timer count

exe$ast_list:   .long           exe$ast_list    ; Head of AST queue
                .long           exe$ast_list

;       Register Save Areas

exe$chmk_r0:    .long           0
exe$chmk_r1:    .long           0

;       Region handlers

exe$p0_rgn:     .long           0
exe$p1_rgn:     .long           0
exe$s0_rgn:     .long           0


;       Console input stuff

exe$verbose:    .long		verbose()   ; function value set by console

exe$rxdata:     .blkb           100
exe$rxdesc:
exe$rxlen:      .long           0
exe$rxbuffer:   .long           exe$rxdata
exe$rxptr:      .long           exe$rxdata

vaxc$errno:     .long           0

;       Message descriptors

exe$init_msgb:  .ascii          "Kernel initialized..."
exe$init_msg:   .long           . - exe$init_msgb
                .long           exe$init_msgb   

exe$sig_buff:   .blkb           10
exe$sig_desc:
exe$sig_buff_len:.long          8
                .long           exe$sig_buff
                
;       Storage used by LIBRTL replacements

decc$$gl___ctypea:    .long    1   ; Runtime flag indicating CTYPE table avail.
decc$$ga___ctypet:    .long    exe$ctype_table
exe$ctype_table:                                  ; Actual table starts here
                      .long    ^X00000020  ;  00
                      .long    ^X00000020  ;  01
                      .long    ^X00000020  ;  02
                      .long    ^X00000020  ;  03
                      .long    ^X00000020  ;  04
                      .long    ^X00000020  ;  05
                      .long    ^X00000020  ;  06
                      .long    ^X00000020  ;  07
                      .long    ^X00000020  ;  08
                      .long    ^X00000428  ;  09
                      .long    ^X00000028  ;  0A
                      .long    ^X00000028  ;  0B
                      .long    ^X00000028  ;  0C
                      .long    ^X00000028  ;  0D
                      .long    ^X00000020  ;  0E
                      .long    ^X00000020  ;  0F
                      .long    ^X00000020  ;  10
                      .long    ^X00000020  ;  11
                      .long    ^X00000020  ;  12
                      .long    ^X00000020  ;  13
                      .long    ^X00000020  ;  14
                      .long    ^X00000020  ;  15
                      .long    ^X00000020  ;  16
                      .long    ^X00000020  ;  17
                      .long    ^X00000020  ;  18
                      .long    ^X00000020  ;  19
                      .long    ^X00000020  ;  1A
                      .long    ^X00000020  ;  1B
                      .long    ^X00000020  ;  1C
                      .long    ^X00000020  ;  1D
                      .long    ^X00000020  ;  1E
                      .long    ^X00000020  ;  1F
                      .long    ^X00000488  ;  20
                      .long    ^X00000290  ;  21
                      .long    ^X00000290  ;  22
                      .long    ^X00000290  ;  23
                      .long    ^X00000290  ;  24
                      .long    ^X00000290  ;  25
                      .long    ^X00000290  ;  26
                      .long    ^X00000290  ;  27
                      .long    ^X00000290  ;  28
                      .long    ^X00000290  ;  29
                      .long    ^X00000290  ;  2A
                      .long    ^X00000290  ;  2B
                      .long    ^X00000290  ;  2C
                      .long    ^X00000290  ;  2D
                      .long    ^X00000290  ;  2E
                      .long    ^X00000290  ;  2F
                      .long    ^X000002C4  ;  30
                      .long    ^X000002C4  ;  31
                      .long    ^X000002C4  ;  32
                      .long    ^X000002C4  ;  33
                      .long    ^X000002C4  ;  34
                      .long    ^X000002C4  ;  35
                      .long    ^X000002C4  ;  36
                      .long    ^X000002C4  ;  37
                      .long    ^X000002C4  ;  38
                      .long    ^X000002C4  ;  39
                      .long    ^X00000290  ;  3A
                      .long    ^X00000290  ;  3B
                      .long    ^X00000290  ;  3C
                      .long    ^X00000290  ;  3D
                      .long    ^X00000290  ;  3E
                      .long    ^X00000290  ;  3F
                      .long    ^X00000290  ;  40
                      .long    ^X000003C1  ;  41
                      .long    ^X000003C1  ;  42
                      .long    ^X000003C1  ;  43
                      .long    ^X000003C1  ;  44
                      .long    ^X000003C1  ;  45
                      .long    ^X000003C1  ;  46
                      .long    ^X00000381  ;  47
                      .long    ^X00000381  ;  48
                      .long    ^X00000381  ;  49
                      .long    ^X00000381  ;  4A
                      .long    ^X00000381  ;  4B
                      .long    ^X00000381  ;  4C
                      .long    ^X00000381  ;  4D
                      .long    ^X00000381  ;  4E
                      .long    ^X00000381  ;  4F
                      .long    ^X00000381  ;  50
                      .long    ^X00000381  ;  51
                      .long    ^X00000381  ;  52
                      .long    ^X00000381  ;  53
                      .long    ^X00000381  ;  54
                      .long    ^X00000381  ;  55
                      .long    ^X00000381  ;  56
                      .long    ^X00000381  ;  57
                      .long    ^X00000381  ;  58
                      .long    ^X00000381  ;  59
                      .long    ^X00000381  ;  5A
                      .long    ^X00000290  ;  5B
                      .long    ^X00000290  ;  5C
                      .long    ^X00000290  ;  5D
                      .long    ^X00000290  ;  5E
                      .long    ^X00000290  ;  5F
                      .long    ^X00000290  ;  60
                      .long    ^X000003C2  ;  61
                      .long    ^X000003C2  ;  62
                      .long    ^X000003C2  ;  63
                      .long    ^X000003C2  ;  64
                      .long    ^X000003C2  ;  65
                      .long    ^X000003C2  ;  66
                      .long    ^X00000382  ;  67
                      .long    ^X00000382  ;  68
                      .long    ^X00000382  ;  69
                      .long    ^X00000382  ;  6A
                      .long    ^X00000382  ;  6B
                      .long    ^X00000382  ;  6C
                      .long    ^X00000382  ;  6D
                      .long    ^X00000382  ;  6E
                      .long    ^X00000382  ;  6F
                      .long    ^X00000382  ;  70
                      .long    ^X00000382  ;  71
                      .long    ^X00000382  ;  72
                      .long    ^X00000382  ;  73
                      .long    ^X00000382  ;  74
                      .long    ^X00000382  ;  75
                      .long    ^X00000382  ;  76
                      .long    ^X00000382  ;  77
                      .long    ^X00000382  ;  78
                      .long    ^X00000382  ;  79
                      .long    ^X00000382  ;  7A
                      .long    ^X00000290  ;  7B
                      .long    ^X00000290  ;  7C
                      .long    ^X00000290  ;  7D
                      .long    ^X00000290  ;  7E
                      .long    ^X00000020  ;  7F
                      .long    ^X00000000  ;  80
                      .long    ^X00000000  ;  81
                      .long    ^X00000000  ;  82
                      .long    ^X00000000  ;  83
                      .long    ^X00000020  ;  84
                      .long    ^X00000020  ;  85
                      .long    ^X00000020  ;  86
                      .long    ^X00000020  ;  87
                      .long    ^X00000020  ;  88
                      .long    ^X00000020  ;  89
                      .long    ^X00000020  ;  8A
                      .long    ^X00000020  ;  8B
                      .long    ^X00000020  ;  8C
                      .long    ^X00000020  ;  8D
                      .long    ^X00000020  ;  8E
                      .long    ^X00000020  ;  8F
                      .long    ^X00000020  ;  90
                      .long    ^X00000020  ;  91
                      .long    ^X00000020  ;  92
                      .long    ^X00000020  ;  93
                      .long    ^X00000020  ;  94
                      .long    ^X00000020  ;  95
                      .long    ^X00000020  ;  96
                      .long    ^X00000020  ;  97
                      .long    ^X00000000  ;  98
                      .long    ^X00000000  ;  99
                      .long    ^X00000000  ;  9A
                      .long    ^X00000020  ;  9B
                      .long    ^X00000020  ;  9C
                      .long    ^X00000020  ;  9D
                      .long    ^X00000020  ;  9E
                      .long    ^X00000020  ;  9F
                      .long    ^X00000000  ;  A0
                      .long    ^X00000290  ;  A1
                      .long    ^X00000290  ;  A2
                      .long    ^X00000290  ;  A3
                      .long    ^X00000000  ;  A4
                      .long    ^X00000290  ;  A5
                      .long    ^X00000000  ;  A6
                      .long    ^X00000290  ;  A7
                      .long    ^X00000290  ;  A8
                      .long    ^X00000290  ;  A9
                      .long    ^X00000290  ;  AA
                      .long    ^X00000290  ;  AB
                      .long    ^X00000000  ;  AC
                      .long    ^X00000000  ;  AD
                      .long    ^X00000000  ;  AE
                      .long    ^X00000000  ;  AF
                      .long    ^X00000290  ;  B0
                      .long    ^X00000290  ;  B1
                      .long    ^X00000290  ;  B2
                      .long    ^X00000290  ;  B3
                      .long    ^X00000000  ;  B4
                      .long    ^X00000290  ;  B5
                      .long    ^X00000290  ;  B6
                      .long    ^X00000290  ;  B7
                      .long    ^X00000000  ;  B8
                      .long    ^X00000290  ;  B9
                      .long    ^X00000290  ;  BA
                      .long    ^X00000290  ;  BB
                      .long    ^X00000290  ;  BC
                      .long    ^X00000290  ;  BD
                      .long    ^X00000000  ;  BE
                      .long    ^X00000290  ;  BF
                      .long    ^X00000290  ;  C0
                      .long    ^X00000290  ;  C1
                      .long    ^X00000290  ;  C2
                      .long    ^X00000290  ;  C3
                      .long    ^X00000290  ;  C4
                      .long    ^X00000290  ;  C5
                      .long    ^X00000290  ;  C6
                      .long    ^X00000290  ;  C7
                      .long    ^X00000290  ;  C8
                      .long    ^X00000290  ;  C9
                      .long    ^X00000290  ;  CA
                      .long    ^X00000290  ;  CB
                      .long    ^X00000290  ;  CC
                      .long    ^X00000290  ;  CD
                      .long    ^X00000290  ;  CE
                      .long    ^X00000290  ;  CF
                      .long    ^X00000000  ;  D0
                      .long    ^X00000290  ;  D1
                      .long    ^X00000290  ;  D2
                      .long    ^X00000290  ;  D3
                      .long    ^X00000290  ;  D4
                      .long    ^X00000290  ;  D5
                      .long    ^X00000290  ;  D6
                      .long    ^X00000290  ;  D7
                      .long    ^X00000290  ;  D8
                      .long    ^X00000290  ;  D9
                      .long    ^X00000290  ;  DA
                      .long    ^X00000290  ;  DB
                      .long    ^X00000290  ;  DC
                      .long    ^X00000290  ;  DD
                      .long    ^X00000000  ;  DE
                      .long    ^X00000290  ;  DF
                      .long    ^X00000290  ;  E0
                      .long    ^X00000290  ;  E1
                      .long    ^X00000290  ;  E2
                      .long    ^X00000290  ;  E3
                      .long    ^X00000290  ;  E4
                      .long    ^X00000290  ;  E5
                      .long    ^X00000290  ;  E6
                      .long    ^X00000290  ;  E7
                      .long    ^X00000290  ;  E8
                      .long    ^X00000290  ;  E9
                      .long    ^X00000290  ;  EA
                      .long    ^X00000290  ;  EB
                      .long    ^X00000290  ;  EC
                      .long    ^X00000290  ;  ED
                      .long    ^X00000290  ;  EE
                      .long    ^X00000290  ;  EF
                      .long    ^X00000000  ;  F0
                      .long    ^X00000290  ;  F1
                      .long    ^X00000290  ;  F2
                      .long    ^X00000290  ;  F3
                      .long    ^X00000290  ;  F4
                      .long    ^X00000290  ;  F5
                      .long    ^X00000290  ;  F6
                      .long    ^X00000290  ;  F7
                      .long    ^X00000290  ;  F8
                      .long    ^X00000290  ;  F9
                      .long    ^X00000290  ;  FA
                      .long    ^X00000290  ;  FB
                      .long    ^X00000290  ;  FC
                      .long    ^X00000290  ;  FD
                      .long    ^X00000000  ;  FE
                      .long    ^X00000000  ;  FF

lib$hex_table:

                .ascii "0123456789ABCDEF"

                .set            exe$wend .

                .align          200
                .set            exe$fbase .
;
;   I've been playing around with a forth interpreter written back in 1984
;   for a VAX.  It might be interesting to include it in the microkernel
;   for handling logic at the virtual VAX level.  If the interpreter source
;   is present, assemble it as well.

                ; .if file_exists("forth.asm") .include       "forth.asm"
                nop

;   DCL string storage

                .align          200

exe$dclstring:  .blkb           100

                .set            exe$fend .

 
;--------------------------------------------------------------------
;   SOFTWARE SHIM DEFINITIONS FOR NATIVE KERNEL ROUTINES
;
;   The first parameter is the local entry point name, that can be
;   called by assembler code, etc.
;
;   The second parameter of 0 means the routine is implemented in the
;   microkernel and doesn't need a native runtime XFC stub.
;
;   The third parameter is the name of the sharable image that this
;   routine is a shim for.  This is used by the RUN command's image
;   activator to map runtime libraries to families of shims.
;
;   The fourth parameter is the offset in the sharable image of the
;   real sharable image that supports this routine.  This is used by
;   the image activator to bind a specific sharable image .ADDRESS
;   or G^ references to this shim entry.
;
;--------------------------------------------------------------------

                .shim   lib$put_output,         0, LIBRTL,      0478
                .shim   decc$main,              0, DECC$SHR,    0000
                .shim   decc$exit,              0, DECC$SHR,    0528
                .shim   decc$strlen,            0, DECC$SHR,    06E8
                .shim   decc$strcpy,            0, DECC$SHR,    06D0
                .shim   decc$strcat,            0, DECC$SHR,    06B0
                .shim   cma$tis_errno_get_addr, 0, CMA$TIS_SHR, 0038
                .shim   decc$calloc,            0, DECC$SHR,    0520
		.shim   decc$$gl___ctypea       0, DECC$SHR,    03098
		.shim   decc$$ga___ctypet       0, DECC$SHR,    0309C

;--------------------------------------------------------------------
;   RESET STATE FOR CONSOLE ASSEMBLER
;--------------------------------------------------------------------

;       This section takes care of miscellanous housekeeping.
;       Define the exception handlers in the SCB and make the 
;       entire kernel area protected from being written on.
;
;	Note that for many of these, we define "console$handler"
;       as the handler.  This equates to -1, and causes the emulator
;       to report on the exception using non-VAX native code, and
;       halts the emulation.  Later, this handler will also be 
;       able to chase user-mode stack frames looking for exception
;       handlers.

                .scb            exc$chmk,      exe$chmk
                .scb            exc$priv,      console$handler; exe$priv
                .scb            exc$accvio,    console$handler; exe$accvio
                .scb            exc$resop,     console$handler; exe$resop
                .scb            exc$resaddr,   console$handler; exe$resaddr
                .scb            exc$interval,  exe$interval
                .scb            exc$software2, exe$deliver_ast
                .scb            exc$conwrite,  exe$tx
                .scb            exc$conread,   exe$rx
                

;       Set page protections on the segments of the kernel.  This MUST
;       be done after all symbol fixups are generated, because the
;       microassembler is forced to abide by page table protections.

                .console        set page exe$ubase to exe$uend prot=pte$k_ur
                .console        set page exe$base to exe$end prot=pte$k_ur
                .console        set page exe$wbase to exe$wend prot=pte$k_kwur
                .console        set page exe$fbase to exe$fend prot=pte$k_all
                

;       All done, let's set the console back so user assembly can
;       occur normally

                .region         p0
