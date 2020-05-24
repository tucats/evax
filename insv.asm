
        .entry test, ^m<>

        movl   #14, r0
        insv   #0d, r0, #3, @#bits
        ret

bits:   .long   0
        .long   0

