;///////////////////////////////////////////////////////////////////////////////////
; Start Apps - 32K cartridge for the Commodore 128
;///////////////////////////////////////////////////////////////////////////////////

;===================================================================================
; Code by Jorge Castillo (Pastbytes) & Pablo Roldan (Durandal)
;===================================================================================
; 23-Sep-2021	v0: First 16K version, formerly known as RetroApps.
; 30-Sep-2021	v0.1: First 32K version.
; 06-Oct-2021	v0.2: Separate internal and external versions. Added 80-column support.
; 29-May-2022	v0.3: Added some macros. Menu and loader reworked.
; 29-Jun-2022	v0.4: Changes to cartridge initialization. Startup logo and menu title
;		are now separate PETSCII files. BASIC 7.0 screen now supports 80
;		column mode. Some minor changes to C64 and C128 mode loaders.
; 15-Sep-2023	v0.5: More macros were added to make the code more readable.
; 25-Feb-2024	v0.6: Now the same binary works as an internal or external cartridge.
;		Added support for upper-graphics PETSCII logo.
; 16-Mar-2024	v0.7: Minor changes were made to facilitate cartridge customization.
;===================================================================================

	!to "startappsx.bin", plain
	!sl "labels.txt"

; System variables / functions

	MODE = $D7		; Active screen flag (MODE.7 = 0 : 40-column display)
				;                    (MODE.7 = 1 : 80-column display)
	KEYCHK = $033C		; (2 bytes) Indirect vector in keyboard scanning routine
	TEXT_TOP = $1210	; Pointer to end of BASIC program
	BASICSTART = $1C01	; First byte of BASIC program area
	VM1 = $0A2C		; VIC text screen and character base (C128 mode)
	JRUN_A_PROGRAM = $AF99	; Entry point for the RUN routine (executes a BASIC program)
	JBOOT_CALL = $FF53	; Entry point for the Kernal BOOT_CALL routine
	CHROUT = $FFD2		; Entry point for the Kernal BSOUT (CHROUT) routine
	PLOT   = $FFF0		; Entry point for the Kernal PLOT routine
	GETIN = $FFE4		; Entry point for the Kernal GETIN routine
	SETBNK = $FF68		; Entry point for the Kernal SETBNK routine
	JMPFAR = $FF71		; Entry point for the Kernal JMPFAR routine
	STOP = $FFE1		; Entry point for the Kernal STOP routine
	CINT = $FF81		; Entry point for the Kernal CINT routine
	IOINIT = $FF84		; Entry point for the Kernal IOINIT routine
	RESTOR = $FF8A		; Entry point for the Kernal RESTOR routine
	WINDOW = $C02D		; Entry point for the Kernal WINDOW routine
	WRITEREG = $CDCC	; Entry point for the WRITEREG routine (stores A in the 8563 register specified in the X register)
	MMUCR = $FF00		; MMU configuration register
	MMUMCR = $D505		; MMU mode configuration register

	TEMPZP  = $FB		; Temporary variable on zero page (4 bytes available)

; C64-mode variables (Cassette buffer)

	BLKSTRT = $033C		; (2 bytes) Destination address of the program to be copied from ROM (block start)
	BLKEND  = $033E		; (2 bytes) Destination address of the program to be copied from ROM (block end)
	SOURCEADR = $0340	; (2 bytes) Source address of the program to be copied from ROM

; C128-mode variables (Application Program Area)

	DELAYTIME = $1300	; Parameter used by timing routines
	LASTENTRY = $1300	; Number of programs on the menu
	BLKSTRT2 = $1300	; (2 bytes) Destination address of the program to be copied from ROM (block start)
	BLKEND2  = $1302	; (2 bytes) Destination address of the program to be copied from ROM (block end)
	SOURCEADR2 = $1304	; (2 bytes) Source address of the program to be copied from ROM
	INTEXTCART = $1306	; Copy of bits 3-2 of MMUCR (01: internal cartridge, 10: external cartridge)

;///// MMUCR Macros /////

; BIT 0    : $D000-$DFFF (0 = I/O Block)
;          : $D000-$DFFF (1 = No I/O Block)
; BIT 1    : $4000-$7FFF (0 = BASIC LOW ROM)
;          :             (1 = RAM)
; BITS 3-2 : $8000-$BFFF (00 = BASIC HIGH ROM)
;          :             (01 = Internal ROM)
;          :             (10 = External ROM)
;          :             (11 = RAM)
; BITS 5-4 : $C000-$CFFF/$E000-$FFFF (00 = Kernal ROM)
;          :                         (01 = Internal ROM)
;          :                         (10 = External ROM)
;          :                         (11 = RAM)
; BITS 7-6 : RAM block used (X0 = RAM 0)
;          :                (X1 = RAM 1)

