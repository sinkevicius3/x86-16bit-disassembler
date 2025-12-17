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

    mov es, [bx]
    mov [di+6], ds

    nop

    mov al, 42h
    mov ds:[10h], al

    mov [bx+di+100h], 0CDEFh
    mov ax, [bp+1234h]

    nop

    mov es:[1000h], ax

    nop

    out 60h, al
    out 70h, ax
    
    out dx, al
    out dx, ax
    
    mov ax, 1234h
    out 80h, ax

    nop

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

    nop

    rcr al, 1 
    rcr bl, 1
    rcr ax, 1 
    rcr word ptr [bx], 1 
    
    rcr al, cl
    rcr byte ptr [bx+si], cl
    
    rcr byte ptr es:[bx], 1

    nop

    xlat
    xlat
    xlat
    
    mov ah, 4Ch             ; terminate
    int 21h

end start