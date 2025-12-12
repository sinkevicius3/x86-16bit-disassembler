.model small

.stack 100h

jumps                                           ; auto generates far jumps

BUFFER_SIZE EQU 10                              ; file reading buffer size
FILENAME_SIZE EQU 12                            ; maximum filename length (8.3 format)

.data

  about db "x86 16-bit mini disassembler", 13, 10
        db "disasm.exe source.com destination.asm", 13, 10, '$'
        db "disasm.exe [/?] - help", 13, 10, '$'


  err_source_msg            db "Error: Could not open source file.", 13, 10, '$'
  err_destination_msg       db "Error: Could not create destination file.", 13, 10, '$'


  source_file               db FILENAME_SIZE + 1 dup (0)
  source_file_handler       dw ?
  destination_file          db FILENAME_SIZE + 1 dup (0)
  destination_file_handler  dw ?

  
  buffer                    db BUFFER_SIZE dup (?)          ; file reading buffer
  output_line               db 150 dup ('$')                ; line output buffer
  

  hex_chars                 db '0123456789ABCDEF'           ; for hex conversion
  

  reg_names_8               db 'AL', 'CL', 'DL', 'BL', 'AH', 'CH', 'DH', 'BH'
  reg_names_16              db 'AX','CX','DX','BX','SP','BP','SI','DI'
  seg_reg_names             db 'ES','CS','SS','DS'


  offset_value              dw 100h              ; current offset (COM files start at 100h)
  buffer_pos                dw 0                 ; current position in buffer
  buffer_len                dw 0                 ; number of bytes in buffer
  current_segment_prefix    db 0                 ; segment override prefix (0=none, 26h=ES:, 2Eh=CS:, 36h=SS:, 3Eh=DS:)
  saved_modrm               db 0                 ; saved ModR/M byte
  saved_disp_low            db 0                 ; saved displacement low byte
  saved_disp_high           db 0                 ; saved displacement high byte

  mov_byte_ptr_str          db 'mov byte ptr '
  mov_word_ptr_str          db 'mov word ptr '

