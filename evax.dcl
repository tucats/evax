!
!   DCLRTL grammar definition for eVAX console commands
!


grammar evax

    syntax show_logical
        parameter name/id=301/type=$name
        qualifier table/id=300/type=$name
    
    syntax show_device
        parameter name/id=100/type=$name
        qualifier full/id=101
        
    type dev_class
        keyword disk	/id=1
        keyword tape	/id=2
        keyword scom	/id=32
        keyword card	/id=65
        keyword term	/id=66
        keyword	lp	/id=67
        keyword workstation/id=70
        keyword realtime/id=96
        keyword decvoice/id=97
        keyword audio	/id=98
        keyword	video	/id=99
        keyword	bus	/id=128
        keyword mailbox	/id=160
        keyword recmsl_storage/id=179
        keyword misc	/id=200
        
    type dev_type
        keyword	rk06		/id=1
        keyword	rk07		/id=2
        keyword	rp04		/id=3
        keyword rp05		/id=4
        keyword rp06		/id=5
        keyword rm03		/id=6
        keyword rp07		/id=7
        keyword	rp07ht		/id=8
        keyword rl01		/id=9
        keyword rl02		/id=10
        keyword	rx02		/id=11
        keyword rx04		/id=12
        keyword rm80		/id=13
        keyword tu58		/id=14
        keyword rm05		/id=15
        keyword rx01		/id=16
        keyword	ml11		/id=17
        keyword rb02		/id=18
        keyword rb80		/id=19
        keyword	ra80		/id=20
        keyword ra81		/id=21
        keyword	ra60		/id=22
        keyword	rz01		/id=23
        keyword rd51		/id=25
        keyword rx50		/id=26
        keyword vt100		/id=96
        
    syntax define_device
        parameter name/id=400/type=$name/prompt="Name"
        qualifier cluster/id=401/type=$integer
        qualifier cylinders/id=402/type=$integer
        qualifier devbufsize/id=403/type=$integer
        qualifier devchar/id=404/type=$integer
        qualifier devchar2/id=405/type=$integer
        qualifier devclass/id=406/type=dev_class
        qualifier devdepend/id=407/type=$integer
        qualifier devdepend2/id=408/type=$integer
        qualifier devtype/id=409/type=dev_type
        qualifier freeblocks/id=410/type=$integer
        qualifier lockid/id=411/type=$integer
        qualifier maxblock/id=412/type=$integer
        qualifier maxfiles/id=413/type=$integer
        qualifier ownuic/id=414/type=$integer
        qualifier recsize/id=415/type=$integer
        qualifier sectors/id=416/type=$integer
        qualifier serial/id=417/type=$integer
        qualifier volname/id=420/type=$string
        qualifier medianame/id=421/type=$string
        qualifier mediatype/id=422/type=$string
        qualifier rootdevname/id=423/type=$string
        
        
    syntax define_logical
        parameter name/id=201/type=$name/prompt="Name"
        qualifier table/id=200/type=$name
        parameter value/id=202/type=$any/prompt="Value"
        
    verb define
    
        qualifier	logical/syntax=define_logical
        qualifier	device/syntax=define_device
        
    type debug_types
        keyword     debug/id=5003

    verb about /entry=exe$about

    verb forth /entry=exe$forth_dcl
        parameter   cmd/id=6001/type=$string

    verb exit
    
    verb quit/alias=exit
    
    verb test
    
        parameter   what/id=161                 -
                    /type=$rest_of_line         -
                    /prompt="Code"


    verb call

        qualifier step
        parameter   routine                     -
                    /type=$rest_of_line         -
                    /prompt="Routine"
    
    
    type clear_types
        keyword     breakpoint          /syntax=clear_breakpoint
        keyword     interrupt           /syntax=clear_interrupt
        keyword     memory              /syntax=clear_memory
        keyword     profiles            /syntax=clear_profiles
        keyword     symbol              /syntax=clear_symbols
        keyword     strings             /syntax=clear_strings
        keyword     tb                  /syntax=clear_tb
        keyword     translation_buffer  /syntax=clear_tb
        keyword     error               /syntax=clear_error
        
        
        
    verb clear
    
        parameter   CLEAR_TYPE/type=clear_types/prompt="What"
 
  
        syntax clear_sym_temp/id=115
        syntax clear_mem_stat/id=114
        syntax clear_error/id=113
        syntax clear_break_all/id=112
        syntax clear_sym_all/id=111
        syntax clear_interrupt_all/id=110
        syntax clear_break_fault_all/id=109
        syntax clear_break_instr_all /id =553
        syntax clear_break_instr/id=551
            qualifier   all -
                        /syntax=clear_break_instr_all
            parameter   p1 /id=552 -
                        /type=$rest_of_line -
                        /prompt="Opcode"
                        
        syntax clear_break_fault/id=108
            qualifier   all                         -
                        /syntax=clear_break_fault_all
            parameter   p1 /id=2                    -
                        /type=$rest_of_line         -
                        /prompt="Fault"
        syntax clear_tb/id=107
        syntax clear_symbols/id=106
            qualifier   temporary                   -
                        /syntax=clear_sym_temp
            qualifier   all                         -
                        /syntax=clear_sym_all
            parameter   p1 /id=1003                 -
                        /type=$name                 -
                        /prompt="Symbol"
        syntax clear_strings/id=105
        syntax clear_breakpoint/id=101
            qualifier   fault                       -
                        /syntax=clear_break_fault
            qualifier	instruction		    -
                        /syntax=clear_break_instr
            qualifier   all                         -
                        /syntax=clear_break_all
            parameter   BREAK_ADDR /id=1            -
                        /type=$rest_of_line         -
                        /prompt="Address"
        syntax clear_interrupt/id=102
            qualifier   all                         -
                        /syntax=clear_interrupt_all
            parameter   INTERRUPT_ID/id=1002        -
                        /type=$rest_of_line         -
                        /prompt="Fault"
        syntax clear_memory/id=103
            qualifier   statistics                  -
                        /syntax=clear_mem_stat
        syntax clear_profiles/id=104
    
    
    type show_types
        keyword		clock		/syntax=show_clock
        keyword         watchpoints     /syntax=show_watchpoints
        keyword		logical_names	/syntax=show_logical
        keyword		devices		/syntax=show_device
        keyword         version         /syntax=show_version
        keyword         xtest           /syntax=xtest
        keyword         string_pool     /syntax=show_string
        keyword         nvram           /syntax=show_nvram      
        keyword         error           /syntax=show_error
        keyword         mode            /syntax=show_mode
        keyword         shim            /syntax=show_shim
        keyword         page            /syntax=show_page
        keyword         pte             /syntax=show_page
        keyword         call_frames     /syntax=show_call_frames
        keyword         calls           /syntax=show_call_frames
        keyword         quantum         /syntax=show_quantum
        keyword         debug           /syntax=show_debug
        keyword         assembler_flags /syntax=show_assembler_flags
        keyword         instructions    /syntax=show_instructions
        keyword         breakpoints     /syntax=show_break
        keyword         registers       /syntax=show_reg
        keyword         reg             /syntax=show_reg
        keyword         step_mode       /syntax=show_step
        keyword         psl             /syntax=show_psl
        keyword         cpu_status      /syntax=show_cpu
        keyword         base            /syntax=show_base
        keyword         memory          /syntax=show_memory
        keyword         vm              /syntax=show_memory
        keyword         stack           /syntax=show_stack
        keyword         isp             /syntax=show_isp
        keyword         ksp             /syntax=show_ksp
        keyword         esp             /syntax=show_esp
        keyword         ssp             /syntax=show_ssp
        keyword         usp             /syntax=show_usp
        keyword         exceptions      /syntax=show_fault
        keyword         faults          /syntax=show_fault
        keyword         radix           /syntax=show_radix
        keyword         trace           /syntax=show_trace
        keyword         disassembly     /syntax=show_trace
        keyword         scb             /syntax=show_scb
        keyword         symbols         /syntax=show_sym
        keyword         rom             /syntax=show_rom
        keyword         tb              /syntax=show_tb
        keyword         translation_buffer/syntax=show_tb
        keyword         maps            /syntax=show_map
        keyword         images          /syntax=show_images
        keyword         regions         /syntax=show_regions
        keyword         share_prefix    /syntax=show_share
        keyword         command_args    /syntax=show_command_args
        keyword         expand          /syntax=show_expand
        keyword         r0
        keyword         r1
        keyword         r2
        keyword         r3
        keyword         r4
        keyword         r5
        keyword         r6
        keyword         r7
        keyword         r8
        keyword         r9
        keyword         r10
        keyword         r11
        keyword         r12
        keyword         r13
        keyword         r14
        keyword         r15
        keyword         AP
        keyword         FP
        keyword         SP
        keyword         PC
        keyword         p0br
        keyword         p0lr
        keyword         p1br
        keyword         p1l4
        keyword         sbr
        keyword         slr
        keyword         pcbb
        keyword         scbb
        keyword         ipl
        keyword         astlvl
        keyword         sirr
        keyword         sisr
        keyword         iccs
        keyword         nicr
        keyword         icr
        keyword         todr
        keyword         rxcs
        keyword         rxdb
        keyword         txcs
        keyword         txdb
        keyword         tbdr
        keyword         savisp
        keyword         savpc
        keyword         savpsl
        keyword         wcsa
        keyword         wcsb
        keyword         mapen
        keyword         tbia
        keyword         tbis
        keyword         pmr
        keyword         sid
        keyword         tbchk
                

	verb vminit

            qualifier       p0 /id=1801 -
		                /type=$integer

	    qualifier       p1 /id=1802 -
		                /type=$integer

	    qualifier       s0 /id=1803 -
		                /type=$integer

            qualifier       ksp /id=1804 -
                                /type=$integer -
                                /default=4

            qualifier       esp /id=1805 -
                                /type=$integer -
                                /default=4

            qualifier       ssp /id=1806 -
                                /type=$integer -
                                /default=4

            qualifier       isp /id=1807 -
                                /type=$integer -
                                /default=4

            qualifier       stringpool /id=1808 -
			        /type=$integer -
                                /default=8

            qualifier       debug /id=1809
            qualifier       verify /alias=debug
            qualifier       log /alias=debug

    verb show/id=120
    
        parameter       SHOW_TYPE/id=160            -
                        /type=show_types            -
                        /prompt="What"
    
        syntax xtest/entry=exe$xtest /id=5001
            parameter   debug /type=debug_types /id = 5002
            qualifier   code/type=$integer /id=5005/nonegatable/default=101
            parameter   name/type=$any/id=5004                    

        syntax		show_expand/id=188
        syntax          show_command_args/id=159
        syntax          show_map/id=156                
        syntax          show_tb/id=155
        syntax          show_rom/id=154
        syntax          show_scb/id=148
            qualifier   all/id=1032
        syntax          show_sym_all/id=150
        syntax          show_sym_sys/id=151
        syntax          show_sym_tmp/id=152
        syntax          show_sym_unres/id=153
        syntax          show_sym/id=149
            qualifier   system                      -
                        /syntax=show_sym_sys
            qualifier   temporary                   -
                        /syntax=show_sym_tmp
            qualifier   unresolved                  -
                        /syntax=show_sym_unres
            qualifier   all                         -
                        /syntax=show_sym_all
            parameter   symbol          /id=1021    -
                        /type=$name                 -
                        /prompt="Symbol name"
        syntax          show_trace/id=147
        syntax          show_radix/id=146
        syntax          show_fault/id=145
        syntax          show_stack/id=139
            parameter   count/type=$rest_of_line/id=1031
            qualifier   all/id=1030
        syntax          show_usp/id=140
            parameter   count/type=$rest_of_line/id=1031
            qualifier   all/id=1030
        syntax          show_ssp/id=141
            parameter   count/type=$rest_of_line/id=1031
            qualifier   all/id=1030
        syntax          show_esp/id=142
            parameter   count/type=$rest_of_line/id=1031
            qualifier   all/id=1030
        syntax          show_ksp/id=143
            parameter   count/type=$rest_of_line/id=1031
            qualifier   all/id=1030
        syntax          show_isp/id=144
            parameter   count/type=$rest_of_line/id=1031
            qualifier   all/id=1030
        
        syntax          show_psl/id=135
        syntax          show_cpu/id=136
        syntax          show_base/id=137
        syntax          show_memory/id=138
            qualifier   statistics/id=1016
            qualifier   runtime/id=1010
            qualifier   full/id=1011

        syntax          show_step/id=134
        syntax          show_reg/id=133
        syntax          show_break/id=132
            qualifier	instructions/syntax=show_break_instr
            qualifier   faults/id=1014
            qualifier   addresses/id=1015
            disallow    faults and addresses
        syntax          show_string/id=121
        syntax          show_nvram/id=122
        syntax          show_error/id=123
            parameter   code/id=1005                -
                        /type=$rest_of_line
        syntax          show_mode/id=124
        syntax          show_shim/id=125
        syntax		show_break_instr/id=412
        syntax          show_watchpoints/id=411
        syntax          show_page/id=126
            qualifier   write/id=1006               -
                        /nonegatable
            qualifier   read/id=1007                -
                        /nonegatable
            parameter   address/id=1008             -
                        /type=$rest_of_line         -
                        /prompt="Address"
            disallow    read and write
        syntax          show_call_frames/id=127
            parameter   count/id=1009               -
                        /type=$rest_of_line
        syntax          show_quantum/id=128
        syntax          show_debug/id=129
        syntax          show_assembler_flags/id=130
        syntax          show_images/id=160
            qualifier	full/id=100
        syntax          show_share/id=161
        syntax          show_regions/id=162
        syntax		show_clock/id=500
        syntax          show_instructions/id=131
            qualifier   modes/id=1009
            qualifier   profile/id=1010
            qualifier   unimplemented/id=1011
            qualifier   all/id=1012
            parameter   opcode/id=1013              -
                        /type=$rest_of_line
            disallow    modes and profile
            disallow    modes and unimplemented
            disallow    modes and all
            disallow    unimplemented and all
            disallow    unimplemented and profile
            disallow    profile and all
        syntax          show_version/entry=exe$about            
     
end