!macro DisKernal {
	LDA	#%00000001	; BIT 0    : $D000-$DFFF (1 = No I/O Block)
				; BIT 1    : $4000-$7FFF (0 = BASIC LOW ROM)
				; BITS 3-2 : $8000-$BFFF (01 = Internal ROM)
				;          : $8000-$BFFF (10 = External ROM)
				; BITS 5-4 : $C000-$CFFF/$E000-$FFFF (01 = Internal ROM)
				;          : $C000-$CFFF/$E000-$FFFF (10 = External ROM)
				; BITS 7-6 : RAM block used (X0 = RAM 0)
	ORA	INTEXTCART	; Adds bits 3-2 and 5-4 (selects internal/external cartridge)
	STA	MMUCR		; MMU Configuration Register = 00XXXX01: RAM0 RAM0 INT/EXT INT/EXT INT/EXT INT/EXT BAS I/O
}

!macro EnKernal {
	LDA	#%00000000	; BIT 0    : $D000-$DFFF (0 = I/O Block)
				; BIT 1    : $4000-$7FFF (0 = BASIC LOW ROM)
				; BITS 3-2 : $8000-$BFFF (01 = Internal ROM)
				;          : $8000-$BFFF (10 = External ROM)
				; BITS 5-4 : $C000-$CFFF/$E000-$FFFF (00 = Kernal ROM)
				; BITS 7-6 : RAM block used (00 = RAM 0)
	ORA	INTEXTCART	; Adds bits 3-2 and 5-4 (selects internal/external cartridge)
	AND	#%11001111	; Enables Kernal on block $C000-$FFFF
	STA	MMUCR		; MMU Configuration Register = 0000XX00: RAM0 RAM0 KER KER INT/EXT INT/EXT BAS I/O
}

!macro DefaultCfg {
	LDA	#%00000000	; BIT 0    : $D000-$DFFF (0 = I/O Block)
				; BIT 1    : $4000-$7FFF (0 = BASIC LOW ROM)
				; BITS 3-2 : $8000-$BFFF (00 = BASIC HIGH ROM)
				; BITS 5-4 : $C000-$CFFF/$E000-$FFFF (00 = Kernal ROM)
				; BITS 7-6 : RAM block used (00 = RAM 0)
	STA	MMUCR		; MMU Configuration Register = 00000000: RAM0 RAM0 KER KER BAS BAS BAS I/O
}

!macro AllRAM {
	LDA	#%00111110	; BIT 0    : $D000-$DFFF (0 = I/O Block)
				; BIT 1    : $4000-$7FFF (1 = RAM)
				; BITS 3-2 : $8000-$BFFF (11 = RAM)
				; BITS 5-4 : $C000-$CFFF/$E000-$FFFF (11 = RAM)
				; BITS 7-6 : RAM block used (00 = RAM 0)
	STA	MMUCR		; MMU Configuration Register = 00111110: RAM0 RAM0 RAM RAM RAM RAM RAM I/O
}

	* = $8000
	SEI
	NOP
	NOP
	JMP	StartCart	; warmstart and coldstart
	!byte	$FF		; $FF = Autostart after basic cold-start sequence
	!byte	$43, $42, $4D	; "CBM" string

StartCart
	SEI			; Disable interrupts
	LDX	#$FF		; Reset stack pointer
	TXS
	CLD			; Clear decimal mode
	LDA	#$E3		; Initialize 8502's I/O port
	STA	$01
	LDA	#$37
	STA	$00

	LDA	MMUCR		; INTEXTCART = 0 0 0 0 MMUCR.3 MMUCR.2 MMUCR.3 MMUCR.2
	AND	#%00001100	; (used to detect if cartridge is internal or external and select the ROMs accordingly)
	STA	INTEXTCART
	ASL
	ASL
	ORA	INTEXTCART
	STA	INTEXTCART

	+EnKernal		; Selects Cartridge ROML + Kernal

	LDA	#$FD		; Checks the left shift key
	STA	$DC00
	LDA	$DC01
	CMP	#$7F
	BNE	+
	CLI			; If pressed, enables interrupts
	JMP	Go128		; and transfers control to BASIC

+
	JSR	RESTOR		; RESTOR: Restore Vectors
	JSR	IOINIT		; IOINIT: Init I/O Devices, Ports & Timers
	JSR	CINT		; CINT: Init Editor & Video Chips
	LDX	#0		; Selects bank 0 for I/O operations
	JSR	SETBNK

	CLI			; Enable interrupts

