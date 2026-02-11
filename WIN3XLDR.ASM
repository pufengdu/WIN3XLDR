; ===========================================================================
; WIN3XLDR - An unloadable TSR program to help running Windows 3.x on MS-DOS
;            7.1 and 8.0. (An alternative to OSR2FIX)
;           
; Copyright(C) 2026 Dr. Pu-Feng Du.
;
; LICENSE:
;   WIN3XLDR is free software: you can redistribute it and/or modify it under
; the terms of the GNU General Public License as published by the Free Software
; Foundation, either version 2 of the License, or (at your option) any later
; version. This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY, without even the implied warranty of MERCHANTABILITY
; or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
; more details. You should have received a copy of the GNU General Public
; License along with this program. If not, see <https://www.gnu.org/licenses/>.
; 
; Compile:
;   WIN3XLDR needs to be assembled using TASM 5.0 / TLINK 7.1 version, with the 
; following commands:
;
;   TASM32 w3xinit.asm
;   TLINK /t w3xinit.obj
;
; Install:
;   Just call WIN3XLDR.COM as a normal COM file. DO NOT load high! It will find
; UMBs if you have enough UMBs. If it cannot find enough UMB, LOW mem will be
; used. WIN3XLDR.COM needs only **64** bytes memory to resident. It does not 
; show itself as a normal TSR, but as a part of IO.SYS system data in MEM 
; command.
; 
; Uninstall:
;   Run WIN3XLDR /U to unload it. If WIN3XLDR can be unloaded, it will unload.
;
; Note:
;  1. WIN3XLDR is an unloadable and stealth TSR program to help loading Windows
; 3.x on MS-DOS 7.1 and 8.0. It works in stealth TSR mode by design. This may
; cause false alarm of security software. 
;  2. After loading WIN3XLDR, you can run WIN from windows 3.x in MS-DOS 7.1
; directly.
;  3. For MS-DOS 8.0, you still need IO8EMMOK and EMM386.
; ===========================================================================
masm                                   ; Use MASM directives
version T500                           ; Assemble with TASM 5.0+
model tiny                             ; Produce .COM file
P386N                                  ; Use 386 real mode instruction set

; Command constants
TSR_SIG  EQU 0DFFDH
TSR_RET  EQU 0FDDFH
WIN_BRDC EQU 1605H
WIN_VERC EQU 040BH
W3X_ENA  EQU 0F5CH
JMP_FAR  EQU 0EAH
MOV_DX   EQU 0BAH
UMB_HDR  EQU 08CH

; Action constant
ACT_NONE EQU 0h
ACT_INST EQU 1h
ACT_UNIN EQU 2h
ACT_HELP EQU 3h

; Status constant
ST_NON   EQU 0h
ST_RES   EQU 1h

; Macros
ShowMsg  MACRO MSG
	lea dx, MSG
    call disp
ENDM

ErrExit  MACRO MSG
    lea dx, MSG
    call disp
    call exitp
ENDM

