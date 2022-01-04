$NOLIST
$MODEFM8LB1
$LIST

SYSCLK         EQU 72000000  ; Microcontroller system clock frequency in Hz changed from 72MHz
TIMER2_RATE    EQU 22050     ; 22050Hz is the sampling rate of the wav file we are playing
TIMER2_RELOAD  EQU 0x10000-(SYSCLK/TIMER2_RATE)
F_SCK_MAX      EQU 20000000 ; 20 Mhz orginally
FLASH_CE			 EQU P0.3
SPEAKER 			 EQU P2.0
READ_BYTES     EQU 0x03  ; Address:3 Dummy:0 Num:1 to infinite

PUSHBUTTON     EQU P1.1

cseg

org 0x0000 ; Reset vector
ljmp MainProgram

org 0x0003 ; External interrupt 0 vector (not used in this code)
reti

org 0x000B ; Timer/Counter 0 overflow interrupt vector (not used in this code)
	inc R7
	reti

org 0x0013 ; External interrupt 1 vector (not used in this code)
reti

org 0x001B ; Timer/Counter 1 overflow interrupt vector (not used in this code
reti

org 0x0023 ; Serial port receive/transmit interrupt vector (not used in this code)
reti

org 0x005b ; Timer 2 interrupt vector.  Used in this code to replay the wave file.
ljmp Timer2_ISR

; Variables used in the program:
dseg at 30H
w:   ds 3 ; 24-bit play counter.  Decremented in Timer 2 ISR.
x:   ds 4
y:   ds 4
bcd: ds 5

BSEG
mf: dbit 1
zero: dbit 1
ten: dbit 1
twenty: dbit 1
thirty: dbit 1
forty: dbit 1
fifty: dbit 1
sixty: dbit 1
seventy: dbit 1
eighty: dbit 1
ninety: dbit 1
hundred: dbit 1
mode: dbit 1

$NOLIST
$include(math32.inc)
$LIST

LCD_RS equ P2.6
LCD_RW equ P2.5
LCD_E  equ P2.4
LCD_D4 equ P2.3
LCD_D5 equ P2.2
LCD_D6 equ P2.1
LCD_D7 equ P1.7

$NOLIST
$include(LCD_4bit_72MHz.inc)
$LIST

cseg

Left_blank mac
	mov a, %0
	anl a, #0xf0
	swap a
	jz Left_blank_%M_a
	ljmp %1
	Left_blank_%M_a:
		Display_char(#' ')
		mov a, %0
		anl a, #0x0f
		jz Left_blank_%M_b
		ljmp %1
	Left_blank_%M_b:
		Display_char(#' ')
endmac

Display_10_digit_BCD:
	Set_Cursor(2, 7)
	Display_BCD(bcd+4)
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	; Replace all the zeros to the left with blanks
	Set_Cursor(2, 7)
	Left_blank(bcd+4, skip_blank)
	Left_blank(bcd+3, skip_blank)
	Left_blank(bcd+2, skip_blank)
	Left_blank(bcd+1, skip_blank)
	mov a, bcd+0
	anl a, #0f0h
	swap a
	jnz skip_blank
	Display_char(#' ')
	skip_blank:
	ret

Display_formated_BCD:
	Set_Cursor(2, 7)
	Display_char(#' ')
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	Display_char(#'.')
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
  ret

	; This 'wait' must be as precise as possible. Sadly the 24.5MHz clock in the EFM8LB1 has an accuracy of just 2%.

Wait_hundred_milliseconds:
	    ;For a 72MHz clock one machine cycle takes 1/72MHz=13.88889ns
 			mov R2, #17 ; Calibrate using this number to account for overhead delays
	X3: mov R1, #235
	X2: mov R0, #255
	X1: djnz R0, X1 ; 3 machine cycles -> 3*13.88889ns*255 = 10.625us (see table 10.2 in reference manual)
	    djnz R1, X2 ; 20.44898us*255 = 2.709375ms
	    djnz R2, X3 ; 2.709375ms*184 = 498.525ms
	    ret

Test_msg:  db 'Capacitance (nF)', 0

Timer2_ISR:
	mov	SFRPAGE, #0x00
	clr	TF2H ; Clear Timer2 interrupt flag

	; The registers used in the ISR must be saved in the stack
	push acc
	push psw

	; Check if the play counter is zero.  If so, stop playing sound.
	mov a, w+0
	orl a, w+1
	orl a, w+2
	jz stop_playing

	; Decrement play counter 'w'.  In this implementation 'w' is a 24-bit counter.
	mov a, #0xff
	dec w+0
	cjne a, w+0, keep_playing
	dec w+1
	cjne a, w+1, keep_playing
	dec w+2

	keep_playing:

	setb SPEAKER
	lcall Send_SPI ; Read the next byte from the SPI Flash...

	; It gets a bit complicated here because we read 8 bits from the flash but we need to write 12 bits to DAC:
	mov SFRPAGE, #0x30 ; DAC registers are in page 0x30
	push acc ; Save the value we got from flash
	swap a
	anl a, #0xf0
	mov DAC0L, a
	pop acc
	swap a
	anl a, #0x0f
	mov DAC0H, a
	mov SFRPAGE, #0x00

	sjmp Timer2_ISR_Done

	stop_playing:
	clr TR2 ; Stop timer 2
	setb FLASH_CE  ; Disable SPI Flash
	clr SPEAKER ; Turn off speaker.  Removes hissing noise when not playing sound.

	Timer2_ISR_Done:
	pop psw
	pop acc
	reti

Send_SPI:
	mov	SPI0DAT, a
	Send_SPI_L1:
	jnb	SPIF, Send_SPI_L1 ; Wait for SPI transfer complete
	clr SPIF ; Clear SPI complete flag
	mov	a, SPI0DAT
	ret

Init_all:
	; Disable WDT:
	mov	WDTCN, #0xDE
	mov	WDTCN, #0xAD

	mov	VDM0CN, #0x80
	mov	RSTSRC, #0x06

	; Switch SYSCLK to 72 MHz.  First switch to 24MHz:
	mov	SFRPAGE, #0x10
	mov	PFE0CN, #0x20
	mov	SFRPAGE, #0x00
	mov	CLKSEL, #0x00
	mov	CLKSEL, #0x00 ; Second write to CLKSEL is required according to datasheet
  mov P0SKIP, #00011_1000B
	; Wait for clock to settle at 24 MHz by checking the most significant bit of CLKSEL:
	Init_L1:
	mov	a, CLKSEL
	jnb	acc.7, Init_L1

	 ;Now switch to 72MHz:
		mov	CLKSEL, #0x03
		mov	CLKSEL, #0x03  ; Second write to CLKSEL is required according to datasheet

	; Wait for clock to settle at 72 MHz by checking the most significant bit of CLKSEL:
	Init_L2:
		mov	a, CLKSEL
		jnb	acc.7, Init_L2

	mov	SFRPAGE, #0x00

	; Configure P3.0 as analog output.  P3.0 pin is the output of DAC0.
	anl	P3MDIN, #0xFE
	orl	P3, #0x01

	; Configure the pins used for SPI (P0.0 to P0.3)
	mov	P0MDOUT, #0x1D ; SCK, MOSI, P0.3, TX0 are push-pull, all others open-drain

	mov	XBR0, #0x02 ; ***********changed from 0x03 to 0x02 (we don't need to enable UART0)
	mov	XBR1, #0x10 ; *********** Changed from 0x00 to 0x10 TR0 is enabled
	mov	XBR2, #0x40 ; Enable crossbar and weak pull-ups

	; Configure DAC 0
	mov	SFRPAGE, #0x30 ; To access DAC 0 we use register page 0x30
	mov	DACGCF0, #0b_1000_1000 ; 1:D23REFSL(VCC) 1:D3AMEN(NORMAL) 2:D3SRC(DAC3H:DAC3L) 1:D01REFSL(VCC) 1:D1AMEN(NORMAL) 1:D1SRC(DAC1H:DAC1L)
	mov	DACGCF1, #0b_0000_0000
	mov	DACGCF2, #0b_0010_0010 ; Reference buffer gain 1/3 for all channels
	mov	DAC0CF0, #0b_1000_0000 ; Enable DAC 0
	mov	DAC0CF1, #0b_0000_0010 ; DAC gain is 3.  Therefore the overall gain is 1.
	; Initial value of DAC 0 is mid scale:
	mov	DAC0L, #0x00
	mov	DAC0H, #0x08
	mov	SFRPAGE, #0x00

	; Configure SPI
	mov	SPI0CKR, #((SYSCLK/(2*F_SCK_MAX))-1)
	mov	SPI0CFG, #0b_0100_0000 ; SPI in master mode
	mov	SPI0CN0, #0b_0000_0001 ; SPI enabled and in three wire mode
	setb FLASH_CE ; CS=1 for SPI flash memory
	clr SPEAKER ; Turn off speaker.

	;Initializes timer/counter 0 as a 16-bit counter
	clr TR0 ; Stop timer 0
	mov a, TMOD
	anl a, #0b_1111_0000 ; Clear the bits of timer/counter 0
	orl a, #0b_0000_0101 ; Sets the bits of timer/counter 0 for a 16-bit counter
	mov TMOD, a

	; Configure Timer 2 and its interrupt
	mov	TMR2CN0,#0x00 ; Stop Timer2; Clear TF2
	orl	CKCON0,#0b_0001_0000 ; Timer 2 uses the system clock
	; Initialize reload value:
	mov	TMR2RLL, #low(TIMER2_RELOAD)
	mov	TMR2RLH, #high(TIMER2_RELOAD)
	; Set timer to reload immediately
	mov	TMR2H,#0xFF
	mov	TMR2L,#0xFF
	setb ET2 ; Enable Timer 2 interrupts
	;setb TR2 ; Timer 2 is only enabled to play stored sound

	setb EA ; Enable interrupts

	clr zero
	clr ten
	clr twenty
	clr thirty
	clr forty
	clr fifty
	clr sixty
	clr seventy
	clr eighty
	clr ninety
	clr hundred
	ret

PlaySound mac
  clr TR2 ; Stop Timer 2 ISR from playing previous request
  setb FLASH_CE
  clr SPEAKER ; Turn off speaker.

  clr FLASH_CE ; Enable SPI Flash
  mov a, #READ_BYTES
  lcall Send_SPI
  ; Set the initial position in memory where to start playing
  mov a, %0
  lcall Send_SPI
  mov a, %1
  lcall Send_SPI
  mov a, %2
  lcall Send_SPI
  mov a, #0x00 ; Request first byte to send to DAC
  lcall Send_SPI

  ; How many bytes to play? All of them!  Asume 4Mbytes memory: 0x3fffff
  mov w+2, %3
  mov w+1, %4
  mov w+0, %5

  setb SPEAKER ; Turn on speaker.
  setb TR2 ; Start playback by enabling Timer 2

	;lcall check_over
endmac

check_over:
	mov a, w+0
	orl a, w+1
	orl a, w+2
	cjne a, #0x00, check_over
	ret

play_ZERO:
	jb mode, play_ZERO_ml
	PlaySound(#0x00, #0x00, #0x00, #0x00, #0x7C, #0x06)
	ret
	play_ZERO_ml:
		PlaySound(#0x06, #0x42, #0x80, #0x00, #0x4C, #0x93)
	ret

play_TEN:
	jb mode, play_TEN_ml
	PlaySound(#0x00, #0x90, #0xF6, #0x00, #0x69, #0x41)
	ret
	play_TEN_ml:
		PlaySound(#0x06, #0xB0, #0x52, #0x00, #0x68, #0xA7)
	ret

play_TWENTY:
	jb mode, play_TWENTY_ml
	PlaySound(#0x01, #0x11, #0x8F, #0x00, #0x73, #0xC3)
	ret
	play_TWENTY_ml:
		PlaySound(#0x07, #0x37, #0xA3, #0x00, #0x71, #0x2D)
	ret

play_THIRTY:
	jb mode, play_THIRTY_ml
	PlaySound(#0x01, #0xA1, #0x66, #0x00, #0x6A, #0x60)
	ret
	play_THIRTY_ml:
	 PlaySound(#0x07, #0xCA, #0x10, #0x00, #0xAF, #0xFA)
	ret

play_FORTY:
  jb mode, play_FORTY_ml
	PlaySound(#0x02, #0x25, #0x87, #0x00, #0x71, #0x5A)
	ret
	play_FORTY_ml:
	 PlaySound(#0x08, #0x92, #0x10, #0x00, #0xB6, #0x2B)
	ret

play_FIFTY:
  jb mode, play_FIFTY_ml
	PlaySound(#0x02, #0xAD, #0x1A, #0x00, #0x70, #0x3B)
	ret
	play_FIFTY_ml:
	 PlaySound(#0x09, #0x64, #0xBE, #0x00, #0xA8, #0x90)
	ret

play_SIXTY:
  jb mode, play_SIXTY_ml
	PlaySound(#0x03, #0x37, #0x16, #0x00, #0x77, #0x4B)
	ret
	play_SIXTY_ml:
   PlaySound(#0x0A, #0x2B, #0xF8, #0x00, #0xA6, #0xD6)
	ret

play_SEVENTY:
  jb mode, play_SEVENTY_ml
	PlaySound(#0x03, #0xCB, #0x94, #0x00, #0x80, #0x99)
	ret
	play_SEVENTY_ml:
   PlaySound(#0x0A, #0xF2, #0x55, #0x00, #0xBB, #0x40)
	ret

play_EIGHTY:
  jb mode, play_EIGHTY_ml
	PlaySound(#0x04, #0x62, #0x66, #0x00, #0x6F, #0x1C)
	ret
	play_EIGHTY_ml:
   PlaySound(#0x0B, #0xCC, #0x3F, #0x00, #0xA8, #0x7A)
	ret

play_NINETY:
  jb mode, play_NINETY_ml
	PlaySound(#0x04, #0xE5, #0x52, #0x00, #0x7A, #0xD3)
	ret
	play_NINETY_ml:
	 PlaySound(#0x0C, #0x95, #0x1C, #0x00, #0xAC, #0xC8)
	ret

play_HUNDRED:
  jb mode, play_HUNDRED_ml
	PlaySound(#0x05, #0x76, #0x5E, #0x00, #0x89, #0xE6)
	ret
	play_HUNDRED_ml:
	  PlaySound(#0x0D, #0x64, #0xC6, #0x00, #0xBB, #0x57)
	ret

Capacitance_Loop:
  clr TR0 ; Stop counter 0
  mov TL0, #0
  mov TH0, #0

  mov R7, #0

  clr TF0 ; Clear overflow flag

  setb ET0  ; Enable timer 0 interrupt
  setb EA ; Enable global interrupts
  setb TR0 ; Start counter 0
  lcall Wait_hundred_milliseconds
  clr TR0 ; Stop counter 0, R7-TH0-TL0 has the frequency

  mov y+0, TL0
  mov y+1, TH0
  mov y+2, R7
  mov y+3, #0

	;Load_x(10)
	;lcall mul32

  Load_x(2181818)
  lcall div32

  ;lcall hex2bcd
  ;lcall Display_formated_BCD
	;lcall Display_10_digit_BCD
	ret

clr_all_level_bits:
	clr hundred
	clr ninety
	clr eighty
	clr seventy
	clr sixty
	clr fifty
	clr forty
	clr thirty
	clr twenty
	clr ten
	clr zero
	ret

WaterLevel_Loop:
	Load_y(12200)
	lcall x_gteq_y
	jnb mf, hundred_cont
	jnb hundred, voice_hundred
	ljmp go_back
	voice_hundred:
	lcall play_hundred
	lcall clr_all_level_bits
	setb hundred
	ret
	hundred_cont:

	Load_y(12100)
	lcall x_gteq_y
	jnb mf, ninety_cont
	jnb ninety, voice_ninety
	ljmp go_back
	voice_ninety:
	lcall play_ninety
	lcall clr_all_level_bits
	setb ninety
	ret
	ninety_cont:

	Load_y(11848)
	lcall x_gteq_y
	jnb mf, eighty_cont
	jnb eighty, voice_eighty
	ljmp go_back
	voice_eighty:
	lcall play_eighty
	lcall clr_all_level_bits
	setb eighty
	ret
	eighty_cont:

	Load_y(11647)
	lcall x_gteq_y
	jnb mf, seventy_cont
	jnb seventy, voice_seventy
	ljmp go_back
	voice_seventy:
	lcall play_SEVENTY
	lcall clr_all_level_bits
	setb seventy
	ret
	seventy_cont:

	Load_y(11446)
	lcall x_gteq_y
	jnb mf, sixty_cont
	jnb sixty, voice_sixty
	ljmp go_back
	voice_sixty:
	lcall play_SIXTY
	lcall clr_all_level_bits
	setb sixty
	ret
	sixty_cont:

	Load_y(11245)
	lcall x_gteq_y
	jnb mf, fifty_cont
	jnb fifty, voice_fifty
	ljmp go_back
	voice_fifty:
	lcall play_FIFTY
	lcall clr_all_level_bits
	setb fifty
	ret
	fifty_cont:

	Load_y(11044)
	lcall x_gteq_y
	jnb mf, forty_cont
	jnb forty, voice_forty
	ljmp go_back
	voice_forty:
	lcall play_FORTY
	lcall clr_all_level_bits
	setb forty
	ret
	forty_cont:

	Load_y(10843)
	lcall x_gteq_y
	jnb mf, thirty_cont
	jb thirty, go_back
	lcall play_THIRTY
	lcall clr_all_level_bits
	setb thirty
	ret
	thirty_cont:

	Load_y(10642)
	lcall x_gteq_y
	jnb mf, twenty_cont
	jb twenty, go_back
	lcall play_TWENTY
	lcall clr_all_level_bits
	setb twenty
	ret
	twenty_cont:

	Load_y(10441)
	lcall x_gteq_y
	jnb mf, ten_cont
	jb ten, go_back
	lcall play_TEN
	lcall clr_all_level_bits
	setb ten
	ret
	ten_cont:

	Load_y(10000)
	lcall x_gteq_y
	jnb mf, go_back
	jb zero, go_back
	lcall play_ZERO
	lcall clr_all_level_bits
	setb zero
	ret
	go_back:
	ret

button_sensor:
	jb PUSHBUTTON, go_back  ; if the 'BOOT' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.
	jb PUSHBUTTON, go_back  ; if the 'BOOT' button is not pressed skip
	jnb PUSHBUTTON, $		; Wait for button release.  The '$' means: jump to same instruction.
	; A valid press of the 'BOOT' button has been detected, reset the BCD counter.
  jb mode, mode_percent
	setb mode
	PlaySound(#0x11,#0x42,#0xC9,#0x00, #0xA8, #0x90)
	lcall check_over
  lcall clr_all_level_bits
	lcall WaterLevel_Loop
	ret

	mode_percent:
	clr mode
	PlaySound(#0x10,#0x8B,#0xD7,#0x00, #0x95, #0xC9)
	lcall check_over
	lcall clr_all_level_bits
	lcall WaterLevel_Loop
	ret


MainProgram:
  mov SP, #0x7f ; Setup stack pointer to the start of indirectly accessable data memory minus one
  lcall Init_all ; Initialize the hardware
  clr mode

;	lcall LCD_4BIT
; Set_Cursor(1, 1)
;	Send_Constant_String(#Test_msg)
	PlaySound(#0x0E, #0x3E, #0xC7, #0x02, #0x2A, #0xF4)
	lcall check_over

  MainLoop:
	lcall Capacitance_Loop
	lcall WaterLevel_Loop
	lcall button_sensor
	ljmp MainLoop