;///////////////////////////////////////////////////////////////////////////////////
; Checks if we are in 80-column mode

Check80
	LDA	MODE		; Checks the active screen flag
	BPL	ShowLogo	; If active screen is 40-column, jump to ShowLogo
				; If it's 80-column, we need to create a 40x25 window,
				; centered horizontally
	CLC			; Set top-left corner
	LDA	#0
	LDX	#20
	JSR	WINDOW
	SEC			; Set bottom-right corner
	LDA	#24
	LDX	#59
	JSR	WINDOW
	LDA	#$FF		; VDC register #26 = $FF
	LDX	#$1A		; (white background)
	JSR	WRITEREG

;///////////////////////////////////////////////////////////////////////////////////
; Shows startup logo

ShowLogo
	LDA	#1		; White border, white background
	STA	$D020
	STA	$D021
	LDA	#$90		; Black text
	JSR	CHROUT
	LDA	#$0B		; Block C= + SHIFT
	JSR	CHROUT
	LDA	#$0E		; Select lowercase/uppercase charset
	JSR	CHROUT
	LDA	#$93		; Clear screen
	JSR	CHROUT

	CLC			; Move cursor to row 9, column 0
	LDX	#9
	LDY	#0
	JSR	PLOT

	LDA	#<StartLogo	; Print the startup logo
	LDY	#>StartLogo
	JSR	PrintTxt

; We'll try to boot the disk on drive 8 (CP/M, etc.)

	CLC			; Move cursor to row 24, column 0
	LDX	#24
	LDY	#0
	JSR	PLOT

	; Print "Attempting to boot from drive 8..."

	LDA	#<BootMsg1	; Print "   "
	LDY	#>BootMsg1
	JSR	PrintTxt
	+DisKernal		; Selects Cartridge ROML + Cartridge ROMH
	LDA	BootMsg2	; Gets the first character of "Attempting..."
	STA	TEMPZP		; and stores it in TEMPZP
	+EnKernal		; Selects Cartridge ROML + Kernal
	LDA	VM1		; If the current charset is lowercase/uppercase,
	AND	#%00000010	; adds 32 to TEMPZP before printing the character
	ASL
	ASL
	ASL
	ASL
	CLC
	ADC	TEMPZP
	JSR	CHROUT
	LDA	#<BootMsg2+1	; and then prints the rest of the string
	LDY	#>BootMsg2+1
	JSR	PrintTxt

	; Copies Boot128 to 4865 ($1307)

	LDX	#Boot128End-Boot128
-	LDA	Boot128-1,X
	STA	B128-1,X
	DEX
	BNE	-

	JSR	B128		; and calls BOOT from there
	JMP	Boot128End	; Continues execution at Boot128End if boot fails

Boot128
!pseudopc $1307 {

; Calls JBOOT_CALL function ($FF53) to try to boot from drive 8
; We have to enable BASIC HIGH ROM first
; If boot fails, we enable ROML before returning to cartridge code

B128
	+DefaultCfg		; Selects BASIC ROMs + Kernal
	LDA	#$30		; Drive 0
	LDX	#$08		; Device 8
	JSR	JBOOT_CALL	; Calls BOOT_CALL
	+EnKernal		; Selects Cartridge ROML + Kernal
	RTS			; Returns to cartridge code
}
Boot128End

; If we get here it means that there is no bootable disk,
; so we wait 1 second before showing the menu

	LDA	#<ClearMsg	; Clear the current line
	LDY	#>ClearMsg
	JSR	PrintTxt
	LDA	#16		; Wait 1 second
	JSR	Delay16

;///////////////////////////////////////////////////////////////////////////////////
; Shows the Start Apps' menu

ShowMenu
	LDA	#$93		; Clear screen
	JSR	CHROUT
	LDA	#$0E		; Select lowercase/uppercase charset
	JSR	CHROUT

	LDA	#<StartTitle	; Print PETSCII title ("start apps")
	LDY	#>StartTitle
	JSR	PrintTxt

; Prints menu

	CLC			; Move cursor to row 5, column 16
	LDX	#5
	LDY	#16
	JSR	PLOT
	LDA	#<RetroMenu1	; Print menu header
	LDY	#>RetroMenu1
	JSR	PrintTxt

M1
	LDX	#$00
