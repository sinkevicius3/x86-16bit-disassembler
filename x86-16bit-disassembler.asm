.model small

.stack 100h

jumps ; auto generates far jumps

BUFFER_SIZE EQU 10
FILENAME_SIZE EQU 12

.data

  about db "This program outputs statistics of file(s) : number of symbols, words, lowercase and uppercase letters.", 13, 10
        db "homew2.exe [/?] destinationFile [sourceFile1] [sourceFile2] [...]", 13, 10
        db "[/?] - help", 13, 10, '$'

  err_source_msg            db "Could not open source file using handle.", 13, 10, '$'
  err_destination_msg       db "Could not create destination file using handle.", 13, 10, '$'
  err_filename_size         db "Error. Filename size with extension exceeds 12 characters.", 13, 10, '$'


  source_file               db FILENAME_SIZE + 1 dup (0)
  source_file_handler       dw ?
  destination_file          db FILENAME_SIZE + 1 dup (0)
  destination_file_handler  dw ?

  input_buffer        db 200, ?, 200 dup(0)
  buffer              db BUFFER_SIZE dup (?)

  symbols_count       dw 0
  words_count         dw 0
  lowercase_count     dw 0
  uppercase_count     dw 0
  inside_word         db 0                      ; inside word flag: 1 if inside word, 0 if outside

  number_str          db 6 dup (0), '$'
  result_line_buffer  db 50 dup ('$')

  debug               db "Bug", 13, 10, '$'

