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

    out 60h, al
    out 70h, ax
    
    out dx, al
    out dx, ax
    
    mov ax, 1234h
    out 80h, ax

    not al
    not bl
    not cl
    
    not ax
    not bx
    not cx
    
    not byte ptr [bx]
    not word ptr [bx]
    not byte ptr [bx+si]
    not word ptr [bp+10h]
    
    mov ah, 4Ch
    int 21h

end start