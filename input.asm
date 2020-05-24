
;	Really boring program to test the lib$get_input RTL replacement.  This example
;	uses all three arguments to prompt for a name and then echo it back to the user.


prompt:		.ascid	"What is your name? "
data:		.blkb 40
buff:		.long 40
			.long data
len:		.word 0
reply:		.ascid	"Your name is "

			.entry	input_test

			movl	#40, @#buff				;	Initialize the data desc length
			
			pushaw	@#len					;	We want the length written back here
			pushal	@#prompt				;	Here's the prompt string
			pushal	@#buff					;	And the place to write the input
			calls	#3, @#lib$get_input		;	Prompt and get input...
			
			movw	@#len, @#buff			;	Copy length to the data descriptor
			pushal	@#buff					;	Push data descriptor
			pushal	@#reply					;	And predicate text
			calls	#2, @#lib$put_output	;	Ape user input
			
			ret								;	Done!
			
			
						
			.end	input_test
			