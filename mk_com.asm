.model small
	
.code

	org    100H	

	begin:
		jmp    main

	main PROC far

		mov    ax, 09H

	main ENDP
	
end begin

;; tasm mk_com
;; tlink /t mk_com