-
	SEI
	+DisKernal		; Selects Cartridge ROML + Cartridge ROMH
	LDA	MenuEntries	; Number of entries on the menu
	STA	LASTENTRY
	TXA
	PHA			; Push X on the stack
	ASL			; X*2
	TAX
	LDA	PRGNames+1,X	; Read name pointer
	PHA			; Push high byte on the stack
	LDA	PRGNames,X
	PHA			; Push low byte on the stack

	LDA	#<RetroMNum	; Print the beginning of current entry
	LDY	#>RetroMNum
	JSR	PrintTxt
	+EnKernal		; Selects Cartridge ROML + Kernal
	CLI
	TXA
	LSR			; X/2
	TAX
	CLC
	ADC	#49		; Add '1'
	JSR	CHROUT		; Print number of current entry
	SEI
	+DisKernal		; Selects Cartridge ROML + Cartridge ROMH
	LDA	PRGMode,X
	BEQ	+		; Print the mode of current entry (C64/C128)
	LDA	#<RetroM128
	LDY	#>RetroM128
	BVC	++
+	LDA	#<RetroM64
	LDY	#>RetroM64
++	JSR	PrintTxt
	PLA			; Pull low byte from the stack
	TAX
	PLA			; Pull high byte from the stack
	TAY
	TXA			; Y:A points to the name of current entry
	JSR	PrintTxt
	PLA			; Pull X from the stack
	TAX
	INX
	CPX	#$07		; No more of 7 items
	BEQ	.mend
	CPX	LASTENTRY	; Continue until we reach LASTENTRY
	BNE	-

.mend
	+EnKernal		; Selects Cartridge ROML + Kernal
	CLI
	CLC			; Move cursor to row 22, column 2
	LDX	#22
	LDY	#2
	JSR	PLOT
	LDA	#<RetroMenu3	; Print menu footer
	LDY	#>RetroMenu3
	JSR	PrintTxt

	LDA	#$B7		; Disable function key definitions
	STA	KEYCHK
	LDA	#$C6
	STA	KEYCHK+1

	LDA	MODE		; Checks the active screen flag
	BPL	ReadKey		; If active screen is 40-column, jump to ReadKey
				; If it's 80-column, we need to restore the 80x25 window
	CLC			; Set top-left corner
	LDA	#0
	LDX	#0
	JSR	WINDOW
	SEC			; Set bottom-right corner
	LDA	#24
	LDX	#79
	JSR	WINDOW

;///////////////////////////////////////////////////////////////////////////////////
; Reads the keyboard

ReadKey
	SEI			; Before reading the keyboard, check the joystick on port 2
	LDA	#$FF
	STA	$DC00
	STA	$D02F
	LDA	$DC00		; Pressing the fire button on joystick 2
	AND	#%00010000
	BNE	ReadKey_
	LDA	#'1'		; it loads the first program,
	JMP	+		; as if the user had pressed the '1' key
	CLI
ReadKey_
	CLI
	JSR	GETIN		; Wait for a key press
	BEQ	ReadKey
	CMP	#13		; If user pressed RETURN, jump to GoProcRET
	BEQ	GoProcRET
	CMP	#27		; If user pressed ESC, jump to GoProcESC
	BEQ	GoProcESC
+	SEC			; User pressed a key
	SBC	#49		; Subtract '1'
	BMI	ReadKey		; If it's not in the range 1..LASTENTRY, jump to ReadKey
	CMP	LASTENTRY
	BCS	ReadKey
	TAX
	JMP	ProcessX	; If it's within range, jump to ProcessX

GoProcRET
	JMP	ProcessRET
GoProcESC
	JMP	ProcessESC

;///////////////////////////////////////////////////////////////////////////////////
; Loads a program according to the value of register X

ProcessX
	SEI
	CLV
	TXA
	PHA			; Push X on the stack

	+DisKernal		; Selects Cartridge ROML + Cartridge ROMH

	LDA	PRGMode,X	; Checks the mode of the program
	BNE	+		; Skip to + if it's a C128-mode program
	JSR	Init64Vars	; Initializes the first pages and some C64 system variables

+	PLA			; Pull X from the stack
	TAX
	ASL			; A*2
	TAY

	; Load address
	; Points $FC:$FB to the first byte of the PRG in ROM

	LDA	PRGStart,Y
	STA	$FD
	LDA	PRGStart+1,Y
	STA	$FE
	LDY	#$00

	LDA	($FD),Y
	STA	$FB		; Start of block (low byte)
	INY
	LDA	($FD),Y
	STA	$FC		; Start of block (high byte)

	; Points $FE:$FD to the last byte of the PRG in ROM (PRG start + PRG size)

	TXA
	ASL			; A*2
	TAY

	CLC
	LDA	$FB
	ADC	PRGSize,Y
	STA	$FD
	LDA	$FC
	ADC	PRGSize+1,Y
	STA	$FE

	LDA	PRGMode,X	; If it's a C64-mode program, jump to .PX64
	BEQ	.PX64