.code
  start:
    mov ax, @data
    mov ds, ax                                  ; set data segment

    mov si, 81h                                 ; SI points to command line parameters (PSP offset 81h)
    call skip_spaces                            ; skip leading spaces

    ; Check if any parameters
    mov al, byte ptr es:[si]
    cmp al, 0Dh                                 ; 0Dh = Carriage Return (no parameters)
    je show_help                                ; if no params, show help

    ; Check for /? help parameter
    mov ax, word ptr es:[si]
    cmp ax, 3F2Fh                               ; 3F2Fh = '/?' (2Fh='/', 3Fh='?')
    je show_help

    ; Read source filename
    mov di, offset source_file
    call read_filename
    cmp byte ptr ds:[source_file], 0            ; check if source file was read
    je show_help                                ; if empty, show help

    ; Read destination filename
    mov di, offset destination_file
    call read_filename
    cmp byte ptr ds:[destination_file], 0       ; check if destination file was read
    je show_help                                ; if empty, show help

    ; Check if any extra parameters (only 2 filenames allowed)
    call skip_spaces
    mov al, byte ptr es:[si]
    cmp al, 0Dh                                 ; should be end of line now
    jne show_help                               ; if more params, show help

    ; Open source file for reading
    mov dx, offset source_file
    mov ah, 3Dh                                 ; open file
    mov al, 00h                                 ; read-only mode
    int 21h
    jc err_source                               ; if error (carry flag set), jump
    mov source_file_handler, ax                 ; save file handle

    ; Create destination file
    mov dx, offset destination_file
    mov ah, 3Ch                                 ; create/truncate file
    mov cx, 00h                                 ; normal file attributes
    int 21h
    jc err_destination                          ; if error, jump
    mov destination_file_handler, ax            ; save file handle

    ; Initialize vars
    mov offset_value, 100h                      ; COM files start at offset 100h
    mov buffer_pos, 0
    mov buffer_len, 0

    ; Main disassembly loop
    disasm_loop:
      call get_next_byte                        ; read next byte from file
      jc close_files                            ; if error or EOF, close files
      
      call disassemble_instruction
      jmp disasm_loop                           ; continue looping

    close_files:
      mov ah, 3Eh                               ; close source file
      mov bx, source_file_handler
      int 21h
      
      mov ah, 3Eh                               ; close destination file
      mov bx, destination_file_handler
      int 21h
      jmp terminate_process

    show_help:
      mov ah, 09h
      mov dx, offset about                      ; print help('about')
      int 21h
      jmp terminate_process

    err_source:
      mov dx, offset err_source_msg
      mov ah, 09h
      int 21h
      jmp terminate_process

    err_destination:
      mov dx, offset err_destination_msg
      mov ah, 09h
      int 21h
      jmp terminate_process

    terminate_process:
      mov ah, 4ch                               ; terminate program
      mov al, 00h                               ; return code 0 (success)
      int 21h

    ; ~~~ PROCEDURES ~~~
 
    skip_spaces PROC near
      skip_spaces_loop:
        cmp byte ptr es:[si], 20h               ; 20h = space character
        jne skip_spaces_return
        inc si                                  ; move to next character
        jmp skip_spaces_loop
      skip_spaces_return:
        ret
    skip_spaces ENDP

    ; Input: SI points to command line, DI points to destination buffer
    ; Output: filename copied to buffer, SI updated
    read_filename PROC near
      push ax cx
      call skip_spaces                          ; skip spaces before filename
      xor cx, cx                                ; CX = character counter
      
      read_filename_start:
        cmp byte ptr es:[si], 0Dh               ; check for end of line
        je read_filename_end
        cmp byte ptr es:[si], 20h               ; check for space
        je read_filename_end
        
        mov al, [es:si]                         ; read character from command line
        inc si
        mov [ds:di], al                         ; write character to buffer
        inc di
        inc cx
        cmp cx, 12                              ; check filename length limit
        ja read_filename_end                    ; if too long, stop
        jmp read_filename_start
      
      read_filename_end:
        mov al, 0                               ; null terminator
        mov [ds:di], al
        pop cx ax
        ret
    read_filename ENDP

    ; Output: AL = byte, carry flag set if error/EOF
    get_next_byte PROC near
      push bx cx dx
      
      mov bx, buffer_pos                        ; get current position in buffer
      cmp bx, buffer_len                        ; check if we reached end of buffer
      jl get_from_buffer
      
      ; Buffer empty = read new bytes from file
      mov ah, 3Fh                               ; read from file
      mov bx, source_file_handler
      mov cx, BUFFER_SIZE                       ; read BUFFER_SIZE number of bytes
      mov dx, offset buffer
      int 21h
      jc get_byte_error                         ; if error, exit
      
      cmp ax, 0                                 ; check if any bytes read
      je get_byte_error                         ; if EOF, exit
      
      mov buffer_len, ax                        ; save number of bytes read
      mov buffer_pos, 0                         ; reset position to start
      mov bx, 0
      
      get_from_buffer:
        mov si, offset buffer
        add si, bx                              ; SI = buffer + position
        mov al, [si]                            ; read byte from buffer
        inc buffer_pos                          ; move to next position
        clc                                     ; clear carry flag (success)
        pop dx cx bx
        ret
      
      get_byte_error:
        stc                                     ; set carry flag (error happened)
        pop dx cx bx
        ret
    get_next_byte ENDP

    ; Input: AL = byte, representing OPCODE
    disassemble_instruction PROC near
      push ax bx cx dx si di
      
      mov bl, al                                ; move opcode to bl
      mov di, offset output_line                ; DI points to output buffer
      
      ; Clear output line buffer so we're not printing old instructions
      ; (not efficient but it works tho :D)
      push di
      mov cx, 150
      clear_loop:
        mov byte ptr [di], ' '
        inc di
        loop clear_loop
      pop di
      
      ; Write instruction's offset address (e.g. 0010: )
      mov ax, offset_value
      call write_hex_word                       ; write offset as hex
      mov al, ':'
      mov [di], al
      inc di
      mov al, ' '
      mov [di], al
      inc di
      
      mov al, bl
      mov current_segment_prefix, 0             ; reset segment prefix
      
      ; Check for segment override prefixes
      cmp al, 26h                               ; ES:
      je handle_seg_prefix
      cmp al, 2Eh                               ; CS:
      je handle_seg_prefix
      cmp al, 36h                               ; SS:
      je handle_seg_prefix
      cmp al, 3Eh                               ; DS:
      je handle_seg_prefix
      jmp check_mov_opcodes
      
      handle_seg_prefix:
        mov current_segment_prefix, al          ; save prefix
        call write_hex_byte                     ; write prefix byte
        mov al, ' '
        mov [di], al
        inc di
        inc offset_value                        ; increment offset for prefix
        call get_next_byte                      ; get actual opcode
        jc disasm_end
        mov bl, al                              ; update opcode
      
      check_mov_opcodes:
      mov al, bl

      ; [OUT imm8, AL] (E6h ~ 1110 0110)
      cmp al, 0E6h
      je handle_out_E6
      ; [OUT imm8, AX] (E7h ~ 1110 0111)
      cmp al, 0E7h
      je handle_out_E7
      
      ; [OUT DX, AL] (EEh ~ 1110 1110)
      cmp al, 0EEh
      je handle_out_EE
      ; [OUT DX, AX] (EFh ~ 1110 1111)
      cmp al, 0EFh
      je handle_out_EF
      
      ; [MOV reg/mem8, reg8] (88h ~ 1000 1000)
      cmp al, 88h
      je handle_mov_88
      ; [MOV reg/mem16, reg16] (89h ~ 1000 1001)
      cmp al, 89h
      je handle_mov_89
      ; [MOV reg8, reg/mem8] (8Ah ~ 1000 1010)
      cmp al, 8Ah
      je handle_mov_8A
      ; [MOV reg16, reg/mem16] (8Bh ~ 1000 1011)
      cmp al, 8Bh
      je handle_mov_8B
      
      ; [MOV reg, immediate] (B0h-BFh ~ 1011 wreg)
      cmp al, 0B0h
      jl not_mov_imm
      cmp al, 0BFh
      jg not_mov_imm
      jmp handle_mov_imm
      
      not_mov_imm:
      ; [MOV mem/reg8, immediate] (C6h ~ 1100 0110)
      cmp al, 0C6h
      je handle_mov_C6
      ; [MOV mem/reg16, immediate] (C7h ~ 1100 0111)
      cmp al, 0C7h
      je handle_mov_C7
      
      ; [MOV AL, memory] (A0h ~ 1010 0000)
      cmp al, 0A0h
      je handle_mov_A0
      ; [MOV AX, memory] (A1h ~ 1010 0001)
      cmp al, 0A1h
      je handle_mov_A1
      
      ; [MOV memory, AL] (A2h ~ 1010 0010)
      cmp al, 0A2h
      je handle_mov_A2
      ; [MOV memory, AX] (A3h ~ 1010 0011)
      cmp al, 0A3h
      je handle_mov_A3

      ; [MOV reg/mem, segment reg] (8Ch ~ 1000 1100)
      cmp al, 8Ch
      je handle_mov_8C

      ; [MOV segment reg, reg/mem] (8Eh ~ 1000 1110)
      cmp al, 8Eh
      je handle_mov_8E

      ; [NOT reg/mem8] (F6h ~ 1111 0110, reg field = 010)
      cmp al, 0F6h
      je handle_not_F6
      ; [NOT reg/mem16] (F7h ~ 1111 0111, reg field = 010)
      cmp al, 0F7h
      je handle_not_F7
      
      ; Unrecognized instruction
      jmp handle_unrecognized
      
      ; [MOV reg/mem8, reg8] (88h ~ 1000 1000)
      handle_mov_88:
        mov al, bl
        call write_hex_byte                     ; write opcode
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte                      ; get ModR/M byte
        jc disasm_end
        mov saved_modrm, al
        call write_hex_byte                     ; write ModR/M byte
        mov al, ' '
        mov [di], al
        inc di
        call read_displacement
        call pad_to_mnemonic
        call write_mov_string
        mov al, saved_modrm
        mov bl, 0                               ; 0 = 8-bit operand
        call decode_modrm_rm                    ; write destination (r/m field)
        mov byte ptr [di], ','
        inc di
        mov al, saved_modrm
        call decode_modrm_reg_8                 ; write source (reg field, 8-bit)
        inc offset_value
        inc offset_value
        jmp write_output

      ; [MOV reg/mem16, reg16] (89h ~ 1000 1001)
      handle_mov_89:
        mov al, bl
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte
        jc disasm_end
        mov saved_modrm, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call read_displacement
        call pad_to_mnemonic
        call write_mov_string
        mov al, saved_modrm
        mov bl, 1                               ; 1 = 16-bit operand
        call decode_modrm_rm                    ; write destination (r/m field)
        mov byte ptr [di], ','
        inc di
        mov al, saved_modrm
        call decode_modrm_reg_16                ; write source (reg field, 16-bit)
        inc offset_value
        inc offset_value
        jmp write_output

      ; [MOV reg8, reg/mem8] (8Ah ~ 1000 1010)
      handle_mov_8A:
        mov al, bl
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte
        jc disasm_end
        mov saved_modrm, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call read_displacement
        call pad_to_mnemonic
        call write_mov_string
        mov al, saved_modrm
        call decode_modrm_reg_8                 ; write destination (reg field, 8-bit)
        mov byte ptr [di], ','
        inc di
        mov al, saved_modrm
        mov bl, 0                               ; 0 = 8-bit operand
        call decode_modrm_rm                    ; write source (r/m field)
        inc offset_value
        inc offset_value
        jmp write_output

      ; [MOV reg16, reg/mem16] (8Bh ~ 1000 1011)
      handle_mov_8B:
        mov al, bl
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte
        jc disasm_end
        mov saved_modrm, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call read_displacement
        call pad_to_mnemonic
        call write_mov_string
        mov al, saved_modrm
        call decode_modrm_reg_16                ; write destination (reg field, 16-bit)
        mov byte ptr [di], ','
        inc di
        mov al, saved_modrm
        mov bl, 1                               ; 1 = 16-bit operand
        call decode_modrm_rm                    ; write source (r/m field)
        inc offset_value
        inc offset_value
        jmp write_output

      ; [MOV reg, immediate] (B0h-BFh ~ 1011 wreg)
      handle_mov_imm:
        mov al, bl
        call write_hex_byte                     ; write opcode
        mov al, ' '
        mov [di], al
        inc di
        
        ; Check if 8-bit or 16-bit (bit 3 of opcode)
        mov al, bl
        and al, 08h                             ; test bit 3
        cmp al, 0
        jne mov_imm_16                          ; if bit 3 = 1, it's 16-bit
        
        ; 8-bit immediate
        call get_next_byte                      ; get immediate value
        jc disasm_end
        mov cl, al                              ; save immediate in CL
        call write_hex_byte                     ; write immediate byte
        mov al, ' '
        mov [di], al
        inc di
        call pad_to_mnemonic
        call write_mov_string
        mov al, bl
        and al, 07h                             ; get register number (bits 0-2)
        call write_reg_8                        ; write 8-bit register name
        mov byte ptr [di], ','
        inc di
        mov al, cl
        call write_hex_byte                     ; write immediate value
        mov byte ptr [di], 'h'                  ; append 'h' for hex
        inc di
        inc offset_value
        inc offset_value
        jmp write_output
        
      mov_imm_16:
        ; 16-bit immediate
        call get_next_byte                      ; get low byte
        jc disasm_end
        mov cl, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte                      ; get high byte
        jc disasm_end
        mov ch, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call pad_to_mnemonic
        call write_mov_string
        mov al, bl
        and al, 07h                             ; get register number
        call write_reg_16                       ; write 16-bit register name
        mov byte ptr [di], ','
        inc di
        mov ax, cx                              ; AX = immediate word (CH:CL)
        call write_hex_word                     ; write immediate value
        mov byte ptr [di], 'h'
        inc di
        add offset_value, 3                     ; opcode + 2 immediate bytes
        jmp write_output

      ; [MOV mem/reg8, immediate] (C6h ~ 1100 0110)
      handle_mov_C6:
        mov al, bl
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte
        jc disasm_end
        mov saved_modrm, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call read_displacement
        call get_next_byte                      ; get immediate byte
        jc disasm_end
        push ax
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call pad_to_mnemonic
        call write_mov_byte_ptr                 ; write "mov byte ptr "
        mov al, saved_modrm
        mov bl, 0                               ; 0 = 8-bit
        call decode_modrm_rm
        mov byte ptr [di], ','
        inc di
        pop ax
        call write_hex_byte
        mov byte ptr [di], 'h'
        inc di
        add offset_value, 3
        jmp write_output

      ; [MOV mem/reg16, immediate] (C7h ~ 1100 0111)
      handle_mov_C7:
        mov al, bl
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte
        jc disasm_end
        mov saved_modrm, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call read_displacement
        call get_next_byte                      ; get immediate low byte
        jc disasm_end
        mov ch, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte                      ; get immediate high byte
        jc disasm_end
        push ax
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call pad_to_mnemonic
        call write_mov_word_ptr                 ; write "mov word ptr "
        mov al, saved_modrm
        mov bl, 1                               ; 1 = 16-bit
        call decode_modrm_rm
        mov byte ptr [di], ','
        inc di
        pop ax
        mov ah, al
        mov al, ch
        call write_hex_word
        mov byte ptr [di], 'h'
        inc di
        add offset_value, 4
        jmp write_output

      ; [MOV AL, memory] (A0h ~ 1010 0000)
      handle_mov_A0:
        mov al, bl
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte                      ; get offset low byte
        jc disasm_end
        mov cl, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte                      ; get offset high byte
        jc disasm_end
        mov ch, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call pad_to_mnemonic
        call write_mov_string
        mov byte ptr [di], 'A'
        inc di
        mov byte ptr [di], 'L'
        inc di
        mov byte ptr [di], ','
        inc di
        call write_segment_prefix               ; write ES:, CS:, SS:, or DS: if present
        mov byte ptr [di], '['
        inc di
        mov ax, cx
        call write_hex_word
        mov byte ptr [di], 'h'
        inc di
        mov byte ptr [di], ']'
        inc di
        add offset_value, 3
        jmp write_output

      ; [MOV AX, memory] (A1h ~ 1010 0001)
      handle_mov_A1:
        mov al, bl
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte
        jc disasm_end
        mov cl, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte
        jc disasm_end
        mov ch, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call pad_to_mnemonic
        call write_mov_string
        mov byte ptr [di], 'A'
        inc di
        mov byte ptr [di], 'X'
        inc di
        mov byte ptr [di], ','
        inc di
        call write_segment_prefix
        mov byte ptr [di], '['
        inc di
        mov ax, cx
        call write_hex_word
        mov byte ptr [di], 'h'
        inc di
        mov byte ptr [di], ']'
        inc di
        add offset_value, 3
        jmp write_output

      ; [MOV memory, AL] (A2h ~ 1010 0010)
      handle_mov_A2:
        mov al, bl
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte
        jc disasm_end
        mov cl, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte
        jc disasm_end
        mov ch, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call pad_to_mnemonic
        call write_mov_string
        call write_segment_prefix
        mov byte ptr [di], '['
        inc di
        mov ax, cx
        call write_hex_word
        mov byte ptr [di], 'h'
        inc di
        mov byte ptr [di], ']'
        inc di
        mov byte ptr [di], ','
        inc di
        mov byte ptr [di], 'A'
        inc di
        mov byte ptr [di], 'L'
        inc di
        add offset_value, 3
        jmp write_output

      ; [MOV memory, AX] (A3h ~ 1010 0011)
      handle_mov_A3:
        mov al, bl
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte
        jc disasm_end
        mov cl, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte
        jc disasm_end
        mov ch, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call pad_to_mnemonic
        call write_mov_string
        call write_segment_prefix
        mov byte ptr [di], '['
        inc di
        mov ax, cx
        call write_hex_word
        mov byte ptr [di], 'h'
        inc di
        mov byte ptr [di], ']'
        inc di
        mov byte ptr [di], ','
        inc di
        mov byte ptr [di], 'A'
        inc di
        mov byte ptr [di], 'X'
        inc di
        add offset_value, 3
        jmp write_output

      ; [MOV reg/mem, segment reg] (8Ch ~ 1000 1100)
      handle_mov_8C:
        mov al, bl
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte
        jc disasm_end
        mov saved_modrm, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call read_displacement
        call pad_to_mnemonic
        call write_mov_string
        mov al, saved_modrm
        mov bl, 1                               ; 1 = 16-bit
        call decode_modrm_rm                    ; write destination (r/m field)
        mov byte ptr [di], ','
        inc di
        mov al, saved_modrm
        call decode_modrm_segreg                ; write source (segment register)
        inc offset_value
        inc offset_value
        jmp write_output

      ; [MOV segment reg, reg/mem] (8Eh ~ 1000 1110)
      handle_mov_8E:
        mov al, bl
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte
        jc disasm_end
        mov saved_modrm, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call read_displacement
        call pad_to_mnemonic
        call write_mov_string
        mov al, saved_modrm
        call decode_modrm_segreg                ; write destination (segment register)
        mov byte ptr [di], ','
        inc di
        mov al, saved_modrm
        mov bl, 1                               ; 1 = 16-bit
        call decode_modrm_rm                    ; write source (r/m field)
        inc offset_value
        inc offset_value
        jmp write_output

      ; [OUT imm8, AL] (E6h ~ 1110 0110)
      handle_out_E6:
        mov al, bl
        call write_hex_byte                     ; write opcode
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte                      ; get immediate port number
        jc disasm_end
        mov cl, al                              ; save port in CL
        call write_hex_byte                     ; write port byte
        mov al, ' '
        mov [di], al
        inc di
        call pad_to_mnemonic
        call write_out_string                   ; write "out "
        mov al, cl
        call write_hex_byte                     ; write port number
        mov byte ptr [di], 'h'
        inc di
        mov byte ptr [di], ','
        inc di
        mov byte ptr [di], 'A'
        inc di
        mov byte ptr [di], 'L'
        inc di
        add offset_value, 2                     ; opcode + immediate byte
        jmp write_output

      ; [OUT imm8, AX] (E7h ~ 1110 0111)
      handle_out_E7:
        mov al, bl
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte                      ; get immediate port number
        jc disasm_end
        mov cl, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call pad_to_mnemonic
        call write_out_string
        mov al, cl
        call write_hex_byte
        mov byte ptr [di], 'h'
        inc di
        mov byte ptr [di], ','
        inc di
        mov byte ptr [di], 'A'
        inc di
        mov byte ptr [di], 'X'
        inc di
        add offset_value, 2
        jmp write_output

      ; [OUT DX, AL] (EEh ~ 1110 1110)
      handle_out_EE:
        mov al, bl
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call pad_to_mnemonic
        call write_out_string
        mov byte ptr [di], 'D'
        inc di
        mov byte ptr [di], 'X'
        inc di
        mov byte ptr [di], ','
        inc di
        mov byte ptr [di], 'A'
        inc di
        mov byte ptr [di], 'L'
        inc di
        inc offset_value
        jmp write_output

      ; [OUT DX, AX] (EFh ~ 1110 1111)
      handle_out_EF:
        mov al, bl
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call pad_to_mnemonic
        call write_out_string
        mov byte ptr [di], 'D'
        inc di
        mov byte ptr [di], 'X'
        inc di
        mov byte ptr [di], ','
        inc di
        mov byte ptr [di], 'A'
        inc di
        mov byte ptr [di], 'X'
        inc di
        inc offset_value
        jmp write_output  

       ; [NOT reg/mem8] (F6h ~ 1111 0110)
      handle_not_F6:
        mov al, bl
        call write_hex_byte                     ; write opcode
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte                      ; get ModR/M byte
        jc disasm_end
        mov saved_modrm, al
        call write_hex_byte                     ; write ModR/M byte
        mov al, ' '
        mov [di], al
        inc di
        
        ; Check if reg field = 010 (NOT instruction)
        mov al, saved_modrm
        shr al, 3
        and al, 07h                             ; extract reg field
        cmp al, 2                               ; must be 010 (2)
        jne handle_unrecognized_f6              ; if not, it's a different F6 instruction
        
        call read_displacement
        call pad_to_mnemonic
        call write_not_string                   ; write "not "
        mov al, saved_modrm
        mov bl, 0                               ; 0 = 8-bit operand
        call decode_modrm_rm                    ; write operand (r/m field)
        add offset_value, 2
        jmp write_output
        
      handle_unrecognized_f6:
        ; F6 with different reg field - treat as unknown
        call pad_to_mnemonic
        mov byte ptr [di], 'U'
        inc di
        mov byte ptr [di], 'n'
        inc di
        mov byte ptr [di], 'k'
        inc di
        mov byte ptr [di], 'n'
        inc di
        mov byte ptr [di], 'o'
        inc di
        mov byte ptr [di], 'w'
        inc di
        mov byte ptr [di], 'n'
        inc di
        add offset_value, 2
        jmp write_output

      ; [NOT reg/mem16] (F7h ~ 1111 0111)
      handle_not_F7:
        mov al, bl
        call write_hex_byte                     ; write opcode
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte                      ; get ModR/M byte
        jc disasm_end
        mov saved_modrm, al
        call write_hex_byte                     ; write ModR/M byte
        mov al, ' '
        mov [di], al
        inc di
        
        ; Check if reg field = 010 (NOT instruction)
        mov al, saved_modrm
        shr al, 3
        and al, 07h                             ; extract reg field
        cmp al, 2                               ; must be 010 (2)
        jne handle_unrecognized_f7              ; if not, it's a different F7 instruction
        
        call read_displacement
        call pad_to_mnemonic
        call write_not_string                   ; write "not "
        mov al, saved_modrm
        mov bl, 1                               ; 1 = 16-bit operand
        call decode_modrm_rm                    ; write operand (r/m field)
        add offset_value, 2
        jmp write_output
        
      handle_unrecognized_f7:
        ; F7 with different reg field - treat as unknown
        call pad_to_mnemonic
        mov byte ptr [di], 'U'
        inc di
        mov byte ptr [di], 'n'
        inc di
        mov byte ptr [di], 'k'
        inc di
        mov byte ptr [di], 'n'
        inc di
        mov byte ptr [di], 'o'
        inc di
        mov byte ptr [di], 'w'
        inc di
        mov byte ptr [di], 'n'
        inc di
        add offset_value, 2
        jmp write_output

      ; Unrecognized byte - output as "Unknown"
      handle_unrecognized:
        mov al, bl
        call write_hex_byte                     ; write opcode byte
        mov al, ' '
        mov [di], al
        inc di
        call pad_to_mnemonic
        ; Write "Unknown"
        mov byte ptr [di], 'U'
        inc di
        mov byte ptr [di], 'n'
        inc di
        mov byte ptr [di], 'k'
        inc di
        mov byte ptr [di], 'n'
        inc di
        mov byte ptr [di], 'o'
        inc di
        mov byte ptr [di], 'w'
        inc di
        mov byte ptr [di], 'n'
        inc di
        inc offset_value                        ; move to next byte
        jmp write_output
      
      ; Write output line to file
      write_output:
        mov al, 13                              ; CR
        mov [di], al
        inc di
        mov al, 10                              ; LF
        mov [di], al
        inc di
        mov al, '$'                             ; string terminator
        mov [di], al
        
        ; Calculate actual string length (up to CR)
        push di
        mov di, offset output_line
        xor cx, cx
        count_len:
          mov al, [di]
          cmp al, 13
          je found_cr
          inc di
          inc cx
          jmp count_len
        found_cr:
        add cx, 2                               ; Include CR and LF
        pop di
        
        mov ah, 40h                             ; DOS: write to file
        mov bx, destination_file_handler
        mov dx, offset output_line
        int 21h
        
      disasm_end:
        pop di si dx cx bx ax
        ret
    disassemble_instruction ENDP

    ; Output: writes "mov " to output buffer
    write_mov_string PROC near
      push ax
      mov byte ptr [di], 'm'
      inc di
      mov byte ptr [di], 'o'
      inc di
      mov byte ptr [di], 'v'
      inc di
      mov byte ptr [di], ' '
      inc di
      pop ax
      ret
    write_mov_string ENDP

    ; Output: writes "mov byte ptr " to output buffer
    write_mov_byte_ptr PROC near
      push ax si cx
      mov si, offset mov_byte_ptr_str
      mov cx, 13                                ; length of "mov byte ptr " is 13
      wmb_loop:
        mov al, [si]
        mov [di], al
        inc si
        inc di
        loop wmb_loop
      pop cx si ax
      ret
    write_mov_byte_ptr ENDP

    ; Output: writes "mov word ptr " to output buffer
    write_mov_word_ptr PROC near
      push ax si cx
      mov si, offset mov_word_ptr_str
      mov cx, 13                                ; length of "mov word ptr " is 13
      wmw_loop:
        mov al, [si]
        mov [di], al
        inc si
        inc di
        loop wmw_loop
      pop cx si ax
      ret
    write_mov_word_ptr ENDP

    ; Output: writes "out " to output buffer
    write_out_string PROC near
      push ax
      mov byte ptr [di], 'o'
      inc di
      mov byte ptr [di], 'u'
      inc di
      mov byte ptr [di], 't'
      inc di
      mov byte ptr [di], ' '
      inc di
      pop ax
      ret
    write_out_string ENDP

    ; Output: writes "not " to output buffer
    write_not_string PROC near
      push ax
      mov byte ptr [di], 'n'
      inc di
      mov byte ptr [di], 'o'
      inc di
      mov byte ptr [di], 't'
      inc di
      mov byte ptr [di], ' '
      inc di
      pop ax
      ret
    write_not_string ENDP

    ; Input: saved_modrm contains the ModR/M byte
    ; Output: displacement bytes written to output and saved in saved_disp_low/saved_disp_high
    read_displacement PROC near
      push ax bx
      mov al, saved_modrm
      mov bl, al
      shr bl, 6                                 ; extract MOD field (bits 6-7)
      cmp bl, 0                                 ; MOD = 00
      je check_rm_110
      cmp bl, 1                                 ; MOD = 01 (8-bit displacement)
      je read_disp8
      cmp bl, 2                                 ; MOD = 10 (16-bit displacement)
      je read_disp16
      jmp rd_done
      check_rm_110:
        mov al, saved_modrm
        and al, 07h                             ; extract R/M field
        cmp al, 06h                             ; R/M = 110 (direct address)
        je read_disp16
        jmp rd_done
      read_disp8:
        call get_next_byte                      ; read 8-bit displacement
        jc rd_done
        mov saved_disp_low, al
        mov saved_disp_high, 0
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        inc offset_value
        jmp rd_done
      read_disp16:
        call get_next_byte                      ; read displacement low byte
        jc rd_done
        mov saved_disp_low, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        call get_next_byte                      ; read displacement high byte
        jc rd_done
        mov saved_disp_high, al
        call write_hex_byte
        mov al, ' '
        mov [di], al
        inc di
        add offset_value, 2
      rd_done:
        pop bx ax
        ret
    read_displacement ENDP

    ; Input: AL = ModR/M byte, BL = 0 for 8-bit, 1 for 16-bit
    ; Output: writes register or memory operand to output buffer
    decode_modrm_rm PROC near
      push ax bx cx
      mov bh, al
      shr bh, 6                                 ; extract MOD field
      cmp bh, 3                                 ; MOD = 11 (register mode)
      je rm_register_mode
      
      ; Memory addressing modes (MOD = 00, 01, 10)
      call write_segment_prefix                 ; write segment override if present
      mov byte ptr [di], '['
      inc di
      mov al, saved_modrm
      and al, 07h                               ; extract R/M field
      cmp bh, 0
      je rm_mod00
      cmp bh, 1
      je rm_mod01
      cmp bh, 2
      je rm_mod10
      
      rm_mod00:                                 ; MOD = 00 (no displacement or direct address)
        cmp al, 06h                             ; R/M = 110 (direct address)
        je rm_direct_addr
        call write_rm_addressing                ; write addressing mode (e.g., BX+SI)
        jmp rm_close_bracket
      rm_direct_addr:
        mov al, saved_disp_high
        call write_hex_byte
        mov al, saved_disp_low
        call write_hex_byte
        mov byte ptr [di], 'h'
        inc di
        jmp rm_close_bracket
      rm_mod01:                                 ; MOD = 01 (8-bit displacement)
        call write_rm_addressing
        mov byte ptr [di], '+'
        inc di
        mov al, saved_disp_low
        call write_hex_byte
        mov byte ptr [di], 'h'
        inc di
        jmp rm_close_bracket
      rm_mod10:                                 ; MOD = 10 (16-bit displacement)
        call write_rm_addressing
        mov byte ptr [di], '+'
        inc di
        mov al, saved_disp_high
        call write_hex_byte
        mov al, saved_disp_low
        call write_hex_byte
        mov byte ptr [di], 'h'
        inc di
      rm_close_bracket:
        mov byte ptr [di], ']'
        inc di
        jmp rm_done
      
      rm_register_mode:                         ; MOD = 11 (register mode)
        mov al, saved_modrm
        and al, 07h                             ; extract register number
        cmp bl, 0
        je rm_reg8
        call write_reg_16                       ; write 16-bit register
        jmp rm_done
      rm_reg8:
        call write_reg_8                        ; write 8-bit register
      rm_done:
        pop cx bx ax
        ret
    decode_modrm_rm ENDP

    ; Input: AL = R/M field value (0-7)
    ; Output: writes addressing mode to output buffer
    write_rm_addressing PROC near
      push ax bx cx si
      and al, 07h
      cmp al, 0
      jne wra_1
      ; R/M = 000 (BX+SI)
      mov byte ptr [di], 'B'
      inc di
      mov byte ptr [di], 'X'
      inc di
      mov byte ptr [di], '+'
      inc di
      mov byte ptr [di], 'S'
      inc di
      mov byte ptr [di], 'I'
      inc di
      jmp wra_done
      wra_1:
      cmp al, 1
      jne wra_2
      ; R/M = 001 (BX+DI)
      mov byte ptr [di], 'B'
      inc di
      mov byte ptr [di], 'X'
      inc di
      mov byte ptr [di], '+'
      inc di
      mov byte ptr [di], 'D'
      inc di
      mov byte ptr [di], 'I'
      inc di
      jmp wra_done
      wra_2:
      cmp al, 2
      jne wra_3
      ; R/M = 010 (BP+SI)
      mov byte ptr [di], 'B'
      inc di
      mov byte ptr [di], 'P'
      inc di
      mov byte ptr [di], '+'
      inc di
      mov byte ptr [di], 'S'
      inc di
      mov byte ptr [di], 'I'
      inc di
      jmp wra_done
      wra_3:
      cmp al, 3
      jne wra_4
      ; R/M = 011 (BP+DI)
      mov byte ptr [di], 'B'
      inc di
      mov byte ptr [di], 'P'
      inc di
      mov byte ptr [di], '+'
      inc di
      mov byte ptr [di], 'D'
      inc di
      mov byte ptr [di], 'I'
      inc di
      jmp wra_done
      wra_4:
      cmp al, 4
      jne wra_5
      ; R/M = 100 (SI)
      mov byte ptr [di], 'S'
      inc di
      mov byte ptr [di], 'I'
      inc di
      jmp wra_done
      wra_5:
      cmp al, 5
      jne wra_6
      ; R/M = 101 (DI)
      mov byte ptr [di], 'D'
      inc di
      mov byte ptr [di], 'I'
      inc di
      jmp wra_done
      wra_6:
      cmp al, 6
      jne wra_7
      ; R/M = 110 (BP)
      mov byte ptr [di], 'B'
      inc di
      mov byte ptr [di], 'P'
      inc di
      jmp wra_done
      wra_7:
      ; R/M = 111 (BX)
      mov byte ptr [di], 'B'
      inc di
      mov byte ptr [di], 'X'
      inc di
      wra_done:
        pop si cx bx ax
        ret
    write_rm_addressing ENDP

    ; Output: writes ES:, CS:, SS:, or DS: to output buffer
    write_segment_prefix PROC near
      push ax
      mov al, current_segment_prefix
      cmp al, 0
      je wsp_done
      cmp al, 26h
      je wsp_es
      cmp al, 2Eh
      je wsp_cs
      cmp al, 36h
      je wsp_ss
      cmp al, 3Eh
      je wsp_ds
      wsp_es:
        mov byte ptr [di], 'E'
        inc di
        mov byte ptr [di], 'S'
        inc di
        mov byte ptr [di], ':'
        inc di
        jmp wsp_done
      wsp_cs:
        mov byte ptr [di], 'C'
        inc di
        mov byte ptr [di], 'S'
        inc di
        mov byte ptr [di], ':'
        inc di
        jmp wsp_done
      wsp_ss:
        mov byte ptr [di], 'S'
        inc di
        mov byte ptr [di], 'S'
        inc di
        mov byte ptr [di], ':'
        inc di
        jmp wsp_done
      wsp_ds:
        mov byte ptr [di], 'D'
        inc di
        mov byte ptr [di], 'S'
        inc di
        mov byte ptr [di], ':'
        inc di
      wsp_done:
        pop ax
        ret
    write_segment_prefix ENDP

    ; Input: DI = current write pointer
    ; Output: DI moved to create some space to mnemonic
    pad_to_mnemonic PROC near
      push ax cx si
      mov si, offset output_line
      mov cx, di
      sub cx, si                                ; CX = number of characters currently written
      mov ax, 24                                ; mnemonic column position
      pad_loop:
        cmp cx, ax
        jge pad_done
        mov byte ptr [di], ' '
        inc di
        inc cx
        jmp pad_loop
      pad_done:
        pop si cx ax
        ret
    pad_to_mnemonic ENDP

    ; Input: AL = byte to write
    ; Output: writes two hex digits to output buffer
    write_hex_byte PROC near
      push ax bx si
      mov bl, al
      shr al, 4                                 ; get high nibble
      mov si, offset hex_chars
      xor ah, ah
      add si, ax
      mov al, [si]
      mov [di], al
      inc di
      mov al, bl
      and al, 0Fh                               ; get low nibble
      xor ah, ah
      mov si, offset hex_chars
      add si, ax
      mov al, [si]
      mov [di], al
      inc di
      pop si bx ax
      ret
    write_hex_byte ENDP

    ; Input: AX = word to write
    ; Output: writes four hex digits to output buffer
    write_hex_word PROC near
      push ax
      mov al, ah                                ; write high byte first
      call write_hex_byte
      pop ax
      call write_hex_byte                       ; write low byte
      ret
    write_hex_word ENDP

    ; Input: AL = register number (0-7)
    ; Output: writes register name (AL, CL, DL, BL, AH, CH, DH, BH) to output buffer
    write_reg_8 PROC near
      push ax bx si
      and al, 07h
      mov bl, al
      xor bh, bh
      shl bx, 1                                 ; multiply by 2 (each register name is 2 chars)
      mov si, offset reg_names_8
      add si, bx
      mov al, [si]
      mov [di], al
      inc di
      inc si
      mov al, [si]
      mov [di], al
      inc di
      pop si bx ax
      ret
    write_reg_8 ENDP

    ; Input: AL = register number (0-7)
    ; Output: writes register name (AX, CX, DX, BX, SP, BP, SI, DI) to output buffer
    write_reg_16 PROC near
      push ax bx si
      and al, 07h
      mov bl, al
      xor bh, bh
      shl bx, 1                                 ; multiply by 2 (each register name is 2 chars)
      mov si, offset reg_names_16
      add si, bx
      mov al, [si]
      mov [di], al
      inc di
      inc si
      mov al, [si]
      mov [di], al
      inc di
      pop si bx ax
      ret
    write_reg_16 ENDP

    ; Input: AL = ModR/M byte
    ; Output: writes 8-bit register name to output buffer
    decode_modrm_dest_8 PROC near
      push ax
      shr al, 3
      and al, 07h
      call write_reg_8
      pop ax
      ret
    decode_modrm_dest_8 ENDP

    ; Input: AL = ModR/M byte
    ; Output: writes 16-bit register name to output buffer
    decode_modrm_dest_16 PROC near
      push ax
      shr al, 3
      and al, 07h
      call write_reg_16
      pop ax
      ret
    decode_modrm_dest_16 ENDP

    ; Input: AL = ModR/M byte
    ; Output: writes 8-bit register name to output buffer
    decode_modrm_src_8 PROC near
      push ax
      and al, 07h
      call write_reg_8
      pop ax
      ret
    decode_modrm_src_8 ENDP

    ; Input: AL = ModR/M byte
    ; Output: writes 16-bit register name to output buffer
    decode_modrm_src_16 PROC near
      push ax
      and al, 07h
      call write_reg_16
      pop ax
      ret
    decode_modrm_src_16 ENDP

    ; Input: AL = ModR/M byte
    ; Output: writes segment register name (ES, CS, SS, DS) to output buffer
    decode_modrm_segreg PROC near
      push ax bx si
      shr al, 3
      and al, 03h                               ; segment register is in bits 3-4 (only 4 segment regs)
      mov bl, al
      xor bh, bh
      shl bx, 1                                 ; multiply by 2 (each register name is 2 chars)
      mov si, offset seg_reg_names
      add si, bx
      mov al, [si]
      mov [di], al
      inc di
      inc si
      mov al, [si]
      mov [di], al
      inc di
      pop si bx ax
      ret
    decode_modrm_segreg ENDP

    ; Input: AL = ModR/M byte
    ; Output: writes 8-bit register name to output buffer
    decode_modrm_reg_8 PROC near
      push ax
      shr al, 3
      and al, 07h
      call write_reg_8
      pop ax
      ret
    decode_modrm_reg_8 ENDP

    ; Input: AL = ModR/M byte
    ; Output: writes 16-bit register name to output buffer
    decode_modrm_reg_16 PROC near
      push ax
      shr al, 3
      and al, 07h
      call write_reg_16
      pop ax
      ret
    decode_modrm_reg_16 ENDP

end start