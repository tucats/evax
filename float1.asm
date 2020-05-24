
;
;   First floating test
;

        .base       200

data:   .long       0
        .long       0
        
        .base       400

main:   movl        #^d100, r0
        cvtlf       r0, r0
        
        movl        #^d3, r1
        cvtlf       r1, r1
        
        divf3       r1, r0, r2
        
        movl        r2, @#data
        halt