.code
  start:

    mov ax, @data
    mov ds, ax                                  ; move @data to ds (data segment)

    mov si, 81h                                 ; make si point to program parameters


    call skip_spaces


    ; Checking for program parameters
    mov al, byte ptr es:[si]
    cmp al, 0Dh                                 ; if no parameters (0Dh is Carriage Return in ascii)
    je show_help

    mov ax, word ptr es:[si]
    cmp ax, 3F2Fh                               ; if parameter == '/?' (3F is '?', 2F is '/' in ascii)
    je show_help

    ; Reading destination file name
    mov di, offset destination_file
    call read_filename
    cmp byte ptr ds:[destination_file], 0       ; if no destination file
    je show_help

    ; Creating destination file
    mov dx, offset destination_file
    mov ah, 3Ch                                 ; creates(truncates if existing) file using handle
    mov cx, 00h                                 ; no attributes
    int 21h
    jc err_destination
    mov destination_file_handler, ax

    ; Read first source file
    mov di, offset source_file
    call read_filename

    ; If no source files given, go to keyboard input
    cmp byte ptr ds:[source_file], 0
    jne source_file_loop

    keyboard_input:
      mov ah, 0Ah
      mov dx, offset input_buffer
      int 21h


      ; Print newline after user's input
      push ax dx
      mov ah, 02h
      mov dl, 0Dh
      int 21h
      mov dl, 0Ah
      int 21h
      pop dx ax

      ; Count user input
      call reset_counters
      mov si, offset input_buffer + 2
      xor ch, ch
      mov cl, [input_buffer + 1]
      call count
      call print_results
      jmp close_destination_file

    source_file_loop:
      cmp byte ptr ds:[source_file], 0
      je close_destination_file                 ; if no more files

      push si                                   ; saves SI to point to command line


      mov dx, offset source_file
      mov ah, 3Dh                               ; opens file using handle
      mov al, 00h                               ; read only
      int 21h
      jc err_source
      mov source_file_handler, ax


      call reset_counters


    read_source_file_loop:
      mov ah, 3Fh                               ; read from file or device using handle
      mov bx, source_file_handler
      mov cx, 0Ah                               ; number of bytes to read = BUFFER_SIZE                               
      mov dx, offset buffer
      int 21h
      jc err_source
      or ax, ax                                 ; ax is number of bytes read, 'or' updates the zero flag
      jz file_end

      ; mov ah, 09h
      ; mov dx, offset debug
      ; int 21h                                 ; print debug to console

      mov si, offset buffer
      mov cx, ax
      call count
      jmp read_source_file_loop

    file_end:
      mov ah, 3Eh                               ; close file using handle
      mov bx, source_file_handler
      int 21h

      call print_results

      pop si                                    ; restore SI to point to command line
      call skip_spaces                          ; skip spaces before next filename


      clear_source_filename_buffer:
        push cx di

        mov di, offset source_file
        mov cx, FILENAME_SIZE                   ; number of bytes for filename

        clear_loop:
          mov byte ptr [di], 0
          inc di
          dec cx
          cmp cx, 0
          jnz clear_loop                        ; jump if CX not zero

          pop di cx


      mov di, offset source_file
      call read_filename
      jmp source_file_loop


    show_help:
      mov	ah, 09h
      mov	dx, offset about       
      int	21h
      jmp terminate_process

    close_destination_file:
      mov bx, destination_file_handler
      mov ah, 3Eh
      int 21h

    terminate_process:
      mov ah, 4ch
      mov al, 00h                               ; move 00h to al (return code 0)
      int 21h                                   ; int 'Terminate process with return code'

    err_destination:
      mov dx, offset err_destination_msg
      mov ah, 09h
      int 21h
      jmp terminate_process

    err_source:
      mov dx, offset err_source_msg
      mov ah, 09h
      int 21h
      jmp terminate_process

    err_filename:
      mov dx, offset err_filename_size
      mov ah, 09h
      int 21h
      jmp terminate_process










    skip_spaces PROC near

      skip_spaces_loop:
        cmp byte ptr es:[si], 20h               ; 20h is ' ' in ascii
        jne skip_spaces_return
        inc si
        jmp skip_spaces_loop
      skip_spaces_return:
        ret

    skip_spaces ENDP


    read_filename PROC near

      push ax cx
      call skip_spaces

      xor cx, cx

      read_filename_start:
        cmp byte ptr es:[si], 0Dh               ; if no parameters (0Dh is Carriage Return in ascii)
        je read_filename_end
        cmp byte ptr es:[si], 20h               ; 20h is ' ' in ascii
        je read_filename_end

        mov al, [es:si]                         ; could use lodsb(es), copying the filename character in these 4 lines
        inc si
        mov [ds:di], al                         ; could use stosb(es)
        inc di
        inc cx
        cmp cx, 12
        ja err_filename
        jmp read_filename_start

      read_filename_end:
        mov al, 0
        mov [ds:di], al
        inc di
        pop cx ax
        ret

    read_filename ENDP


    count PROC near

      push ax bx cx di si

      count_loop:
        cmp cx, 0
        je count_end

        mov al, [si]                             ; move current char to al
        inc si
        dec cx

        cmp al, ' '
        je count_leave_word
        cmp al, 09h                              ; 09h is 'TAB' in ascii
        je count_leave_word
        cmp al, 0Dh                              ; 0Dh is 'CR' in ascii
        je count_leave_word
        cmp al, 0Ah                              ; 0Ah is 'LF' in ascii
        je count_leave_word

        mov bl, [ds:inside_word]                         
        cmp bl, 1                                ; inside word?
        je count_continue                        ; if yes, continue
        mov byte ptr [ds:inside_word], 1         ; if no, mark as inside word
        inc word ptr words_count                 ; and increment word count

        count_continue:
          cmp al, 21h                            ; 21h is '!' in ascii, first char we treat as a symbol
          jb count_loop
          cmp al, 7Eh                            ; 7Eh is '~' in ascii, last char we treat as a symbol
          ja count_loop
          inc word ptr symbols_count

          cmp al, 'A'
          jb count_not_upper
          cmp al, 'Z'
          ja count_not_upper
          inc word ptr uppercase_count

          count_not_upper:
            cmp al, 'a'
            jb count_loop
            cmp al, 'z'
            ja count_loop
            inc word ptr lowercase_count
            jmp count_loop

        count_leave_word:
          mov byte ptr [ds:inside_word], 0
          jmp count_loop

        count_end:
          pop si di cx bx ax
        ret

      count ENDP


    reset_counters PROC near

      push ax

      xor ax, ax
      mov symbols_count, ax
      mov words_count, ax
      mov lowercase_count, ax
      mov uppercase_count, ax
      mov byte ptr [inside_word], 0               ; inside word flag: 0 - outside word, 1 - inside word

      pop ax
      ret

    reset_counters ENDP


    number_to_string PROC near

    push ax bx cx dx

    mov bx, 10
    xor cx, cx

    number_to_string_loop:
      xor dx, dx
      div bx                                      ; divide ax by 10 (quotient ax, remainder dx)
      add dl, '0'
      
      push dx
      inc cx
      cmp ax, 0
      jne number_to_string_loop

    number_to_string_write:
      pop dx
      mov [si], dl
      inc si
      dec cx
      jnz number_to_string_write

    number_to_string_done:
      pop dx cx bx ax
      ret

    number_to_string ENDP


    print_results PROC near

      push ax bx cx dx si

      mov si, offset result_line_buffer

      mov ax, symbols_count
      call number_to_string
      mov dl, ' '
      mov [si], dl
      inc si

      mov ax, words_count
      call number_to_string
      mov dl, ' '
      mov [si], dl
      inc si

      mov ax, lowercase_count
      call number_to_string
      mov dl, ' '
      mov [si], dl
      inc si

      mov ax, uppercase_count
      call number_to_string

      mov dl, 13
      mov [si], dl
      inc si
      mov dl, 10
      mov [si], dl
      inc si

      mov cx, si                                  ; SI points to position after last char
      sub cx, offset result_line_buffer           ; subtract start address to get length

      mov dl, '$'
      mov [si], dl

      mov ah, 40h                                 ; write to file using handle
      mov bx, destination_file_handler
      mov dx, offset result_line_buffer
      int 21h

      mov ah, 09h
      mov dx, offset result_line_buffer
      int 21h                               ; print to console

      pop si dx cx bx ax

      ret

    print_results ENDP

  end start