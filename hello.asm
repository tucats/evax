        .entry  main, ^m<>
        pushal  @#msg
        calls   #1,@#lib$put_output
        clrl    r0
        clrl    r1
        movl    #1000000, r5

loop:   addf2   r0, r1
        sobgtr  r5, loop


        ret

msg:    .ascid  "Hello world"
        .end    main

