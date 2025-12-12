.model small

.code
org 100h

start:

    mov ax, bx
    mov cx, dx

    nop

    mov ax, [bx]
    mov dx, [bp+di+20h]
    mov [bx], ax
    mov [bp+di], dx

    nop

    mov es, ax
    mov ax, es

    nop

    mov es, word ptr [bx]
    mov word ptr [di+6], ds

    nop

    mov ds:[1000h], ax

    nop

    mov al, 42h
    mov word ptr [bx+di+100h], 0CDEFh
    mov ax, [bp+1234h]

    nop

    out 60h, al          ; E6 60
    out 70h, ax          ; E7 70
    
    ; Test OUT DX port
    out dx, al           ; EE
    out dx, ax           ; EF
    
    ; Test with segment prefix
    mov ax, 1234h        ; B8 34 12
    out 80h, ax          ; E7 80
    
    mov ah, 4Ch
    int 21h

end start