; Initializes BLKSTRT2, BLKEND2 and TEXT_TOP

.PX128
	LDA	$FB		; BLKSTRT2 = $FC:$FB (start of PRG in ROM)
	STA	BLKSTRT2
	LDA	$FC
	STA	BLKSTRT2+1

	LDA	$FD		; BLKEND2 = $FE:$FD (end of PRG in ROM)
	STA	BLKEND2
	STA	TEXT_TOP	; Set TEXT_TOP to BLKEND2+1 (BASIC's End-of-program pointer)
	LDA	$FE
	STA	BLKEND2+1
	STA	TEXT_TOP+1
	INC	TEXT_TOP
	BCC	+
	INC	TEXT_TOP+1

; Points SOURCEADR2 to the first byte of the program in ROM (skips the PRG's load address)

+	CLC
	LDA	PRGStart,Y
	ADC	#$02
	STA	SOURCEADR2
	LDA	PRGStart+1,Y
	ADC	#$00
	STA	SOURCEADR2+1

	+EnKernal		; Selects Cartridge ROML + Kernal
	CLI
	JMP	Exec128		; Jump to Exec128 to copy and run the C128 program

; Initializes BLKSTRT, BLKEND, and the pointer to the start of the BASIC variables

.PX64
	LDA	$FB		; BLKSTRT = $FC:$FB (start of PRG in ROM)
	STA	BLKSTRT
	LDA	$FC
	STA	BLKSTRT+1

	LDA	$FD		; BLKEND = $FE:$FD (end of PRG in ROM)
	STA	BLKEND
	STA	$2D		; Set $2E:$2D to BLKEND+1 (Start of BASIC Variables)
	LDA	$FE
	STA	BLKEND+1
	STA	$2E
	INC	$2D
	BCC	+
	INC	$2E

; Points SOURCEADR to the first byte of the program in ROM (skips the PRG's load address)

+	CLC
	LDA	PRGStart,Y
	ADC	#$02
	STA	SOURCEADR
	LDA	PRGStart+1,Y
	ADC	#$00
	STA	SOURCEADR+1
	JMP	Exec64		; Jump to Exec64 to copy and run the C64 program

;///////////////////////////////////////////////////////////////////////////////////
; ESC: Exits to BASIC 7.0

ProcessESC
	LDA	MODE		; Checks the active screen flag
	BPL	Esc40		; If active screen is 40-column, jump to Esc40
Esc80	LDA	#$22		; VDC register #26 = $22
	LDX	#$1A		; (blue background)
	JSR	WRITEREG
	JMP	+
Esc40	LDA	#6		; Blue border, blue background
	STA	$D020
	STA	$D021
+	LDA	#$AD		; Restore function key definitions
	STA	KEYCHK
	LDA	#$C6
	STA	KEYCHK+1
	LDA	#<BASICMsg1	; Clear screen and print the first part of the message
	LDY	#>BASICMsg1
	JSR	PrintTxt
	LDA	MODE		; If active screen is 80-column, print an additional
	BPL	+		; RETURN character
	LDA	#13
+	JSR	CHROUT
	LDA	#<BASICMsg2	; Print the second part of the message
	LDY	#>BASICMsg2
	JSR	PrintTxt
Go128
	LDA	#15		; BANK 15
	STA	$02
	LDA	#$40		; $4000
	STA	$03
	LDA	#$03
	STA	$04
	LDA	#0
	STA	$05
	STA	$06
	STA	$07
	STA	$08
	JMP	JMPFAR		; Transfers control to the BASIC 7.0 interpreter

;///////////////////////////////////////////////////////////////////////////////////
; RETURN: Executes GO64 to enter C64 mode

ProcessRET
	LDA	#15		; BANK 15
	STA	$02
	LDA	#$FF		; $FF4D
	STA	$03
	LDA	#$4D
	STA	$04
	LDA	#0
	STA	$05
	STA	$06
	STA	$07
	STA	$08
	JMP	JMPFAR		; Jumps to GO64

;///////////////////////////////////////////////////////////////////////////////////
; Subroutine to print a NULL-terminated text string
; (Y:A points to the string)

PrintTxt
	STA	$FB		; TEMPZP = Y:A
	STY	$FC
	LDY	#0		; Y = 0
PrLoop
	SEI
	+DisKernal		; Selects Cartridge ROML + Cartridge ROMH
	LDA	($FB), Y	; Read a byte
	BEQ	PrEnd		; If byte is null jump to PrEnd
	PHA
	+EnKernal		; Selects Cartridge ROML + Kernal
	CLI
	PLA
	JSR	CHROUT		; Print the character
	INC	$FB		; Increment pointer $FC:$FB
	BNE	+
	INC	$FC
+	JMP	PrLoop		; Jump to PrLoop
PrEnd
	+EnKernal		; Selects Cartridge ROML + Kernal
	CLI
	RTS			; Returns

;///////////////////////////////////////////////////////////////////////////////////
; Subroutine Delay16, waits A times 1/16 of a second

Delay16
	STA	DELAYTIME	; DELAYTIME = A
	LDA	#$08		; Set CIA2's Timer A to one-shot mode
	STA	$DD0E
DlyStart2
	LDA	#$F4		; Load Timer A with the value $F424 (62500 us)
	STA	$DD05
	LDA	#$24
	STA	$DD04
	LDA	#$09		; Start Timer A
	STA	$DD0E
DlyLoop2
	LDA	$DD0D		; Wait until Timer A = 0
	AND	#$01
	BEQ	DlyLoop2
DlyNext2
	DEC	DELAYTIME	; DELAYTIME--
	BNE	DlyStart2	; Jump to DlyStart2 if DELAYTIME<>0
	RTS

;///////////////////////////////////////////////////////////////////////////////////
; Initializes the first pages and some C64 system variables

Init64Vars
	LDA	#$00		; Clear page zero, starting at $0002
	LDY	#$02
-	STA	$0000, Y
	INY
	BNE	-
	LDA	#$00		; Clear RAM pages 2 & 3
	TAY
-	STA	$0200, Y
	STA	$0300, Y
	INY
	BNE	-

	LDA	#$3C		; Set some system variables
	STA	$B2
	LDA	#$03
	STA	$B3
	LDA	$A0
	STA	$0284
	LDA	$00
	STA	$0283
	LDA	#$08
	STA	$0282
	LDA	#$04
	STA	$0288

	RTS

;///////////////////////////////////////////////////////////////////////////////////
; Copies CBufCode to 834 ($0342)

Exec64
	LDX	#CBufEnd-CBufCode
-	LDA	CBufCode-1,X
	STA	RCopy64-1,X
	DEX
	BNE	-
	LDA	#%00000001	; BIT 0    : $D000-$DFFF (1 = No I/O Block)
				; BIT 1    : $4000-$7FFF (0 = BASIC LOW ROM)
				; BITS 3-2 : $8000-$BFFF (01 = Internal ROM)
				;          : $8000-$BFFF (10 = External ROM)
				; BITS 5-4 : $C000-$CFFF/$E000-$FFFF (01 = Internal ROM)
				;          : $C000-$CFFF/$E000-$FFFF (10 = External ROM)
				; BITS 7-6 : RAM block used (X0 = RAM 0)
	ORA	INTEXTCART	; Adds bits 3-2 and 5-4 (selects internal/external cartridge)
	STA	RC64Loop+1	; Uses this MMUCR configuration as parameter in RC64Loop's LDA instruction
	JMP	RCopy64		; Transfers control to the code in cassette buffer

CBufCode
!pseudopc $0342 {

;///////////////////////////////////////////////////////////////////////////////////
; Copies the program from Cartridge ROM to RAM

RCopy64
	SEI
	LDA	SOURCEADR	; Writes SOURCEADR as parameter of RC64Read's LDA instruction
	STA	RC64Read+1
	LDA	SOURCEADR+1
	STA	RC64Read+2
	LDA	BLKSTRT		; Writes BLKSTRT as parameter of RC64Write's STA instruction
	STA	RC64Write+1
	LDA	BLKSTRT+1
	STA	RC64Write+2
RC64Loop
	LDA	#$FF		; Enables cartridge on block $8000-$FFFF (Self-modifying code)
	STA	MMUCR
RC64Read
	LDY	$FFFF		; (Self-modifying code)
	+AllRAM			; Enables RAM on block $8000-$FFFF
RC64Write
	STY	$FFFF		; (Self-modifying code)
RC64Next
	LDA	RC64Write+2	; If we reach BLKEND, jump to Go64
	CMP	BLKEND+1
	BNE	+
	LDA	RC64Write+1
	CMP	BLKEND
	BEQ	Go64

+	INC	RC64Write+1	; Increment destination pointer
	BNE	+
	INC	RC64Write+2

+	INC	RC64Read+1	; Increment source pointer
	BNE	RC64Loop
	INC	RC64Read+2
	JMP	RC64Loop	; Jump to RC64Loop

;///////////////////////////////////////////////////////////////////////////////////
; Switch to C64 Mode

Go64	LDA	#$E7		; 0001 R6510 - CAPKEY CASMTR CASSEN CASWRT CHAREN HIRAM LORAM = 11100111
	STA	$01		; X X X X X /CHAREN Signal (0 = Switch Char. ROM In)	/HIRAM Signal (0 = Switch Kernal ROM Out)
				; /LORAM Signal (0=Switch BASIC ROM Out)
	LDA	#$2F		; 0000 D6510 - (IN)   (OUT)  (IN)   (OUT)  (OUT)  (OUT) (OUT) = 00101111 (0 = entrada, 1 = salida)
	STA	$00
	LDA	#$FF		; Bits 0-2 = 1 (disables extended keyboard)
	STA	$D02F
	LDA	#$00		; Bit 0 = 0 (sets 6502 clock to 1 MHz)
	STA	$D030

	LDA	#$F7		; MMU Mode Configuration Register: 11110111	- C64 - - - - - 8502
	STA	MMUMCR

;///////////////////////////////////////////////////////////////////////////////////
; C64-mode code

C64Init
	LDX	#$FF		; X = 255
	SEI			; Disable interrupts
	TXS			; Reset stack pointer
	CLD			; Clear decimal mode

	JSR	$FDA3		; Initialize I/O devices (IOINIT)
	LDA	#0		; Disable quotation mode
	STA	$D4
	JSR	$FD15		; Set up OS vectors (RESTOR)
	JSR	$FF5B		; Initialize screen (CINT)

	JSR	$E453		; Initialize BASIC vectors
	JSR	$E3BF		; Initialize RAM
	LDX	#$FB		; Initialize stack
	TXS

	LDA	#4		; Writes "RUN"+RETURN to the keyboard buffer
	STA	$C6
	LDA	#$52
	STA	$0277
	LDA	#$55
	STA	$0278
	LDA	#$4E
	STA	$0279
	LDA	#$0D
	STA	$027A
	LDA	#$00		; Pointer to end of BASIC area ($A000)
	STA	$37
	LDA	#$A0
	STA	$38
	JMP	$E386		; Prints "READY." and transfers control to the BASIC interpreter
}
CBufEnd

;///////////////////////////////////////////////////////////////////////////////////
; Copies RLCp1300 to 4865 ($1307)

Exec128
	LDA	#$AD		; Restore function key definitions
	STA	$033C
	LDA	#$C6
	STA	$033D
	LDX	#RC128End-ROMCopy128
-	LDA	ROMCopy128-1,X
	STA	RCopy128-1,X
	DEX
	BNE	-

	JSR	RCopy128	; Copies the program from cartridge ROM to RAM

StartBasic
	LDA	#19		; HOME
	JSR	CHROUT
	LDA	#15		; BANK 15
	STA	$02
	LDA	#>JRUN_A_PROGRAM
	STA	$03
	LDA	#<JRUN_A_PROGRAM
	STA	$04
	LDA	#0
	STA	$05
	STA	$06
	STA	$07
	STA	$08
	JMP	JMPFAR		; Executes a BASIC program

ROMCopy128
!pseudopc $1307 {

; Copies from SOURCEADR2 to BLKSTRT2, until BLKSTRT2=BLKEND2

RCopy128
	SEI
	LDA	SOURCEADR2	; Writes SOURCEADR2 as parameter of RC128Read's LDA instruction
	STA	RC128Read+1
	LDA	SOURCEADR2+1
	STA	RC128Read+2
	LDA	BLKSTRT2	; Writes BLKSTRT2 as parameter of RC128Write's STA instruction
	STA	RC128Write+1
	LDA	BLKSTRT2+1
	STA	RC128Write+2
RC128Loop
	+DisKernal		; Enables cartridge on block $8000-$FFFF
RC128Read
	LDY	$FFFF		; (Self-modifying code)
	+AllRAM			; Enables RAM on block $8000-$FFFF
RC128Write
	STY	$FFFF		; (Self-modifying code)
RC128Next
	LDA	RC128Write+2	; If we reach BLKEND2, jump to RC128Exit
	CMP	BLKEND2+1
	BNE	+
	LDA	RC128Write+1
	CMP	BLKEND2
	BEQ	RC128Exit

+	INC	RC128Read+1	; Increment source pointer
	BNE	+
	INC	RC128Read+2
+	INC	RC128Write+1	; Increment destination pointer
	BNE	+
	INC	RC128Write+2
+	JMP	RC128Loop	; Jump to RC128Loop
RC128Exit
	+EnKernal		; Selects Cartridge ROML + Kernal
	CLI
	RTS
}
RC128End

;///////////////////////////////////////////////////////////////////////////////////
; Startup logo

StartLogo
	!binary "startlogo.seq"
	!byte 0

;///////////////////////////////////////////////////////////////////////////////////
; Menu title

StartTitle
	!binary "starttitle.seq"
	!byte 0

RetroMenu1
	!text "pOWERED BY rETROlOADER    "
	!byte 18
	!text " vOLUME x V1 "
	!byte 146
	!fill 23, 192
	!byte 0

RetroMNum
	!byte 13, 13, 29, 29, 29, 29, 29, 29, 29, 152, 18, 32, 0

RetroM128
	!byte 32, 30, 161, 146, 144, 32, 32, 0
RetroM64
	!byte 32, 31, 161, 146, 144, 32, 32, 0

RetroMenu3
	!byte 18, 152
	!text "c64/128 lOADER BY pASTBYTES/dURANDAL"
	!byte 144, 146, 32, 32, 32, 32
	!fill 36, 192
	!byte 13
	!text "  "
	!byte 31, 18, 161
	!text "return"
	!byte 146, 161, 144
	!text "eNTER c64 mODE"
	!byte 30, 18, 161
	!text "esc"
	!byte 146, 161, 144
	!text "basic 7.0"
	!byte 0
ClearMsg
	!byte 145, 13
	!text "                                     "
	!byte 0

CODEEND:

;///////////////////////////////////////////////////////////////////////////////////
; Binaries of the programs to load in RAM (.prg)
;///////////////////////////////////////////////////////////////////////////////////

;///////////////////////////////////////////////////////////////////////////////////
; RetroLoader 128 (C128 mode)

PRG1
	!binary "retroloader128.prg"
PRG1End
PRG1Txt
	!text "retroloader 128 V0.6.11"
	!byte 0

;///////////////////////////////////////////////////////////////////////////////////
; Retroterm (C64 mode)

PRG2
	!binary "retroterm.prg"
PRG2End
PRG2Txt
	!text "retroterm V0.20"
	!byte 0

;///////////////////////////////////////////////////////////////////////////////////
; InDev Tester 128 (C128 mode)

PRG3
	!binary "indev128.prg"
PRG3End
PRG3Txt
	!text "indev tester 128 V0.1.2"
	!byte 0

;///////////////////////////////////////////////////////////////////////////////////
; PRG4

PRG4
PRG4End
PRG4Txt

;///////////////////////////////////////////////////////////////////////////////////
; PRG5

PRG5
PRG5End
PRG5Txt

;///////////////////////////////////////////////////////////////////////////////////
; PRG6

PRG6
PRG6End
PRG6Txt

;///////////////////////////////////////////////////////////////////////////////////
; PRG7

PRG7
PRG7End
PRG7Txt


EndPrgs:

	* = $FF00

;//////////////////////////////////////////////////////////////////////////////////
; These MMU registers are visible in all banks so these 5 memory addresses cannot
; be used

MMUReg:
	!byte 0,0,0,0,0		; MMU registers, visible in all configurations

;//////////////////////////////////////////////////////////////////////////////////
; Various messages, moved here to fill the last page of the ROM

BASICMsg1
	!byte $0C,142,5,147
	!byte 18,154,169,32,32,32,146,32,32,32,5
	!text "COMMODORE BASIC V7.0"
	!byte 13,18,154,32,146,32,32,32,18,32,146,169,32,5
	!text "(C)1985 COMMODORE ELECTRONICS LTD"
	!byte 0
BASICMsg2
	!byte 18,154,32,146,32,32,32,18,150,32,223,146,32,5
	!text "(C)1977 MICROSOFT CORP."
	!byte 13,154,223,18,32,32,32,146,32,32,32,5
	!text "ALL RIGHTS RESERVED"
	!byte 13,5,0

BootMsg1
	!text "   "
	!byte 0
BootMsg2
	!text "ATTEMPTING TO BOOT FROM DRIVE 8..."
	!byte 0
EndMsg:

;//////////////////////////////////////////////////////////////////////////////////
; Tables

PRGStart:
	!word PRG1, PRG2, PRG3, PRG4, PRG5, PRG6, PRG7

PRGSize:
	!word PRG1End-PRG1-3, PRG2End-PRG2-3, PRG3End-PRG3-3, PRG4End-PRG4-3, PRG5End-PRG5-3, PRG6End-PRG6-3, PRG7End-PRG7-3

PRGNames:
	!word PRG1Txt, PRG2Txt, PRG3Txt, PRG4Txt, PRG5Txt, PRG6Txt, PRG7Txt
EndOfNames:

MenuEntries:				; Number of programs on the menu
	!byte 3
PRGMode:				; 0 = C64 mode		255 = C128 mode
	!byte 255,0,255,0,0,0,0
CARTEND:

	!align $ffff,0