; Code segment
code segment use16                     ; 16-bit code segment
	assume cs:code, ds:code
    org	100h                           ; COM file
	start label byte                   ; Point of COM program start
	jmp main                           ; Go main proc
    ; ======================================================================
	; i2fh: Handler for 2FH. This is integrated with IO.SYS as system codes.
    ; ======================================================================
    i2fh_start label byte              ; Mark the beginning of the handler
	i2fh proc near
        cmp ax, TSR_SIG                ; Installation check
        jnz short fakever              ; No? Go next sub-function
        xchg al,ah                     ; Set installation mark
        push cs                        ; Return address of myself ES:BX
        pop es                         ; for possible uninstallation
        xor bx, bx                     ; We always begin from XXXX:0000.
        mov di, i2fh_off - i2fh        ; Return ptr of old 2fh handler ES:DI.
        iret                           ; We do iret. Maybe, retf 2 is better.
	fakever:
        cmp ax, 1605H                  ; Intercept Windows Init BRDC
        jnz short i2fh_old             ; No? Go next sub-function
        push es                        ; Before we fake the Windows version,
        push dx                        ; we must first change the W3X_ENA flag
        movdx db MOV_DX                ; in the DOSDATA segment. This mov dx,
        dos_seg dw 0H                  ; is set when installing this handler
        mov es, dx                     ; It changes DOSDATA:W3X_ENA flag, to
        mov es:byte ptr [W3X_ENA], 1   ; enable loading of Windows 3.x. This
        pop dx                         ; has to be changes every time in the
        pop es                         ; Windows init BRDC.
        mov di, WIN_VERC               ; Fake Windows Version 4.11.
    i2fh_old:
    	jmpfar   db JMP_FAR            ; Last sub-function, go to the old
        i2fh_off dw ?                  ; handler. These addresses are filled
        i2fh_seg dw ?                  ; when installing this handler.
    i2fh endp
    i2fh_end label byte                ; Mark the end of the handler
	
    ; ======================================================================
    ; main: Entrance of the program
    ; ======================================================================
	main proc near                     ; Proc main: entrance of the program.
		mov ax, cs                     ; This is a COM. Setup a small stack
		mov ss, ax                     ; at the end of the segment.
        mov sp, offset stk_bot 
      	push cs                        ; DS = CS = SS, SP = DS:stk_bot
        pop ds
        call iswin                     ; Check if in windows? Y => Exit
        call set_dosseg                ; Find DOSDATA segment, fix handler
        call initp                     ; Releasing unnecessary memory
        call argv                      ; Proc cmdline to store status/action
		call is_tsr                    ; Check residential for status/action
        .IF action == ACT_HELP         ; Action is help?
            ErrExit msg                ; Y => show help msg and exit.
        .ENDIF
        .IF action == ACT_NONE         ; Action is unknown?
            ErrExit emsg0              ; Y => show wrong argument msg, exit.
        .endif
        .IF status == ST_RES           ; Status is residented?
			.if action == ACT_INST     ; Action is to install?
                ErrExit emsg1          ; Not going to happen!
            .elseif action == ACT_UNIN ; Action is to uninstall?
            	call action_uninstall  ; Let's do it, self unload!
            .endif
        .ELSEif status == ST_NON       ; Status is non-residented?
        	.if action == ACT_INST     ; Action is to install?
            	call action_install    ; OK, let's do it, install myself!
            .elseif action == ACT_UNIN ; Action is to uninstall?
                ErrExit emsg2          ; Nothing need to do, show msg and exit.
            .endif
        .ENDIF
        call exitp                     ; Terminate the program
		ret
    main endp
    
    ; ======================================================================
	; action_install: Perform installation of the handler
    ; ======================================================================
    action_install proc near
    	pushf                          ; Keep flag and
        pusha                          ; states, and
        push ds                        ; DS and
        push es                        ; ES
    	mov ax, 352FH                  ; Call DOS service to obtain
        int 21h                        ; 2FH handler location 
        mov word ptr i2fh_seg, es      ; Store the ptr to OLD 2FH handler
        mov word ptr i2fh_off, bx      ; inside the JMP instruction in ours.
        call alloc_handler_mem         ; Allocate memory for resident. We can
                                       ; not use TSR function here. TSRs need
                                       ; at least 11H paragraphs. We only 4.
		.IF alloc_seg == 0             ; If memory allocation is error
	        ErrExit emsg7              ; Show error msg and exit
        .ENDIF                         ; If memory allocation is success
                                       ; ES is the allocated segment
        mov cx, i2fh_len               ; Get number of bytes from i2fh_len
        mov si, offset i2fh_start      ; Set source of copy
        xor di, di                     ; Set destination of copy, alway 0 
        cld
        rep movsb                      ; Copy our handler to the new location
        mov ax, es                     ; Find the MCB information of our i2fh
        dec ax                         ; by the -1 para of the segment
        mov es, ax                     ; Change the owner of the MCB to
        mov es:[word ptr 01h], 0008h   ; IO.SYS (PSP = 0008)
        mov si, offset prog_name       ; Copy special program name SD to the
        mov di, 08h                    ; MCB field.
        mov cx, 08h
        rep movsb                      ; Now, we are integrated with DOS
		mov ax, 252FH                  ; Use DOS service 25H to install i2fh
        mov dx, alloc_seg              ; as the new handler of 2FH, DS:DX 
        mov ds, dx                     ; points to our i2fh at new location
        xor dx, dx
        int 21h
        push cs
        pop ds
		.IF use_umb == 1               ; Show successful installation msgs
        	ShowMsg imsg1              ; Install in UMB message
        .ELSEIF use_umb == 0
        	ShowMsg imsg0              ; Install in LOW message
        .ENDIF
		pop es                         ; Finish installation
        pop ds
        popa
        popf
    	ret
    action_install endp

    ; ======================================================================
	; action_uninstall: Perform uninstallation of the handler
    ; ======================================================================
    action_uninstall proc near
		mov ax, 352FH                  ; Use DOS service to obtain current 2FH
        int 21h                        ; handler. Store it in memory.
        mov curr_2fh_off, bx
        mov curr_2fh_seg, es
        mov ax, TSR_SIG                ; We come here, so we are installed for
        int 2fH                        ; sure. We only need to get our own ptr
        mov ax, es                     ; to see if we are chained by others.
        cmp bx, curr_2fh_off
        jnz err_stop_unin              ; If we are chained by others, unloading
        cmp ax, curr_2fh_seg           ; is too complicated to do. Just give
        jnz err_stop_unin              ; up. Not worth it in WIN3XLDR.
        mov eax, es:[dword ptr di]     ; Here, we are the last hanlder, find 
        mov dx, ax                     ; the old ones.
        shr eax, 10H                   ; The old ones are returned by our i2fh
        mov ds, ax                     ; in a location pointed by ES:DI as a
        mov ax, 252fH                  ; DWORD PTR.
        int 21h                        ; Recover the OLD 2FH handler
        push cs                        ; Set DS=CS again
        pop ds
        mov ax, curr_2fh_seg           ; Get our handler segment
        mov es, ax                     ; Release the memory blocks
        mov ax, 4900h
        int 21h
        jnc ok_exit_unin               ; Error ?
        ErrExit emsg5                  ; Y => Go show err msg and exit.
	err_stop_unin:
    	ErrExit emsg4
	ok_exit_unin:                      ; No error, 
        ShowMsg emsg6                  ; Show uninstalled msg and return.
		ret    
    action_uninstall endp

    ; ======================================================================
	; alloc_handler_mem: Allocate memory for handler residence, use UMB 
    ;                    automatically, if available.
    ; ======================================================================
	alloc_handler_mem proc near
		call save_mem_state            ; Save mem alloc strategy + UMB link
        call has_umb                   ; Do we have UMB?
		mov use_umb, ax                ; Set flag for using UMB
	    cmp ax, 1                      ; If we have UMB
    	jnz set_mem_alloc_strat
        mov ax, 5803h                  ; Enable UMB link
	    mov bx, 0001h
	    int 21h
	set_mem_alloc_strat:
	    mov ax, 5801h                  ; Enable UMB first, LOW next
	    mov bx, 0081h                  ; allocation strategy / best fit
	    int 21h
        jnc mem_alloc
		ErrExit emsg7                  ; If error, show msg and exit
	mem_alloc:        
        mov ax, offset i2fh_start      ; Compute memory amount for the handler
        mov bx, offset i2fh_end
        sub bx, ax                     
        mov i2fh_len, bx               ; Store the byte length for later copy
        shr bx, 4                      ; Convert to number of paragraphs
        inc bx                         ; Plus a residue para
        mov ax, 4800h                  ; Allocate a memory block
        int 21h                        ; We do not know if this is in UMB. We
                                       ; simply believe we have more than 80 
                                       ; bytes free in UMB, if we have UMB.
        jc restore_mem_state           ; If error, keep alloc_seg = 0
		mov alloc_seg, ax              ; If success, set alloc_seg
	restore_mem_state:
		call load_mem_state            ; Restore mem alloc strategy+UMB link
        mov es, alloc_seg              ; Return the allocated segment as ES
        ret
    alloc_handler_mem endp

    ; ======================================================================
	; argv: Parse command line to get internat states of action / status
    ; ======================================================================
    argv proc near
		pusha                          ; Keep states and 
        pushf                          ; flags
    	mov cl, ds:[80h]		       ; Get len(cmd line) from PSP, in CL
        xor ch, ch                     ; Clear CH
        .IF CX == 0                    ; No command line argument
        	mov action, ACT_INST       ; Set action install
            jmp argv_end               ; Go exit function
        .ENDIF
		cld
        mov si, 81h                    ; Prepare to get command line arguments
        .WHILE CX > 0                  ; Scan command line
            mov al, DS:[SI]            ; Load DS:[SI] in AL
	        .IF AL == '/'              ; Find argument prefix '/'
            	.BREAK                 ; If found, go to check argument
            .ENDIF
            inc si
            dec cx
        .ENDW
        .IF CX == 0                    ; No argument prefix found.
        	jmp argv_end               ; Keep default ACT_NONE status, 
        .ENDIF                         ; wrong args
        inc si                         ; Go load the argument in 
        mov al, DS:[SI]                ; AL
        .IF AL == '?'                  ; Help argument
        	mov action, ACT_HELP
        .ELSEIF AL == 'u' || AL == 'U' ; Uninstall argument
        	mov action, ACT_UNIN
        .ELSE                          ; Other wrong argument
        	mov action, ACT_NONE
        .ENDIF
    argv_end:
    	popf                           ; Recover flags and
        popa                           ; status
        ret                            ; Return 
    argv endp

    ; ======================================================================
	; has_umb: Check if we have UMB or not.
    ; ======================================================================
	has_umb proc near                  
        push es                        ; We check if we have UMB by accessing
    	mov ax, cs:[dos_seg]           ; DOSDATA:8CH. This is a location in
        mov es, ax                     ; Disk Buffer Info. If this location is
        mov ax, 1                      ; FFFFH, no UMB. Otherwise, we have UMB
        cmp es:[word ptr UMB_HDR], -1  ; We use AX to return this status. 
        jnz umb_ok                     ; AX = 1: We have UMB
        xor ax, ax                     ; AX = 0: We have NO UMB
    umb_ok:                            ; !!! This proc is not for sure working
    	pop es                         ; !!! on every machine and every DOS 7.
    	ret                            ; !!! This proc is dangerous. For now,
    has_umb endp                       ; !!! we see 7.1 and 8.0 are correct.

    ; ======================================================================
	; save_mem_state: Save memory allocation strat and UMB link state
    ; ======================================================================
	save_mem_state proc near
        mov ax, 5800h                  ; Save memory allocating strategy
        int 21h
        mov cmb_save, ax
        mov ax, 5802h                  ; Save UMB link state
        int 21h
        mov umb_save, al
    	ret
    save_mem_state endp

    ; ======================================================================
	; load_mem_state: Restore memory allocation strat and UMB link state
    ; ======================================================================
	load_mem_state proc near
        mov ax, 5801h                  ; Recover allocation strategy
        mov bx, cmb_save
        xor bh, bh
        int 21h
        mov ax, 5803h                  ; Recover UMB link state
        mov bl, umb_save
        xor bh, bh
        int 21h
        ret
    load_mem_state endp

    ; ======================================================================
    ; is_tsr: Check if we are installed or not
    ; ======================================================================
    is_tsr proc near
		push ax                        ; Save AX
        mov	ax,	TSR_SIG		           ; If installed, the
        int	2FH                        ; 2FH handler will 
        cmp	ax, TSR_RET                ; swap AH and AL
        setz status                    ; Save the installation status
        pop ax                         ; Restore AX
        ret
    is_tsr endp

    ; ======================================================================
    ; initp: Release tail memory for residential part.
    ;        This is necessry, if NO UMB is available.
    ; ======================================================================
    initp proc near
        push cs                        ; Setup CS = ES, for releasing all mem
        pop es                         ; after us. In DOS, for a COM file, DOS
        lea bx, end_all                ; allocate all memory for it. Therefore,
        shr bx, 4                      ; we have to release remaining memory, 
        inc bx                         ; before we can copy/install our handler.
        mov ax, 4A00H                  ; The end_all label is for this purpose.
        int 21h
        jnc initp_end                  ; Release success?
        ErrExit emsg8                  ; N => Abort
	initp_end:        
        ret                            ; Y => return 
    initp endp

    ; ======================================================================
    ; exitp: Terminate the program and return to DOS
    ; ======================================================================
    exitp proc near
		mov ah, 4ch
        int 21h
        ret
    exitp endp

    ; ======================================================================
    ; disp: Display message
    ; ======================================================================
    disp proc near
		mov ah, 09h             ; Set Ah=09H
        int 21h                 ; Call DOS service to display strings
        ret
    disp endp

    ; ======================================================================
    ; iswin: Check if we are already running Windows
    ; ======================================================================
	iswin proc near
    	mov ax, 1600H
        int 2fh
        .IF AL > 0H
        	ErrExit emsg3
        .ENDIF
    iswin endp

    ; ======================================================================
    ; set_dosseg: Find out DOSDATA segement and save it in our handler
    ; ======================================================================
    set_dosseg proc near
    	push es
        push bx
        push ax
        mov ah, 52h
        int 21h
        mov cs:[dos_seg], es
        pop ax
        pop bx
        pop es
        ret
    set_dosseg endp

    ; ======================================================================
    ; Data area for non-resident part
    ; ======================================================================
    emsg0        db 'Wrong argument.',0AH,0DH,'$'
    emsg1        db 'WIN3XLDR already installed.',0AH,0DH,'$'
    emsg2        db 'WIN3XLDR was not installed.',0AH,0DH,'$'
    emsg3	     db 'Windows is already running.',0AH,0DH,'$'
    emsg4	     db 'Other handlers installed, unable to unload.', 0DH, 0AH, '$'
    emsg5	     db 'Error releasing memory.',0Dh, 0AH,'$'
    emsg6	     db 'WIN3XLDR uninstalled.',0DH,0AH,'$'
	emsg7	     db 'Memory allocation error.',0AH,0DH,'$'
    emsg8        db 'WIN3XLDR failed to initialize.',0DH,0AH,'$'
	imsg0	     db 'WIN3XLDR installed in LOW.',0AH,0DH,'$'
    imsg1	     db 'WIN3XLDR installed in UMB.',0AH,0DH,'$'
    msg	         db 'WIN3XLDR.COM - A TSR program to help loading Windows 3 in MS-DOS 7+',0AH,0DH
                 db '',0Ah,0DH
                 db 'Usage: WIN3XLDR.COM [ /U | /? ]',0AH,0DH
                 db '       /U: Unload WIN3XLDR',0AH,0DH
                 db '       /?: Display this message',0AH,0DH
                 db '       Default action is to load and resident in memory.',0AH,0DH
                 db '',0AH,0DH
                 db 'Note:  WIN3XLDR installs 2FH handler to intercept AX=1605H windows ',0AH,0DH
                 db '       initialization broadcasting.',0AH,0DH
                 db '       It fools MS-DOS 7+ kernel to believe Windows9x is starting.',0Ah,0DH
                 db '',0AH,0DH,'$'
    prog_name	 db 'SD', 6 dup(0)     ; Name for residential with IO.SYS
    status		 db 0h                 ; Status for residential 
    action		 db 0h                 ; Command line parse results
    use_umb		 dw 0h                 ; Are we using UMB? 1/0=Y/N
    cmb_save   	 dw 0                  ; Save for memory allocation strategy
    umb_save   	 db 0                  ; Save for UMB link
    i2fh_len	 dw 0h                 ; Length of our handler
    alloc_seg	 dw 0                  ; Save for moving handler destination
    curr_2fh_off dw 0                  ; Save for 2FH handler in unloading 
    curr_2fh_seg dw 0
	stk_top		 dw 32 dup(0)          ; A stack w/64 Bytes
    stk_bot      label byte            ; Stack bottom
    end_all		 label byte            ; The tail of our program
code ends                              ; End of the code segment
end start                              ; Program start from the start lable


