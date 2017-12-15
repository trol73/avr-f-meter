; *******************************************************
; * Frequencycounter, RPM-Meter and Voltmeter           *
; * for ATmega8 at 16 MHz crystal clock frequency       *
; * with prescaler /1 or /16                            *
; * Version 0.3 (C)2009 by info!at!avr-asm-tutorial.net *
; *******************************************************
;
.INCLUDE "m8def.inc"
;
.EQU debug = 0
.EQU debugpulse = 0
;
; Switches for connected hardware
;
.EQU cUart = 1 		; Uart active

; attached prescaler on port C
.EQU pPresc = PORTC 	; prescaler by 16 output attached to port C
.EQU pPrescD = DDRC 	; data direction of prescaler
.EQU bPresc = 5 		; bit 5 enables prescaler by 16
;
; ================================================
;          Other hardware depending stuff
; ================================================
;
.EQU cFreq = 16000000 	; Clock frequency processor in cycles/s
.IF cUart
	.EQU cBaud = 9600 	; If Uart active, define Baudrate
.ENDIF
.EQU bLcdE = 5 		; LCD E port bit on Port B
.EQU bLcdRs = 4 		; Lcd RS port bit on Port B
;
; ================================================
;       Constants for voltage measurement
; ================================================
;
; Resistor network as pre-divider for the ADC
; --------------------------------------
; R1   R2(k) Meas  Accur.  MaxVoltage
; kOhm kOhm  Volt  mV/dig  Volt
; --------------------------------------
; 1000 1000   5,12    5    10
; 1000  820   5,68    6    11
; 1000  680   6,32    6    12
; 1000  560   7,13    7    14
; 1000  470   8,01    8    15
; 1000  330  10,32   10    20
; 1000  270  12,04   12    23
; 1000  220  14,20   14    27
; 1000  180  16,78   16    32
; 1000  150  19,63   19    38
; 1000  120  23,98   23    46
; 1000  100  28,16   28    55
;
.EQU cR1 = 1000 		; Resistor between ADC input and measured voltage
.EQU cR2 = 1000 		; Resistor between ADC input and ground
.EQU cRin = 8250 		; Input resistance ADC, experimental 
;
; Other sSoft switches
;
.EQU cNMode = 3 		; number of measurements before mode changes
.EQU cDecSep = '.' 		; decimal separator for numbers displayed
.EQU c1kSep = ',' 		; thousands separator
.EQU nMeasm = 4 		; number of measurements per second
.IF (nMeasm < 4) || (nMeasm > 7)
	.ERROR "Number of measurements outside acceptable range"
.ENDIF
;
; ================================================
;           Hardware connections
; ================================================
;                     ___   ___
;              RESET |1  |_| 28| Prescaler divide by 16 output   (PC5)
;                RXD |2   A  27| 
;                TXD |3   T  26| 
; (PD2,INT0)Time inp |4   M  25| 
;                    |5   E  24| Mode select input, 0..2.56 V    (PC1, ADC1 -> ENC-B)
; (PD4,R0)  Count in |6   L  23| Voltage input, 0..2.56 V        (PC0, ADC1 -> ENC-A)	
;                VCC |7      22| GND
;                GND |8   A  21| AREF (+2.56 V, output)
;              XTAL1 |9   T  20| AVCC input
;              XTAL2 |10  m  19| SCK/LCD-E                       (PB5)
;                    |11  e  18| MISO/LCD-RS                     (PB4)
;                    |12  g  17| MOSI/LCD-D7                     (PB3)
;                    |13  a  16| LCD-D6                          (PB2)
; (PB0)       LCD-D4 |14  8  15| LCD-D5                          (PB1)
;                    |_________|
;
;
; ================================================
;           Derived constants
; ================================================
;
.EQU cR2c = (cR2 * cRin) / (cR2+cRin)
.EQU cMultiplier = (641 * (cR1+cR2c))/cR2c 			; used for voltage multiplication
.EQU cMaxVoltage = 1024*cMultiplier/256 			; in mV

.EQU cSafeVoltage = (cMaxVoltage * 5000) / 2560
.EQU cTDiv = 1000/nMeasm 						; interval per measurement update


; calculating the CTC and prescaler values for TC1 (frequency measurement)
.SET cCmp1F = cFreq / 32 			; CTC compare value with counter prescaler = 8
.SET cPre1F = (1<<WGM12)|(1<<CS11) 	; CTC and counter prescaler = 8
.IF cFreq > 2097120
	.SET cCmp1F = cFreq/256 			; CTC compare value with counter prescaler = 64
	.SET cPre1F = (1<<WGM12)|(1<<CS11)|(1<<CS10) ; counter prescaler = 64
.ENDIF
.IF cFreq > 16776960
	.SET cCmp1F = cFreq / 1024 		; CTC compare value with counter prescaler = 256
	.SET cPre1F = (1<<WGM12)|(1<<CS12) ; counter prescaler = 256
.ENDIF

; calculating the CTC and counter prescaler values for TC2 (LCD/UART update) 
.SET cCmp2 = cFreq/8000
.SET cPre2 = (1<<CS21) 				; counter prescaler = 8
.IF cFreq > 2040000
	.SET cCmp2 = cFreq / 32000
	.SET cPre2 = (1<<CS21)|(1<<CS20) 	; counter prescaler = 32
.ENDIF
.IF cFreq > 8160000
	.SET cCmp2 = cFreq/64000
	.SET cPre2 = (1<<CS22) 			; counter prescaler = 64
.ENDIF
.IF cFreq > 16320000
	.SET cCmp2 = cFreq/128000 		; counter prescaler = 128
	.SET cPre2 = (1<<CS22)|(1<<CS20) 
.ENDIF
;
; Uart constants
;
.IF cUart
	.EQU cNul = $00
	.EQU cClrScr = $0C
	.EQU cCR = $0D
	.EQU cLF = $0A
.ENDIF
;
; Debug definitions for testing
;
; (none)
;
; ================================================
;            Register definitons
; ================================================
;
; R0 used for LPM and for calculation purposes
.DEF rRes1 = R1 		; Result byte 1
.DEF rRes2 = R2 		; Result byte 2
.DEF rRes3 = R3 		; Result byte 3
.DEF rRes4 = R4 		; Result byte 4
.DEF rDiv1 = R5 		; Divisor byte 1
.DEF rDiv2 = R6 		; Divisor byte 2
.DEF rDiv3 = R7 		; Divisor byte 3
.DEF rDiv4 = R8 		; Divisor byte 4
.DEF rCpy1 = R9 		; Copy byte 1
.DEF rCpy2 = R10 		; Copy byte 2
.DEF rCpy3 = R11 		; Copy byte 3
.DEF rCpy4 = R12 		; Copy byte 4
.DEF rCtr1 = R13 		; Counter/Timer byte 1
.DEF rCtr2 = R14 		; Counter/Timer byte 2
.DEF rCtr3 = R15 		; Counter/Timer byte 3
.DEF rmp = R16 		; Multipurpose register outside interrupts
.DEF rimp = R17 		; Multipurpose register inside interrupts
.DEF rSreg = R18 		; Save status register inside interrupts
.DEF rTDiv = R19 		; Internal divider for TC2 count down
.DEF rMode = R20 		; Current mode of operation
.DEF rNMode = R21 		; Number of inadequate measurements
.DEF rir = R22 		; interrim calculation register
.DEF rFlg = R23 		; Flag register
.EQU bCyc = 2 			; measure cycle ended
.EQU bMode = 3 		; measuring mode, 1 = frequency, 0 = time
.EQU bEdge = 4 		; measured edge, 1 = rising, 0 = falling
.EQU bOvf = 5 			; overflow bit
.EQU bUartRxLine = 7 	; Uart line complete flag bit
.DEF rDelL = R24 		; delay counter for LCD, LSB
.DEF rDelH = R25 		; dto., MSB
; X = R26..R27 used for calculation purposes
; Y = R28..R29: free
; Z = R30..R31 used for LPM and calculation purposes
;
; ================================================
;             SRAM definitions
; ================================================
;
.DSEG
.ORG Sram_Start
;
; Result display space in SRAM
;
s_video_mem:
	.BYTE 32
;
; Uart receive buffer space in SRAM
;   sUartRxBs is buffer start
;   sUartRxBe is buffer end
;   sUartRxBp is buffer input position
;
.IF cUart
	.EQU UartRxbLen = 38 		; Buffer length in bytes
;
	sUartFlag: 				; flag register for Uart
		.BYTE 1
		.EQU bUMonU = 0 		; displays voltage over Uart
		.EQU bUMonF = 1 		; displays frequency over Uart
		; free: bits 2..7
	sUartMonUCnt: 				; counter for Monitoring voltage
		.BYTE 1
	sUartMonURpt: 				; counter preset for monitoring voltage
		.BYTE 1
    sUartMonFCnt: 				; counter for Monitoring frequency
		.BYTE 1
	sUartMonFRpt: 				; counter preset for monitoring voltage
		.BYTE 1
	sUartRxBp: 				; buffer pointer
		.BYTE 1
	sUartRxBs: 				; buffer
		.BYTE UartRxbLen
	sUartRxBe: 				; buffer end
.ENDIF
;
; Main interval timer characteristics
;
sTMeas: ; ms per measuring interval (default: 250)
	.BYTE 1

;
; Interim storage for counter value during time measurement
;
sCtr:
	.BYTE 4
;
; ================================================
;          Selected mode flags
; ================================================
;
;  Mode   Measuring  Prescale  Display
;  ---------------------------------------------
;   0     Frequency   16       Frequency
;   1     Frequency    1       Frequency
;   2     Time HL      1       Frequency
;   3     Time HL      1       Rounds per Minute
;   4     Time HL      1       Time
;   5     Time H       1       Time
;   6     Time L       1       Time
;   7     PW ratio H   1       Pulse width ratio H %
;   8     PW ratio L   1       Pulse width ratio L %
;   9     none         -       Voltage only
;                              (for a single line LCD)
;
.EQU cModeFrequency16 = 0
.EQU cModeFrequency = 1
.EQU cModeTimeFreq = 2
.EQU cModeTimeRpm = 3
.EQU cModeTimeTimeHL = 4
.EQU cModeTimeTimeH = 5
.EQU cModeTimeTimeL = 6
.EQU cModeTimePwrH = 7
.EQU cModeTimePwrL = 8
.EQU cModeVoltage = 9
;
sModeSlct: ; Selected mode
	.BYTE 1
sModeNext: ; next selected mode
	.BYTE 1

sEncoderPrev:	; Encoder previous value
	.BYTE 1
;
; ==================================================
;   Info on timer and counter interrupt operation
; ==================================================
;
; Clock => Presc2 => TC2 => CTC => rTDiv =>
;
; Main interval timer TC2
;    - uses TC2 as 8-bit-CTC, with compare interrupt
;    - starts a ADC conversion
;    - on ADC conversion complete:
;      * store ADC result
;      * convert ADC result
;      * if a new counter result: convert this
;      * if Uart connected and monitoring f/U: display on Uart
;      * if LCD connected and display mode: display f/U result  
; 
; Operation at 16 MHz clock:
;   cFreq => Prescaler/128 => CTC(125) => rTDiv(250)
;   16MHz =>   125 kHz     =>  1 kHz   =>   4 Hz
;
; Frequeny counting modes (Mode = 0 and 1)
;    - uses TC0 as 8-bit-counter to count positive edges
;    - uses TC1 as 16-bit-counter to time-out the counter after 250 ms
;
; Timer modes (Mode = 2 to 8)
;    - uses edge detection on external INT0 for timeout
;    - uses TC1 as 16-bit-counter to time-out from edge to edge
;
; Voltage only (Mode = 9)
;    - Timers TC0 and TC1 off
;    - Timer TC2 times interval
;
; ==============================================
;   Reset and Interrupt Vectors starting here
; ==============================================
;
.CSEG
.ORG $0000
;
; Reset/Intvectors
;
	rjmp Main            ; Reset
	rjmp Int0Int         ; Int0
	reti                 ; Int1
	rjmp TC2CmpInt       ; TC2 Comp
	reti                 ; TC2 Ovf
	reti                 ; TC1 Capt
	rjmp Tc1CmpAInt      ; TC1 Comp A
	reti                 ; TC1 Comp B
	rjmp Tc1OvfInt       ; TC1 Ovf
	rjmp TC0OvfInt       ; TC0 Ovf
	reti                 ; SPI STC
.IF cUart
	rjmp SioRxcIsr       ; USART RX
.ELSE
	reti                 ; USART RX
.ENDIF
	reti                 ; USART UDRE
	reti                 ; USART TXC
	reti
	reti                 ; EERDY
	reti                 ; ANA_COMP
	reti                 ; TWI
	reti                 ; SPM_RDY
;
; =============================================
;
;     Interrupt Service Routines
;
; =============================================
;
; TC2 Compare Match Interrupt
;   counts rTDiv down, if zero: starts an AD conversion
;
TC2CmpInt:
	in 	rSreg, SREG 		; save SREG
	dec 	rTDiv 			; count down
	brne	TC2CmpInt1 		; not zero, interval not ended
	lds	rTDiv, sTMeas 		; restart interval timer
TC2CmpInt1:
	out	SREG, rSreg 		; restore SREG
	reti
;
; External Interrupt INT0 Service Routine
;   active in modes 2 to 6 (measuring the signal duration),
;   detects positive going edges of the input
;   INT1, TC1 is in free running mode,
;   reads the current counter state of TC1,
;   copies it to the result registers,
;   clears the counter and restarts it
;
Int0Int:
	in	rSreg, SREG 		; 1, save SREG
	sbrc	rFlg, bCyc 		; 2/3, check if cycle flag signals ok for copy
	rjmp	Int0Int1 			; 4, no, last result hasn't been read
	in	rCpy1, TCNT1L 		; 4, read timer 1 LSB
	in	rCpy2, TCNT1H 		; 5, dto., MSB
	mov	rCpy3, rCtr2 		; 6, copy the counter bytes
	mov	rCpy4, rCtr3 		; 7
	sbr	rFlg, 1<<bCyc 		; 8, set cycle end flag bit
	cbr	rFlg, 1<<bEdge 	; 9, set falling edge
	sbic	PIND, 2 			; 10/11, check if input = 0
	sbr	rFlg, 1<<bEdge 	; 11, no, set edge flag to rising
Int0Int1: 			; 4/11
	ldi	rimp, 0 			; 5/12, reset the timer
	out	TCNT1H, rimp 		; 6/13, set TC1 zero to restart
	out	TCNT1L, rimp 		; 7/14
	mov	rCtr1, rimp 		; 8/15, clear the upper bytes
	mov	rCtr2, rimp 		; 9/16
	mov	rCtr3, rimp 		; 10/17
	out	SREG, rSreg 		; 11/18, restore SREG
	reti 			; 15/22
;
; TC1 Compare Match A Interrupt Service Routine
;   active in modes 0 and 1 (measuring the number of
;   sigals on the T1 input), timeout every 0.25s,
;   reads the counter TC0, copies the count to
;   the result registers and clears TC0
;
Tc1CmpAInt:
	in	rSreg, SREG 		; 1, save SREG
	sbrc	rFlg, bCyc 		; 2/3, check if cycle flag signals ok for copy
	rjmp TC1CmpAInt1 		; 4, no, last result hasn't been read
	in	rCpy1, TCNT0 		; 4, read counter TC0
	mov	rCpy2, rCtr1 		; 5, copy counter bytes to result
	mov	rCpy3, rCtr2 		; 6
	mov	rCpy4, rCtr3 		; 7
	sbr	rFlg, 1<<bCyc 		; 8, set cycle end flag bit
Tc1CmpAInt1: 			; 4/8
	ldi	rimp, 0 			; 5/9, clear counter
	out	TCNT0, rimp 		; 6/10
	mov	rCtr1, rimp 		; 7/11, clear counter bytes
	mov	rCtr2, rimp 		; 8/12
	mov	rCtr3, rimp 		; 9/13
	out	SREG, rSreg 		; 10/14, restore SREG
	reti ; 			14/18
;
; TC1 Overflow Interrupt Service Routine
;   active in modes 2 to 6 counting clock cycles to measure time
;   increases the upper bytes and detects overflows
;
Tc1OvfInt:
	in	rSreg, SREG 			; 1, save SREG
	inc	rCtr2 				; 2, increase byte 3 of the counter
	brne	Tc1OvfInt1 			; 3/4, no overflow
	inc	rCtr3 				; 4, increase byte 4 of the counter
	brne	Tc1OvfInt1 			; 5/6, no overflow
	sbr	rFlg, (1<<bOvf)|(1<<bCyc) ; 6, set overflow and end of cycle bit
Tc1OvfInt1: 				; 4/6
	out	SREG, rSreg 			; 5/7, restore SREG
	reti					; 9/11
;
; TC0 Overflow Interrupt Service Routine
;   active in modes 0 and 1 counting positive edges on T1
;   increases the upper bytes and detects overflows
;
Tc0OvfInt:
	in	rSreg, SREG 			; 1, save SREG
	inc	rCtr1	 			; 2, increase byte 2 of the counter
	brne	Tc0OvfInt1 			; 3/4, no overflow
	inc	rCtr2 				; 4, increase byte 3 of the counter
	brne	Tc0OvfInt1 			; 5/6, no overflow
	inc	rCtr3 				; 6, increase byte 4 of the counter
	brne	Tc0OvfInt1 			; 7/8, no overflow
	sbr	rFlg, (1<<bOvf)|(1<<bCyc) ; 8, set overflow bit
Tc0OvfInt1: 				; 4/6/8
	out	SREG, rSreg 			; 5/7/9, restore SREG
	reti 					; 9/11/13
;
; Uart RxC Interrupt Service Routine
;   receives a character, signals errors, echoes it back,
;   puts it into the SRAM line buffer, checks for carriage
;   return characters, if yes echoes additional linefeed
;   and sets line-complete flag
;
.IF cUart
SioRxCIsr:
	in	rSreg, SREG 					; 1, Save SReg
	in	rimp, UCSRA 					; 2, Read error flags
	andi rimp, (1<<FE)|(1<<DOR)|(1<<PE) 	; 3, isolate error bits
	in	rimp, UDR 					; 4, read character from UART
	breq SioRxCIsr1 					; 5/6, no errors
	ldi	rimp, '*' 					; 6, signal an error
	out	UDR, rimp						; 7
	rjmp	SioRxCIsr4 					; 9, return from int
SioRxCIsr1: 							; 6
	out	UDR, rimp						; 7, echo the character
	push	ZH 							; 9, Save Z register
	push	ZL 							; 11
	ldi	ZH, HIGH(sUartRxBs) 			; 12, Load Position for next RX char
	lds	ZL, sUartRxBp 					; 14
	st	Z+, rimp 						; 16, save char in buffer
	cpi	ZL, LOW(sUartRxBe+1) 			; 17, End of buffer?
	brcc SioRxCIsr2 					; 18/19, Buffer overflow
	sts	sUartRxBp, ZL 					; 20, Save next pointer position
SioRxCIsr2: 							; 19/20
	cpi	rimp, cCR 					; 20/21, Carriage Return?
	brne SioRxCIsr3 					; 21/22/23, No, go on
	ldi	rimp, cLF 					; 22/23, Echo linefeed
	out	UDR, rimp 					; 23/24
	sbr	rFlg, (1<<bUartRxLine) 			; 24/25, Set line complete flag
	rjmp	SioRxCIsr3a
SioRxCIsr3: 							; 22/23/24/25
	cpi	rimp, cLF
	brne	SioRxCIsr3a
	sbr	rFlg, (1<<bUartRxLine)
SioRxCIsr3a:
	pop	ZL							; 24/25/26/27, restore Z-register
	pop	ZH							; 26/27/28/29
SioRxCIsr4:							; 9/26/27/28/29
	out	SREG, rSreg					; 10/27/28/29/30, restore SREG
	reti								; 14/31/32/33/34, return from Int
.ENDIF
;
; ================================================
;          Common subroutines
; ================================================
;
; Setting timer/counter modes for measuring
;
SetModeName:
	ldi	rmp, 0xC0 ; line 2
	rcall LcdRs4
	rcall delay40us ; delay 40 us
	ldi	ZL, LOW(2*MODE_0)
	ldi	ZH, HIGH(2*MODE_0)

	mov	rmp,	rMode
	lsl	rmp
	lsl	rmp
	lsl	rmp
	lsl	rmp						; mode * 16

	clr	XL				
	add	ZL, rmp
	adc	ZH, XL
	ldi	rmp, 16					; length
	ldi	XL, LOW(s_video_mem+16)
	ldi	XH, HIGH(s_video_mem+16)
	
LcdInitMode:
	lpm
	adiw	ZL, 1
	st	X+, R0
	dec	rmp
	brne LcdInitMode
	ldi	rmp,16
	rcall LcdText
	ret

MODE_0:
	.DB "1.Frequency (16)"
MODE_1:
	.DB "2.Frequency     "
MODE_2:
	.DB "3.Time HL, f    "
MODE_3:
	.DB "4.Time HL, rpm  "
MODE_4:
	.DB "5.Time HL, us   "
MODE_5:
	.DB "6.Time H        "
MODE_6:
	.DB "7.Time L        "
MODE_7:
	.DB "8.PW ratio H    "
MODE_8:
	.DB "9.PW ratio L    "
MODE_9:
	.DB "0.--------------"

;   0     Frequency   16       Frequency
;   1     Frequency    1       Frequency
;   2     Time HL      1       Frequency
;   3     Time HL      1       Rounds per Minute
;   4     Time HL      1       Time
;   5     Time H       1       Time
;   6     Time L       1       Time
;   7     PW ratio H   1       Pulse width ratio H %
;   8     PW ratio L   1       Pulse width ratio L %
;   9     none         -       Voltage only

	
SetModeNext:

	rcall	ClrTc 				; clear the timers TC0 and TC1, disable INT0
	lds 		rmp, sModeNext 		; read next mode
	mov		rMode, rmp
	rcall	SetModeName

	lds 		rmp, sModeNext 		; read next mode
	mov		rMode, rmp

	ldi		ZL, LOW(SetModeTab)
	ldi		ZH, HIGH(SetModeTab)
	add		ZL, rmp
	ldi		rmp, 0
	adc		ZH, rmp
	ijmp
	


;	rcall ClrTc ; clear the timers TC0 and TC1, disable INT0
;	lds rmp,sModeNext ; read next mode
;	mov rMode,rmp ; copy to current mode
;	ldi ZH,HIGH(SetModeTab)
;	ldi ZL,LOW(SetModeTab)
;	add ZL,rmp
;	ldi rmp,0
;	adc ZH,rmp
;	ijmp
	
; Table mode setting
SetModeTab:
	rjmp		SetMode0		; f div 16, f
	rjmp		SetMode1		; f, f
	rjmp		SetModeT		; t, f
	rjmp		SetModeT		; t, u
	rjmp		SetModeT		; t, t
	rjmp		SetModeE 		; th, t
	rjmp		SetModeE		; tl, t
	rjmp		SetModeE		; th, p
	rjmp		SetModeE		; tl, p
	ret 					; U, U
;
; Set counters/timers to mode 0
;   TC0 counts input signals (positive edges)
;   TC1 times the gate at 250 ms
;   INT0 disabled
;   
SetMode0:
	cbi	pPresc, bPresc 	; enable prescaler
	rjmp	SetModeF 			; frequency measurement
;
; Set counters/timers to mode 1
;
SetMode1:
	sbi	pPresc, bPresc 	; disable prescaler
; Set timer/counter mode to frequency measurement
SetModeF:
	ldi	rmp, HIGH(cCmp1F) 	; set the compare match high value
	out	OCR1AH, rmp
	ldi	rmp, LOW(cCmp1F) 	; set the compare match low value
	out	OCR1AL, rmp
	ldi	rmp, 0xFF 		; disable the compare match B
	out	OCR1BH, rmp
	out	OCR1BL, rmp
	ldi	rmp, 0 			; CTC mode
	out	TCCR1A, rmp
	ldi	rmp, cPre1F 		; set the prescaler value for TC1
	out	TCCR1B, rmp
	ldi	rmp, (1<<CS02)|(1<<CS01)|(1<<CS00) 	; count rising edges on T0
	out	TCCR0, rmp
	ldi	rmp, (1<<OCIE2)|(1<<OCIE1A)|(1<<TOIE0) ; enable TC2Cmp, TC1CmpAInt and TC0OverflowInt
	out	TIMSK, rmp
	ret
;
; Set timer/counter mode to time measurement
;
SetModeT:
	sbi	pPresc, bPresc 				; disable prescaler
	ldi	rmp, 0 						; timing mode
	out	TCCR1A, rmp
	ldi	rmp, 1<<CS10 					; count with prescaler = 1
	out	TCCR1B, rmp
	ldi	rmp, (1<<SE)|(1<<ISC01)|(1<<ISC00)	; sleep enable, positive edges on INT0 interrupt
	out	MCUCR, rmp
	ldi	rmp, 1<<INT0					; enable INT0 interrupt
	out	GICR, rmp
	ldi	rmp, (1<<OCIE2)|(1<<TOIE1)		; enable TC2Cmp, TC1Ovflw
	out	TIMSK, rmp
	ret
;
; Set timer/counter mode to time measurement, all edges
;
SetModeE:
	sbi pPresc, bPresc ; disable prescaler
	ldi rmp, 0 ; timing mode
	out TCCR1A,rmp
	ldi rmp, 1<<CS10 ; count with prescaler = 1
	out TCCR1B,rmp
	ldi rmp,(1<<SE)|(1<<ISC00) ; sleep enable, any logical change on INT0 interrupts
	out MCUCR,rmp
	ldi rmp,1<<INT0 ; enable INT0 interrupt
	out GICR,rmp
	ldi rmp,(1<<OCIE2)|(1<<TOIE1) ; enable TC2Cmp, TC1Ovflw
	out TIMSK,rmp
	ret
;
;
; clears the timers and resets the upper bytes
;
ClrTc:
	clr	rmp 					; disable INT0
	out	GICR, rmp
	clr	rmp					; stop the counters/timers
	out	TCCR0, rmp 			; stop TC0 counting/timing
	out	TCCR1B, rmp			; stop TC1 counting/timing
	out	TCNT0, rmp			; clear TC0
	out	TCNT1L, rmp			; clear TC1
	out	TCNT1H, rmp
	clr	rCtr1				; clear upper bytes
	clr	rCtr2
	clr	rCtr3
	ldi	rmp, 1<<OCIE2			; enable only output compare of TC2 ints
	out	TIMSK, rmp			; timer int disable
	ret
;
; =======================================================
;                 Math routines
; =======================================================
;
; Divides cFreq/256 by the timer value in rDiv4:rDiv3:rDiv2:rDiv1
;   yields frequency in R4:R3:R2:(Fract):R1
;
Divide:
	clr rmp ; rmp:R0:ZH:ZL:XH:XL is divisor
	clr R0
	clr ZH
	ldi ZL,BYTE3(cFreq/256) ; set divisor
	ldi XH,BYTE2(cFreq/256)
	ldi XL,BYTE1(cFreq/256)
	clr rRes1 ; set result
	inc rRes1
	clr rRes2
	clr rRes3
	clr rRes4
Divide1:
	lsl XL ; multiply divisor by 2
	rol XH
	rol ZL
	rol ZH
	rol R0
	rol rmp
	cp ZL,rDiv1 ; compare with divident
	cpc ZH,rDiv2
	cpc R0,rDiv3
	cpc rmp,rDiv4
	brcs Divide2
	sub ZL,rDiv1
	sbc ZH,rDiv2
	sbc R0,rDiv3
	sbc rmp,rDiv4
	sec
	rjmp Divide3
Divide2:
	clc
Divide3:
	rol rRes1
	rol rRes2
	rol rRes3
	rol rRes4
	brcc Divide1
	ret
;
; Multiply measured time in rRes4:rRes3:rRes2:rRes1 by 65536 / fq(MHz)
;   rmp:R0 are the upper bytes of the input
;   ZH:ZL:rDiv4:rDiv3:rDiv2:rDiv1 is the interim result
;   XH:XL is the multiplicator
;   result is in rRes4:rRes3:rRes2:rRes1
;
.EQU cMulti = 65536000 / (cFreq/1000)
;
Multiply:
	ldi XH,HIGH(cMulti) ; set multiplicator
	ldi XL,LOW(cMulti)
	clr ZH
	clr ZL
	clr rDiv4
	clr rDiv3
	clr rDiv2
	clr rDiv1
	clr R0
	clr rmp
Multiply1:
	cpi XL,0
	brne Multiply2
	cpi XH,0
	breq Multiply4
Multiply2:
	lsr XH
	ror XL
	brcc Multiply3
	add rDiv1,rRes1
	adc rDiv2,rRes2
	adc rDiv3,rRes3
	adc rDiv4,rRes4
	adc ZL,R0
	adc ZH,rmp
Multiply3:
	lsl rRes1
	rol rRes2
	rol rRes3
	rol rRes4
	rol R0
	rol rmp
	rjmp Multiply1
Multiply4:
	ldi rmp,128 ; round result
	clr R0
	add rDiv2,rmp
	adc rDiv3,R0
	adc rDiv4,R0
	adc ZL,R0
	adc ZH,R0
	mov rRes1,rDiv3 ; move result
	mov rRes2,rDiv4
	mov rRes3,ZL
	mov rRes4,ZH
	ret
;
; Display seconds at buffer end
;
DisplSec:
	ldi	rmp, ' '
	st	X+, rmp
	ldi	rmp, 'u'
	st	X+, rmp
	ldi	rmp, 's'
	st	X+, rmp
	ldi	rmp, ' '
	st	X, rmp
	ret
;
; An overflow has occurred during pulse width calculation
;
PulseOvflw:
	ldi	XL, LOW(s_video_mem)
	ldi	XH, HIGH(s_video_mem)
	st	X+, rmp

	ldi	ZL, LOW(2*TxtPOvflw16)
	ldi	ZH, HIGH(2*TxtPOvflw16)
	ldi	rmp, 15

PulseOvflw1:
	lpm
	adiw	ZL, 1
	st	X+, R0
	dec	rmp
	brne	PulseOvflw1
	ret
TxtPOvflw16:
	.DB ":error calcul.! "
;
; ======================================================
;     Pulse width calculations 
; ======================================================
;
; Calculate the pulse width ratio
;   active cycle time is in rDelH:rDelL:R0:rmp
;   total cycle time is in rDiv
;   result will be in rRes
;   overflow: carry flag is set
;
CalcPwO: ; overflow
	sec
	ret
CalcPw:
	mov rRes1,rmp ; copy active cycle time to rRes
	mov rRes2,R0
	mov rRes3,rDelL
	mov rRes4,rDelH
	lsl rRes1 ; * 2
	rol rRes2
	rol rRes3
	rol rRes4
	brcs CalcPwO ; overflow
	lsl rRes1 ; * 4
	rol rRes2
	rol rRes3
	rol rRes4
	brcs CalcPwO ; overflow
	lsl rRes1 ; * 8
	rol rRes2
	rol rRes3
	rol rRes4
	brcs CalcPwO ; overflow
	mov XL,rRes1 ; copy to Z:X
	mov XH,rRes2
	mov ZL,rRes3
	mov ZH,rRes4
	lsl rRes1 ; * 16
	rol rRes2
	rol rRes3
	rol rRes4
	brcs CalcPwO
	add rRes1,XL ; * 24
	adc rRes2,XH
	adc rRes3,ZL
	adc rRes4,ZH
	clr ZH ; clear the four MSBs of divisor
	clr ZL
	clr XH
	mov XL,rDelH ; * 256
	mov rDelH,rDelL
	mov rDelL,R0
	mov R0,rmp
	clr rmp
	lsl R0 ; * 512
	rol rDelL
	rol rDelH
	rol XL
	rol XH
	lsl R0 ; * 1024
	rol rDelL
	rol rDelH
	rol XL
	rol XH
	sub rmp,rRes1 ; * 1000
	sbc R0,rRes2
	sbc rDelL,rRes3
	sbc rDelH,rRes4
	sbc XL,ZH
	sbc XH,ZH
	cp XL,rDiv1 ; overflow?
	cpc XH,rDiv2
	cpc ZL,rDiv3
	cpc ZH,rDiv4
	brcc CalcPwO
	clr rRes1 ; clear result
	inc rRes1
	clr rRes2
	clr rRes3
	clr rRes4
CalcPw1: ; dividing loop
	lsl rmp ; multiply by 2
	rol R0
	rol rDelL
	rol rDelH
	rol XL
	rol XH
	rol ZL
	rol ZH
	cp XL,rDiv1 ; compare with divisor
	cpc XH,rDiv2
	cpc ZL,rDiv3
	cpc ZH,rDiv4
	brcs CalcPw2 ; smaller, roll zero in
	sub XL,rDiv1 ; subtract divisor
	sbc XH,rDiv2
	sbc ZL,rDiv3
	sbc ZH,rDiv4
	sec ; roll one in
	rjmp CalcPw3
CalcPw2:
	clc
CalcPw3: ; roll result
	rol rRes1
	rol rRes2
	rol rRes3
	rol rRes4
	brcc CalcPw1 ; roll on
	lsl rDelL ; round result
	rol XL
	rol XH
	rol ZL
	rol ZH
	cp XL,rDiv1
	cpc XH,rDiv2
	cpc ZL,rDiv3
	cpc ZH,rDiv4
	brcs CalcPw4
	ldi rmp,1 ; round up
	add rRes1,rmp
	ldi rmp,0
	adc rRes2,rmp
	adc rRes3,rmp
	adc rRes4,rmp
CalcPw4:
	tst rRes4 ; check > 1000
	brne CalcPwE
	tst rRes3
	brne CalcPwE
	ldi rmp,LOW(1001)
	cp rRes1,rmp
	ldi rmp,HIGH(1001)
	cpc rRes2,rmp
	brcc CalcPwE
	clc ; no error
	ret
CalcPwE: ; error
	sec
	ret
;
; Display the binary in R2:R1 in the form "  100,0%"
;
DisplPw:
	ldi	XL, LOW(s_video_mem)
	ldi	XH, HIGH(s_video_mem)
	ldi	rmp,' '
	st	X+, rmp
	st	X+, rmp
	clr	R0
	ldi	ZL, LOW(1000)
	ldi	ZH, HIGH(1000)
	rcall DisplDecX2
	ldi	ZL, LOW(100)
	ldi	ZH, HIGH(100)
	rcall	DisplDecX2
	ldi	ZL, 10
	inc	R0
	rcall DisplDecX2
	ldi	rmp, cDecSep
	st	X+, rmp
	ldi	rmp, '0'
	add	rmp, rRes1
	st	X+, rmp
	ldi	rmp, '%'
	st	X+, rmp
	ldi	ZL, ' '
	ldi	rmp, 8	
DisplPw1:
	st	X+, ZL
	dec	rmp
	brne	DisplPw1
	ret
;
; If the first characters in the result buffer are empty,
;   place the character in ZL here and add equal, if possible
;
DisplMode:
	ldi	XL, LOW(s_video_mem+1)
	ldi	XH, HIGH(s_video_mem+1)					; point to result buffer	
	ld	rmp, X 							; read second char
	cpi	rmp, ' '
	brne	DisplMode1
	ldi	rmp, '='
	st	X, rmp
DisplMode1:
	sbiw	XL, 1
	ld	rmp, X 							; read first char
	cpi	rmp, ' '
	brne	DisplModeEnd
	st	X,ZL
DisplModeEnd:
	ret
;
;=================================================
;        Display binary numbers as decimal
;=================================================
;
; Converts a binary in R2:R1 to a digit in X
;   binary in Z
;
DecConv:
	clr rmp
DecConv1:
	cp R1,ZL ; smaller than binary digit?
	cpc R2,ZH
	brcs DecConv2 ; ended subtraction
	sub R1,ZL
	sbc R2,ZH
	inc rmp
	rjmp DecConv1
DecConv2:
	tst rmp
	brne DecConv3
	tst R0
	brne DecConv3
	ldi rmp,' ' ; suppress leading zero
	rjmp DecConv4
DecConv3:
	subi rmp,-'0'
DecConv4:
	st X+,rmp
	ret
;
; Display fractional number in R3:R2:(Fract)R1
;
DisplFrac:
	ldi XL,LOW(s_video_mem)
	ldi XH,HIGH(s_video_mem)
	ldi rmp,' '
	st X+,rmp
	st X+,rmp

	clr R0
	ldi ZL,LOW(10000)
	ldi ZH,HIGH(10000)	
	rcall DisplDecY2
	ldi ZL,LOW(1000)
	ldi ZH,HIGH(1000)
	rcall DisplDecY2

	ldi rmp,c1kSep
	tst R0
	brne DisplFrac0
	ldi rmp,' '
DisplFrac0:
	st X+,rmp

	ldi ZL,100
	rcall DisplDecY1
	ldi ZL,10
	rcall DisplDecY1
	ldi rmp,'0'
	add rmp,R2
	st X+,rmp
	tst R1 ; fraction = 0?
	brne DisplFrac1
	ldi rmp,' '
	st X+,rmp
	ldi rmp,'H'
	st X+,rmp
	ldi rmp,'z'
	st X+,rmp

	ldi rmp,' '
	st X+,rmp
	st X+,rmp
	st X+,rmp
	st X+,rmp
	ret
DisplFrac1:
	ldi rmp,cDecSep
	st X+,rmp
	ldi ZL,3
DisplFrac2:
	clr rRes3
	clr rRes2
	mov R0,rRes1 ; * 1
	lsl rRes1 ; * 2
	adc rRes2,rRes3
	lsl rRes1 ; * 4
	rol rRes2
	add rRes1,R0 ; * 5
	adc rRes2,rRes3
	lsl rRes1 ; * 10
	rol rRes2
	ldi rmp,'0'
	add rmp,rRes2
	st X+,rmp
	dec ZL
	brne DisplFrac2

	ldi rmp,' '
	st X+,rmp
	ldi rmp,'H'
	st X+,rmp
	ldi rmp,'z'
	st X+,rmp
	ldi rmp,' '
	st X+,rmp
	ret
;
; Convert a decimal in R4:R3:R2, decimal in ZH:ZL
;
DisplDecY2:
	clr rDiv1 ; rDiv1 is counter
	clr rDiv2 ; overflow byte
DisplDecY2a:
	cp rRes2,ZL
	cpc rRes3,ZH
	cpc rRes4,rDiv2
	brcs DisplDecY2b ; ended
	sub rRes2,ZL ; subtract
	sbc rRes3,ZH
	sbc rRes4,rDiv2
	inc rDiv1
	rjmp DisplDecY2a
DisplDecY2b:
	ldi rmp,'0'
	add rmp,rDiv1
	add R0,rDiv1
	tst R0
	brne DisplDecY2c
	ldi rmp,' '
DisplDecY2c:
	st X+,rmp
	ret
;
; Convert a decimal decimal in R:R2, decimal in ZL
;
DisplDecY1:
	clr rDiv1 ; rDiv1 is counter
	clr rDiv2 ; overflow byte
DisplDecY1a:
	cp rRes2,ZL
	cpc rRes3,rDiv2
	brcs DisplDecY1b ; ended
	sub rRes2,ZL ; subtract
	sbc rRes3,rDiv2
	inc rDiv1
	rjmp DisplDecY1a
DisplDecY1b:
	ldi rmp,'0'
	add rmp,rDiv1
	add R0,rDiv1
	tst R0
	brne DisplDecY1c
	ldi rmp,' '
DisplDecY1c:
	st X+,rmp
	ret
;
; Display a 4-byte-binary in decimal format on result line 1
;   8-bit-display: "12345678"
;   16-bit-display: "  12.345.678 Hz "
;
Displ4Dec:
	ldi rmp,BYTE1(100000000) ; check overflow
	cp rRes1,rmp
	ldi rmp,BYTE2(100000000)
	cpc rRes2,rmp
	ldi rmp,BYTE3(100000000)
	cpc rRes3,rmp
	ldi rmp,BYTE4(100000000)
	cpc rRes4,rmp
	brcs Displ4Dec1
	rjmp CycleOvf
Displ4Dec1:
	clr R0 ; suppress leading zeroes
	ldi XL,LOW(s_video_mem)
	ldi XH,HIGH(s_video_mem) ; X to result buffer

	ldi rmp,' ' ; clear the first two digits
	st X+,rmp
	st X+,rmp

	ldi ZH,BYTE3(10000000) ; 10 mio
	ldi ZL,BYTE2(10000000)
	ldi rmp,BYTE1(10000000)
	rcall DisplDecX3
	ldi ZH,BYTE3(1000000) ; 1 mio
	ldi ZL,BYTE2(1000000)
	ldi rmp,BYTE1(1000000)
	rcall DisplDecX3

	ldi rmp,c1kSep ; set separator
	tst R0
	brne Displ4Dec2
	ldi rmp,' '
Displ4Dec2:
	st X+,rmp

	ldi ZH,BYTE3(100000) ; 100 k
	ldi ZL,BYTE2(100000)
	ldi rmp,BYTE1(100000)
	rcall DisplDecX3
	ldi ZL,LOW(10000)
	ldi ZH,HIGH(10000) ; 10 k	
	rcall DisplDecX2
	ldi ZL,LOW(1000)
	ldi ZH,HIGH(1000) ; 1 k
	rcall DisplDecX2

	ldi rmp,c1kSep ; set separator
	tst R0
	brne Displ4Dec3
	ldi rmp,' '
Displ4Dec3:
	st X+,rmp

	ldi ZL,100 ; 100
	rcall DisplDecX1
	ldi ZL,10
	rcall DisplDecX1
	ldi rmp,'0' ; 1
	add rmp,R1
	st X+,rmp
	ret
;
; Convert a decimal in R3:R2:R1, decimal in ZH:ZL:rmp
;
DisplDecX3:
	clr rDiv1 ; rDiv1 is counter
	clr rDiv2 ; subtractor for byte 4
DisplDecX3a:
	cp rRes1,rmp ; compare
	cpc rRes2,ZL
	cpc rRes3,ZH
	cpc rRes4,rDiv2
	brcs DisplDecX3b ; ended
	sub rRes1,rmp ; subtract
	sbc rRes2,ZL
	sbc rRes3,ZH
	sbc rRes4,rDiv2
	inc rDiv1
	rjmp DisplDecX3a
DisplDecX3b:
	ldi rmp,'0'
	add rmp,rDiv1
	add R0,rDiv1
	tst R0
	brne DisplDecX3c
	ldi rmp,' '
DisplDecX3c:
	st X+,rmp
	ret
;
; Convert a decimal in R3:R2:R1, decimal in ZH:ZL
;
DisplDecX2:
	clr rDiv1 ; rDiv1 is counter
	clr rDiv2 ; next byte overflow
DisplDecX2a:
	cp rRes1,ZL
	cpc rRes2,ZH
	cpc rRes3,rDiv2
	brcs DisplDecX2b ; ended
	sub rRes1,ZL ; subtract
	sbc rRes2,ZH
	sbc rRes3,rDiv2
	inc rDiv1
	rjmp DisplDecX2a
DisplDecX2b:
	ldi rmp,'0'
	add rmp,rDiv1
	add R0,rDiv1
	tst R0
	brne DisplDecX2c
	ldi rmp,' '
DisplDecX2c:
	st X+,rmp
	ret
;
; Convert a decimal in R2:R1, decimal in ZL
;
DisplDecX1:
	clr rDiv1 ; rDiv1 is counter
	clr rDiv2 ; next byte overflow
DisplDecX1a:
	cp rRes1,ZL
	cpc rRes2,rDiv2
	brcs DisplDecX1b ; ended
	sub rRes1,ZL ; subtract
	sbc rRes2,rDiv2
	inc rDiv1
	rjmp DisplDecX1a
DisplDecX1b:
	ldi rmp,'0'
	add rmp,rDiv1
	add R0,rDiv1
	tst R0
	brne DisplDecX1c
	ldi rmp,' '
DisplDecX1c:
	st X+,rmp
	ret
;
;=================================================
;             Delay routines
;=================================================
;
Delay50ms:
	ldi rDelH,HIGH(50000)
	ldi rDelL,LOW(50000)
	rjmp DelayZ
Delay10ms:
	ldi rDelH,HIGH(10000)
	ldi rDelL,LOW(10000)
	rjmp DelayZ
Delay15ms:
	ldi rDelH,HIGH(15000)
	ldi rDelL,LOW(15000)
	rjmp DelayZ
Delay4_1ms:
	ldi rDelH,HIGH(4100)
	ldi rDelL,LOW(4100)
	rjmp DelayZ
Delay1_64ms:
	ldi rDelH,HIGH(1640)
	ldi rDelL,LOW(1640)
	rjmp DelayZ
Delay100us:
	clr rDelH
	ldi rDelL,100
	rjmp DelayZ
Delay40us:
	clr rDelH
	ldi rDelL,40
	rjmp DelayZ
;
; Delays execution for Z microseconds
;
DelayZ:
.IF cFreq>18000000
	nop
	nop
.ENDIF
.IF cFreq>16000000
	nop
	nop
.ENDIF
.IF cFreq>14000000
	nop
	nop
.ENDIF
.IF cFreq>12000000
	nop
	nop
.ENDIF
.IF cFreq>10000000
	nop
	nop
.ENDIF
.IF cFreq>8000000
	nop
	nop
.ENDIF
.IF cFreq>6000000
	nop
	nop
.ENDIF
.IF cFreq>4000000
	nop
	nop
.ENDIF
	sbiw rDelL,1 ; 2
	brne DelayZ ; 2
	ret
;
; =========================================
; Main Program Start
; =========================================
;
main:
	ldi rmp,HIGH(RAMEND) ; set stack pointer
	out SPH,rmp
	ldi rmp,LOW(RAMEND)
	out SPL,rmp
	clr rFlg ; set flags to default
;
.IF debug
.EQU number = 100000000
	ldi rmp,BYTE4(number)
	mov rRes4,rmp
	mov rDiv4,rmp
	ldi rmp,BYTE3(number)
	mov rRes3,rmp
	mov rDiv3,rmp
	ldi rmp,BYTE2(number)
	mov rRes2,rmp
	mov rDiv2,rmp
	ldi rmp,BYTE1(number)
	mov rRes1,rmp
	mov rDiv1,rmp
	rcall CycleM6
beloop:	rjmp beloop
.ENDIF
.IF debugpulse
	.EQU nhigh = 100000000
	.EQU nlow = 15000
	ldi rmp,BYTE4(nhigh)
	sts sCtr+3,rmp
	ldi rmp,BYTE3(nhigh)
	sts sCtr+2,rmp
	ldi rmp,BYTE2(nhigh)
	sts sCtr+1,rmp
	ldi rmp,BYTE1(nhigh)
	sts sCtr,rmp
	ldi rmp,BYTE4(nlow)
	mov rRes4,rmp
	mov rDiv4,rmp
	ldi rmp,BYTE3(nlow)
	mov rRes3,rmp
	mov rDiv3,rmp
	ldi rmp,BYTE2(nlow)
	mov rRes2,rmp
	mov rDiv2,rmp
	ldi rmp,BYTE1(nlow)
	mov rRes1,rmp
	mov rDiv1,rmp
	sbr rFlg,1<<bEdge
	rcall CycleM7
bploop: 
	rjmp bploop
.ENDIF
;
; Clear the output storage
;
	ldi	ZL, LOW(s_video_mem)
	ldi	ZH, HIGH(s_video_mem)
	ldi	rmp, ' '
	mov	R0, rmp
	ldi	rmp, 32
main1:
	st	Z+,R0
	dec	rmp
	brne	main1
;
; Init the Uart
;
.IF cUart
	rcall UartInit
	ldi rmp,1<<bUMonU ; monitor U over Uart
	sts sUartFlag,rmp
	ldi rmp,20 ; 5 seconds
	sts sUartMonURpt,rmp ; set repeat default value
	ldi rmp,1
	sts sUartMonUCnt,rmp
	ldi rmp,4 ; 1 seconds
	sts sUartMonFCnt,rmp
.ENDIF
;
; Init the LCD
;
	rcall LcdInit
;
; Disable the Analog comparator
;
	ldi rmp,1<<ACD
	out ACSR,rmp
;
; Disable the external prescaler by 16
;
	sbi pPrescD, bPresc			; set prescaler port bit to output
	sbi pPresc, bPresc			; disable the prescaler
;

;
; Init encoder
;
	cbi DDRC, 0
	cbi DDRC, 1
	sbi PORTC, 0
	sbi PORTC, 1

	in	rmp, PINC
	andi	rmp, 3
	sts  sEncoderPrev, rmp

;
; Start main interval timer
;
	ldi	rmp, cCmp2				; set Compare Match
	out	OCR2, rmp
	ldi	rmp, cPre2|(1<<WGM21)		; CTC mode and prescaler
	out	TCCR2, rmp
;
; Start timer/counter TC2 interrupts
;
	ldi	rmp, (1<<OCIE2) 			; Interrupt mask
	out	TIMSK, rmp
;
; Set initial mode to mode 1
;
	ldi	rmp, 1 					; initial mode = 1
	sts	sModeNext, rmp
	rcall SetModeNext

	sei 							; enable interrupts
;
; --------[main loop] start --------------------
main_loop:
	sleep 								; send CPU to sleep
	nop
	; if meassure cycle ended then call Cycle()
	sbrc	rFlg, bCyc 						; check cycle end (bCyc - measure cycle ended)
	rcall Cycle							; calculate and display result
	; if adc conversation ended then call Interval
	rcall Interval
.IF cUart
	; if Uart line complete rhen can UartRxLine
	sbrc rFlg, bUartRxLine					; check line complete
	rcall UartRxLine						; call line complete
.ENDIF
	rjmp main_loop 						; go to sleep
; --------[main loop] end --------------------	
;
; Timer interval for calculation and display
;



Interval:
	lds	ZL, sEncoderPrev
	lsl	ZL
	lsl	ZL
	in	rmp, PINC
	andi	rmp, 3
	sts	sEncoderPrev, rmp
	or	ZL, rmp	; encoder value in ZL

	mov	ZH, rMode
	; 1 7 8 14 -> clockwise
	cpi	ZL, 1
	breq	Interval_enc_clockwise
	cpi	ZL, 7
	breq	Interval_enc_clockwise
	cpi	ZL, 8
	breq	Interval_enc_clockwise
	cpi	ZL, 14
	breq	Interval_enc_clockwise
	; 2 4 11 13 -> counterclockwise
	cpi	ZL, 2
	breq	Interval_enc_counterclockwise
	cpi	ZL, 4
	breq	Interval_enc_counterclockwise
	cpi	ZL, 11
	breq	Interval_enc_counterclockwise	
	cpi	ZL, 13
	breq	Interval_enc_counterclockwise	
	rjmp	Interval_noChanges
Interval_enc_clockwise:
	inc	ZH
	cpi	ZH, 9
	brcs	Interval_enc_done	; jump if ZH < 9
	ldi 	ZH, 8			; set to 9
	rjmp Interval_enc_done
Interval_enc_counterclockwise:
	tst  ZH
	breq Interval_enc_done	; jump if ZH = 0
	dec  ZH
Interval_enc_done:



	sts	sModeNext, ZH 			; store next mode
	cp	rMode, ZH				; new mode?
	breq Interval_noChanges		; continue current mode

	; delay for 100 ms duration
	cli
	rcall delay50ms
	rcall delay50ms
	in	rmp, PINC
	andi	rmp, 3
	sts  sEncoderPrev, rmp
	sei
	
	rcall SetModeNext ; start new mode
Interval_noChanges:


;.IF 0
;
;
;
;
;Interval:
;	lds	ZL, sEncoderPrev
;	lsl	ZL
;	lsl	ZL
;	in	rmp, PINC
;	andi	rmp, 3
;	sts	sEncoderPrev, rmp
;	or	ZL, rmp	; encoder value in ZL
;
;	mov	ZH, rMode
;	; 1 7 8 14 -> clockwise
;	cpi	ZL, 1
;	breq	Interval_enc_clockwise
;	cpi	ZL, 7
;	breq	Interval_enc_clockwise
;	cpi	ZL, 8
;	breq	Interval_enc_clockwise
;	cpi	ZL, 14
;	breq	Interval_enc_clockwise
;	; 2 4 11 13 -> counterclockwise
;	cpi	ZL, 2
;	breq	Interval_enc_counterclockwise
;	cpi	ZL, 4
;	breq	Interval_enc_counterclockwise
;	cpi	ZL, 11
;	breq	Interval_enc_counterclockwise	
;	cpi	ZL, 13
;	breq	Interval_enc_counterclockwise	
;	rjmp	Interval_enc_done
;Interval_enc_clockwise:
;	inc	ZH
;	cpi	ZH, 8
;	brcs	Interval_enc_done	; jump if ZH <= 8
;	ldi 	ZH, 8			; set to 8
;	rjmp Interval_enc_done
;Interval_enc_counterclockwise:
;	tst  ZH
;	breq Interval_enc_done	; jump if ZH = 0
;	dec  ZH
;Interval_enc_done:
;
;
;	sts	sModeNext, ZH 			; store next mode
;	cp	rMode, ZH				; new mode?
;	breq Interval_noChanges		; continue current mode
;	cli
;	rcall SetModeNext 		; start new mode
;
;	; delay for 100 ms duration
;
;	rcall delay50ms
;	rcall delay50ms
;	in	rmp, PINC
;	andi	rmp, 3
;	sts  sEncoderPrev, rmp
;	sei
;	
;;	rcall SetModeNext 		; start new mode
;Interval_noChanges:
;.ENDIF
;	rcall cAdc2U 			; convert to text
	rcall LcdDisplayFT
	rcall LcdDisplayU
	
.IF cUart
	rcall UartMonU
.ENDIF
	ret
;
; Frequency/Time measuring cycle ended, calculate results
;
Cycle:
	sbrc rFlg, bOvf ; check overflow
	rjmp CycleOvf ; jump to overflow
	mov rRes1, rCpy1 ; copy counter
	mov rRes2, rCpy2
	mov rRes3, rCpy3
	mov rRes4, rCpy4
	cbr rFlg, (1<<bCyc)|(1<<bOvf) ; clear cycle flag and overflow
	mov rDiv1, rRes1 ; copy again
	mov rDiv2, rRes2
	mov rDiv3, rRes3
	mov rDiv4, rRes4
.IF cUart
	ldi ZH, HIGH(UartMonF) ; put monitoring frequency on stack
	ldi ZL, LOW(UartMonF)
	push ZL
	push ZH
.ENDIF
; calculate and display result
	ldi ZH, HIGH(CycleTab) ; point to mode table
	ldi ZL, LOW(CycleTab)
	add ZL, rMode ; displace table by mode
	brcc Cycle1
	inc ZH
Cycle1:
	ijmp ; call the calculation routine
; overflow occurred
CycleOvf:
	cbr rFlg, (1<<bCyc)|(1<<bOvf) ; clear cycle flag and overflow
	ldi XL, LOW(s_video_mem)
	ldi XH, HIGH(s_video_mem) ; point to result buffer

	ldi ZL, LOW(2*TxtOvf16)
	ldi ZH, HIGH(2*TxtOvf16) ; point to long message
	ldi rmp,16

CycleOvf1:
	lpm
	adiw ZL,1
	st X+,R0
	dec rmp
	brne CycleOvf1
	ret
;
TxtOvf16:
	.DB "  overflow      "

; Table with routines for the 8 modes
CycleTab:
	rjmp CycleM0
	rjmp CycleM1
	rjmp CycleM2
	rjmp CycleM3
	rjmp CycleM4
	rjmp CycleM5
	rjmp CycleM6
	rjmp CycleM7
	rjmp CycleM8
	ret ; voltage only
;
; Mode 0: Measured prescaled frequency, display frequency
;
CycleM0:
	clr rDiv1 ; for detecting an overflow in R5

	lsl rRes1 ; * 2
	rol rRes2
	rol rRes3
	rol rRes4
	rol rDiv1
	
	lsl rRes1 ; * 4
	rol rRes2
	rol rRes3
	rol rRes4
	rol rDiv1
	
	lsl rRes1 ; * 8
	rol rRes2
	rol rRes3
	rol rRes4
	rol rDiv1
	
	lsl rRes1 ; * 16
	rol rRes2
	rol rRes3
	rol rRes4
	rol rDiv1
	
	lsl rRes1 ; * 32
	rol rRes2
	rol rRes3
	rol rRes4
	rol rDiv1
	
	lsl rRes1 ; * 64
	rol rRes2
	rol rRes3
	rol rRes4
	rol rDiv1
	
	tst rDiv1 ; check overflow
	breq CycleM0a ; no error
	rjmp CycleOvf

	
CycleM0a:
	rcall Displ4Dec
	ldi	rmp, ' '
	st	X+, rmp
	ldi	rmp, 'H'
	st	X+, rmp
	ldi	rmp, 'z'
	st	X+, rmp
	ldi	rmp, ' '
	st	X, rmp
	ldi	ZL, 'F'
	rjmp DisplMode
;
; Mode 1: Frequency measured, prescale = 1, display frequency
;
CycleM1:
	clr rDiv1 ; detect overflow in rDiv1
	
	lsl rRes1 ; * 2
	rol rRes2
	rol rRes3
	rol rRes4
	rol rDiv1
	
	lsl rRes1 ; * 4
	rol rRes2
	rol rRes3
	rol rRes4
	rol rDiv1
	
	tst rDiv1 ; check overflow
	breq CycleM1a ; no error
	rjmp CycleOvf
CycleM1a:
	rcall Displ4Dec
	ldi	rmp, ' '
	st	X+, rmp
	ldi	rmp, 'H'
	st	X+, rmp
	ldi	rmp, 'z'
	st	X+, rmp
	ldi	rmp, ' '
	st	X, rmp
	ldi	ZL, 'f'
	rjmp	DisplMode
;
; Mode 2: Time measured, prescale = 1, display frequency
;
CycleM2:
	rcall Divide
	tst rRes4
	brne CycleM2a
	rcall DisplFrac
	ldi ZL,'v'
	rcall DisplMode
	ret
CycleM2a:
	mov rRes1,rRes2 ; number too big, skip fraction
	mov rRes2,rRes3
	mov rRes3,rRes4
	clr rRes4
	rcall Displ4Dec
	ldi rmp,' '
	st X+,rmp
	ldi rmp,'H'
	st X+,rmp
	ldi rmp,'z'
	st X+,rmp
	ldi rmp,' '
	st X,rmp
	ldi ZL,'v'
	rcall DisplMode
	ret
;
; Measure time, display rounds per minute
;
CycleM3:
	rcall Divide
	clr R0 ; overflow detection
	clr rmp
	lsl rRes1 ; * 2
	rol rRes2
	rol rRes3
	rol rRes4
	adc R0,rmp
	lsl rRes1 ; * 4
	rol rRes2
	rol rRes3
	rol rRes4
	adc R0,rmp
	mov rDiv1,rRes1 ; copy
	mov rDiv2,rRes2
	mov rDiv3,rRes3
	mov rDiv4,rRes4
	lsl rRes1 ; * 8
	rol rRes2
	rol rRes3
	rol rRes4
	adc R0,rmp
	lsl rRes1 ; * 16
	rol rRes2
	rol rRes3
	rol rRes4
	adc R0,rmp
	lsl rRes1 ; * 32
	rol rRes2
	rol rRes3
	rol rRes4
	adc R0,rmp
	lsl rRes1 ; * 64
	rol rRes2
	rol rRes3
	rol rRes4
	adc R0,rmp
	tst R0 ; overflow?
	breq CycleM3a
	rjmp CycleOvf
CycleM3a:
	sub rRes1,rDiv1
	sbc rRes2,rDiv2
	sbc rRes3,rDiv3
	sbc rRes4,rDiv4
	mov rRes1,rRes2
	mov rRes2,rRes3
	mov rRes3,rRes4
	clr rRes4
	rcall Displ4Dec
	ldi rmp,' '
	st X+,rmp
	ldi rmp,'r'
	st X+,rmp
	ldi rmp,'p'
	st X+,rmp
	ldi rmp,'m'
	st X+,rmp

	ldi ZL,'u'
	rcall DisplMode
	ret
;
; Measure time high+low, display time
;
CycleM4:
	rcall Multiply
	rcall Displ4Dec
	rcall DisplSec
	ldi ZL,'t'
	rcall DisplMode
	ret
;
; Measure time high, display time
;
CycleM5:
	sbrs rFlg,bEdge
	rjmp CycleM5a
	rcall Multiply
	rcall Displ4Dec
	rcall DisplSec
	ldi ZL,'h'
	rcall DisplMode
CycleM5a:
	ret
;
; Measure time low, display time
;
CycleM6:
	sbrc rFlg,bEdge
	rjmp CycleM6a
	rcall Multiply
	rcall Displ4Dec
	rcall DisplSec
	ldi ZL,'l'
	rcall DisplMode
CycleM6a:
	ret
;
; Measure time high and low, display pulse width ratio high in %
;   if the edge was negative, store the measured time, if positive calculate
;   rRes and rDiv hold the active low time, sCtr the last active high time
;   to CalcPw: rDelH:rDelL:R0:rmp = active high time
;
CycleM7:
	sbrs rFlg,bEdge
	rjmp CycleM7a
	ldi ZL,LOW(sCtr)	; edge is high, calculate
	ldi ZH,HIGH(sCtr) 
	ld rRes1,Z+ ; copy counter value
	ld rRes2,Z+
	ld rRes3,Z+
	ld rRes4,Z+
	add rDiv1,rRes1 ; add to total time
	adc rDiv2,rRes2
	adc rDiv3,rRes3
	adc rDiv4,rRes4
	brcs CycleM7b
	mov rmp,rRes1 ; copy high value to divisor
	mov R0,rRes2
	mov rDelL,rRes3
	mov rDelH,rRes4
	rcall CalcPw ; calculate the ratio
	brcs CycleM7b ; error
	rcall DisplPw ; display the ratio
	ldi ZL,'P'
	rjmp DisplMode
CycleM7a:
	ldi ZL,LOW(sCtr)
	ldi ZH,HIGH(sCtr)
	st Z+,rRes1 ; copy counter value
	st Z+,rRes2
	st Z+,rRes3
	st Z+,rRes4
	ret
CycleM7b: ; overflow
	ldi rmp,'P'
	rjmp PulseOvFlw
;
; Measure time high and low, display pulse width ratio low in %
;   if the edge was negative, store the measured time, if positive calculate
;   rRes and rDiv hold the active low time, sCtr the last active high time
;   to CalcPw: rDelH:rDelL:R0:rmp = active low time
;
CycleM8:
	sbrs rFlg,bEdge
	rjmp CycleM8a
	ldi ZL,LOW(sCtr)
	ldi ZH,HIGH(sCtr) ; edge is high, calculate
	ld rmp,Z+ ; read high-time
	ld R0,Z+
	ld rDelL,Z+
	ld rDelH,Z
	add rDiv1,rmp ; add to total time
	adc rDiv2,R0
	adc rDiv3,rDelL
	adc rDiv4,rDelH
	mov rmp,rRes1 ; copy the active low time
	mov R0,rRes2
	mov rDelL,rRes3
	mov rDelH,rRes4
	rcall CalcPw ; calculate the ratio
	brcs CycleM8b ; error
	rcall DisplPw ; display the ratio
	ldi ZL,'p'
	rjmp DisplMode
CycleM8a:
	ldi ZL,LOW(sCtr)
	ldi ZH,HIGH(sCtr)
	st Z+,rRes1 ; copy counter value
	st Z+,rRes2
	st Z+,rRes3
	st Z+,rRes4
	ret
CycleM8b: ; overflow
	ldi	rmp, 'p'
	rjmp	PulseOvFlw
;
; Converts an ADC value in R1:R0 to a voltage for display
;   cAdc2U  input: ADC value, output: Voltage in V for display
;
cAdc2U:
;	ldi	XH, HIGH(s_video_mem+16)		; point to result
;	ldi	XL, LOW(s_video_mem+16)
;	ldi	rmp, ' '
;	st	X+, rmp
;	st	X+, rmp
;	st	X+, rmp
;	st	X+, rmp
;	st	X+, rmp
;	st	X+, rmp
	ret
;
;
;
;	clr	R2						; clear the registers for left shift in R3:R2
;	clr	R3
;	ldi	rmp, HIGH(cMultiplier)		; Multiplier to R5:R4
;	mov	R5, rmp
;	ldi	rmp, LOW(cMultiplier)
;	mov	R4, rmp
;	clr	XL						; clear result in ZH:ZL:XH:XL
;	clr	XH
;	clr	ZL
;	clr	ZH
;cAdc2U1:
;	lsr	R5 						; shift Multiplier right
;	ror	R4
;	brcc	cAdc2U2 					; bit is zero, don't add
;	add	XL, R0 					; add to result
;	adc	XH, R1
;	adc	ZL, R2
;	adc	ZH, R3
;cAdc2U2:
;	mov	rmp, R4 					; check zero
;	or	rmp, R5
;	breq cAdc2U3 					; end of multiplication
;	lsl	R0						; multiply by 2
;	rol	R1
;	rol	R2
;	rol	R3
;	rjmp cAdc2U1					; go on multipying
;cAdc2U3:
;	ldi	rmp, $80					; round up
;	add	XL, rmp
;	ldi	rmp, $00
;	adc	XH, rmp
;	adc	ZL, rmp
;	adc	ZH, rmp
;	tst	ZH						; check overflow
;	mov	R1, XH					; copy result to R2:R1
;	mov	R2, ZL
;	ldi	XH, HIGH(s_video_mem+16)		; point to result
;	ldi	XL, LOW(s_video_mem+16)
;	ldi	rmp, 'U'
;	st	X+, rmp
;	breq	cAdc2U5
;	ldi	ZH, HIGH(2*AdcErrTxt)
;	ldi	ZL, LOW(2*AdcErrTxt)
;cAdc2U4:
;	lpm
;	tst	R0
;	breq	cAdc2U6
;	sbiw	ZL, 1
;	st	X+,R0
;	rjmp	cAdc2U4
;cAdc2U5:
;	clr	R0
;	ldi	ZH, HIGH(10000)
;	ldi	ZL, LOW(10000)
;	rcall DecConv
;	inc	R0
;	ldi	ZH, HIGH(1000)
;	ldi	ZL, LOW(1000)
;	rcall DecConv
;	ldi	rmp, cDecSep
;	st	X+,rmp
;	clr	ZH
;	ldi	ZL,100
;	rcall DecConv
;	ldi	ZL,10
;	rcall DecConv
;	ldi	rmp,'0'
;	add	rmp,R1
;	st	X+, rmp
;	ldi	rmp,'V'
;	st	X,rmp
;	lds	rmp, s_video_mem+17
;	cpi	rmp, ' '
;	brne cAdc2U6
;	ldi	rmp, '='
;	sts	s_video_mem+17, rmp
;cAdc2U6:
;	ret
;
;AdcErrTxt:
;	.DB	"overflw", $00
;
; ===========================================
; Lcd display routines
; ===========================================
;
;
; LcdE pulses the E output for at least 1 us
;
LcdE:
	sbi PORTB,bLcdE
	.IF cFreq>14000000
		nop
		nop
	.ENDIF
	.IF cFreq>12000000
		nop
		nop
	.ENDIF
	.IF cFreq>10000000
		nop
		nop
	.ENDIF
	.IF cFreq>8000000
		nop
		nop
	.ENDIF
	.IF cFreq>6000000
		nop
		nop
	.ENDIF
	.IF cFreq>4000000
		nop
		nop
	.ENDIF
	.IF cFreq>2000000
		nop
		nop
	.ENDIF
	nop
	nop
	cbi PORTB,bLcdE
	ret
;
; outputs the content of rmp (temporary
; 8-Bit-Interface during startup)
;
LcdRs8:
	out PORTB,rmp
	rcall LcdE
	ret
;
; write rmp as 4-bit-command to the LCD
;
LcdRs4:
	mov R0,rmp ; copy rmp
	swap rmp ; upper nibble to lower nibble
	andi rmp,0x0F ; clear upper nibble
	out PORTB,rmp ; write to display interface
	rcall LcdE ; pulse E
	mov rmp,R0 ; copy original back
	andi rmp,0x0F ; clear upper nibble
	out PORTB,rmp ; write to display interface
	rcall LcdE
	mov rmp,R0 ; restore rmp
	ret
;
; write rmp as data over 4-bit-interface to the LCD
;
LcdData4:
	push rmp ; save rmp
	mov rmp,R0 ; copy rmp
	swap rmp ; upper nibble to lower nibble
	andi rmp,0x0F ; clear upper nibble
	sbr rmp,1<<bLcdRs ; set Rs to one
	out PORTB,rmp ; write to display interface
	rcall LcdE ; pulse E
	mov rmp,R0 ; copy original again
	andi rmp,0x0F ; clear upper nibble
	sbr rmp,1<<bLcdRs ; set Rs to one
	out PORTB,rmp ; write to display interface
	rcall LcdE
	rcall Delay40us
	pop rmp ; restore rmp
	ret
;
; writes the text in flash to the LCD, number of
; characters in rmp
;
LcdText:
	lpm						; read character from flash
	adiw		ZL, 1
	rcall	LcdData4 			; write to 
	rcall	delay40us
	dec		rmp
	brne		LcdText
	ret
;
; Inits the LCD with a 4-bit-interface
;
LcdInit:
	ldi rmp,0x0F | (1<<bLcdE) | (1<<bLcdRs)
	out DDRB,rmp
	clr rmp
	out PORTB,rmp
	rcall delay15ms ; wait for complete self-init
	ldi rmp,0x03 ; Function set 8-bit interface
	rcall LcdRs8
	rcall delay4_1ms ; wait for 4.1 ms
	ldi rmp,0x03 ; Function set 8-bit interface
	rcall LcdRs8
	rcall delay100us ; wait for 100 us
	ldi rmp,0x03 ; Function set 8-bit interface
	rcall LcdRs8
	rcall delay40us ; delay 40 us
	ldi rmp,0x02 ; Function set 4-bit-interface
	rcall LcdRs8
	rcall delay40us
	ldi rmp,0x28 ; 4-bit-interface, two line display
	rcall LcdRs4
	rcall delay40us ; delay 40 us
	ldi rmp,0x08 ; display off
	rcall LcdRs4
	rcall delay40us ; delay 40 us
	ldi rmp,0x01 ; display clear
	rcall LcdRs4
	rcall delay1_64ms ; delay 1.64 ms
	ldi rmp,0x06 ; increment, don't shift
	rcall LcdRs4
	rcall delay40us ; delay 40 us
	ldi rmp,0x0C ; display on
	rcall LcdRs4
	rcall delay40us
	ldi rmp,0x80 ; position on line 1
	rcall LcdRs4
	rcall delay40us ; delay 40 us
	ldi rmp,16
	ldi ZL,LOW(2*LcdInitTxt16)
	ldi ZH,HIGH(2*LcdInitTxt16)
	rcall LcdText

	;;; !!! TODO memove --------------[
;	ldi	rmp, 0xC0 ; line 2
;	rcall LcdRs4
;	rcall delay40us ; delay 40 us
;	ldi	XH, HIGH(s_video_mem+25)
;	ldi	XL, LOW(s_video_mem+25)
;	ldi	ZH, HIGH(2*LcdInitTxtMode)
;	ldi	ZL, LOW(2*LcdInitTxtMode)
;	ldi	rmp, 6					; len(" Mode=") = 6
;LcdInitMode:
;	lpm
;	adiw	ZL, 1
;	st	X+, R0
;	dec	rmp
;	brne LcdInitMode
;	ldi	rmp,16
;	rcall LcdText
	;;;; ]------------------------
	
	ret
LcdInitTxt16:
	.DB "Freq-counter V01"
	.DB " (C)2005 DG4FAC "
;LcdInitTxtMode:
;	.DB " Mode="
;
; Display frequency/time on Lcd
;
LcdDisplayFT:
	ldi	rmp, $80				; set display position to line 1
	rcall LcdRs4
	rcall Delay40us
	ldi	ZL, LOW(s_video_mem)
	ldi	ZH, HIGH(s_video_mem)		; point Z to line buffer
	ldi	rmp, 16

LcdDisplayFT1:
	ld	R0, Z+				; read a char
	rcall LcdData4				; display on LCD
	dec	rmp
	brne	LcdDisplayFT1
LcdDisplayFT2:
	ret
;
; Display voltage on the display
;
LcdDisplayU:
;	lds	rmp, sModeNext
;	subi	rmp, -'0'
;	sts	s_video_mem+31, rmp

	ldi	rmp, $C0 					; output to line 2

	rcall LcdRs4 ; set output position
	rcall Delay40us
	ldi ZL,LOW(s_video_mem+16)
	ldi ZH,HIGH(s_video_mem+16) ; point to result
	ldi rmp, 16
LcdDisplayU1:
	ld	R0, Z+		; read character


	; display second line
	; TODO !!!

	
	rcall LcdData4			; write r0 as data over 4-bit-interface to the LCD
	dec	rmp 				; next char
	brne LcdDisplayU1 		; continue with chars
LcdDisplayU2:
	ret
;


;
; ===========================================
;   Uart routines
; ===========================================
;
.IF cUart
UartInit: ; Init the Uart on startup
.EQU cUbrr = (cFreq/cBaud/16)-1 ; calculating UBRR single speed
	ldi rmp,LOW(sUartRxBs) ; set buffer pointer to start
	sts sUartRxBp,rmp
	ldi rmp,HIGH(cUbrr) ; set URSEL to zero, set baudrate msb
	out UBRRH,rmp
	ldi rmp,LOW(cUbrr) ; set baudrate lsb
	out UBRRL,rmp
	ldi rmp,(1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0) ; set 8 bit characters
	out UCSRC,rmp
	ldi rmp,(1<<RXCIE)|(1<<RXEN)|(1<<TXEN) ; enable RX/TX and RX-Ints
	out UCSRB,rmp
	rcall delay10ms ; delay for 10 ms duration
	ldi ZH,HIGH(2*txtUartInit)
	ldi ZL,LOW(2*txtUartInit)
	rjmp UartSendTxt
;
; Uart receive buffer space in SRAM
;   sUartRxBs is buffer start
;   sUartRxBe is buffer end
;   sUartRxBp is buffer input position
;	.EQU UartRxbLen = 38 ; Buffer length in bytes
;	sUartFlag: ; flag register for Uart
;		.BYTE 1
;		.EQU bUMonU = 0 ; displays voltage over Uart
;		.EQU bUMonF = 1 ; displays frequency over Uart
;		; free: bits 2..7
;	sUartMonUCnt: ; counter for Monitoring voltage
;		.BYTE 1
;	sUartMonURpt: ; counter preset for monitoring voltage
;		.BYTE 1
;	sUartRxBp: ; buffer pointer
;		.BYTE 1
;	sUartRxBs: ; buffer
;		.BYTE UartRxbLen
;	sUartRxBe: ; buffer end
;	.EQU cNul = $00
;	.EQU cClrScr = $0C
;	.EQU cCR = $0D
;	.EQU cLF = $0A
;
UartRxLine:
	cbr rFlg,1<<bUartRxLine ; clear line complete flag
	ldi rmp,LOW(sUartRxBs) ; set buffer pointer to start
	sts sUartRxBp,rmp
	ldi ZL,LOW(UartReturn)
	ldi ZH,HIGH(UartReturn) ; push return adress to stack	
	push ZL
	push ZH
	ldi ZL,LOW(sUartRxBs)
	ldi ZH,HIGH(sUartRxBs) ; set Z to Buffer-Start
	ld rmp,Z+ ; read first character
	cpi rmp,'h' ; help?
	brne UartRxLine1
	rjmp UartHelp
UartRxLine1:
	cpi rmp,'?' ; help?
	brne UartRxLine2
	rjmp UartHelp
UartRxLine2:
	cpi rmp,'U' ; monitor U on
	brne UartRxLine3
	rcall UartGetPar
	sec
	rjmp UartMonUSetC
UartRxLine3:
	cpi rmp,'u' ; monitor U off
	brne UartRxLine4
	clc
	rjmp UartMonUSetC
UartRxLine4:
	cpi rmp,'F' ; monitor F on
	brne UartRxLine5
	rcall UartGetPar
	sec
	rjmp UartMonFSetC
UartRxLine5:
	cpi rmp,'f' ; monitor f off
	brne UartRxLine6
	clc
	rjmp UartMonFSetC
UartRxLine6:
	cpi rmp,'p' ; parameter?
	brne UartRxLine7
	rjmp UartMonPar
UartRxLine7:
	ldi ZL,LOW(2*txtUartUnknown)
	ldi ZH,HIGH(2*txtUartUnknown) ; send unknown command
	ret
UartHelp:
	ldi ZL,LOW(2*txtUartHelp)
	ldi ZH,HIGH(2*txtUartHelp) ; send help text
	ret
UartMonUSetC:
	lds rmp,sUartFlag
	brcs UartMonUSetC1
	cbr rmp,1<<bUMonU ; clear flag
	sts sUartFlag,rmp
	ldi ZL,LOW(2*txtUartUOff)
	ldi ZH,HIGH(2*txtUartUOff)
	ret
UartMonUSetC1:
	brne UartMonUSetC2
	sts sUartMonURpt,R0
	sts sUartMonUCnt,R0
UartMonUSetC2:
	sbr rmp,1<<bUMonU ; set flag
	sts sUartFlag,rmp
	ldi ZL,LOW(2*txtUartUOn)
	ldi ZH,HIGH(2*txtUartUOn)
	ret
UartMonFSetC:
	lds rmp,sUartFlag
	brcs UartMonFSetC1
	cbr rmp,1<<bUMonF ; clear flag
	sts sUartFlag,rmp
	ldi ZL,LOW(2*txtUartFOff)
	ldi ZH,HIGH(2*txtUartFOff)
	ret
UartMonFSetC1:
	brne UartMonFSetC2
	sts sUartMonFRpt,R0
	sts sUartMonFCnt,R0
UartMonFSetC2:
	sbr rmp,1<<bUMonF ; set flag
	sts sUartFlag,rmp
	ldi ZL,LOW(2*txtUartFOn)
	ldi ZH,HIGH(2*txtUartFOn)
	ret
UartMonPar:
	ldi ZL,LOW(2*txtUartNul);
	ldi ZH,HIGH(2*txtUartNul)
	ldi rmp,'U'
	rcall UartSendChar
	ldi rmp,'='
	rcall UartSendChar
	ldi rmp,'$'
	rcall UartSendChar
	lds rmp,sUartMonURpt
	rcall UartHexR
	ldi rmp,','
	rcall UartSendChar
	ldi rmp,' '
	rcall UartSendChar
	ldi rmp,'F'
	rcall UartSendChar
	ldi rmp,'='
	rcall UartSendChar
	ldi rmp,'$'
	rcall UartSendChar
	lds rmp,sUartMonFRpt
	rjmp UartHexR
;
; Get Parameter from line
;
UartGetPar:
	clr R0 ; result register
	ld rmp,Z+ ; read char
	cpi rmp,cCr ; carriage return
	breq UartGetParNoPar
	cpi rmp,cLf ; line feed
	breq UartGetParNoPar
	cpi rmp,'=' ;
	brne UartGetParErr
UartGetPar1:
	ld rmp,Z+ ; read next char
	cpi rmp,cCr ; carriage return?
	breq UartGetPar2
	cpi rmp,cLf ; line feed?
	breq UartGetPar2
	subi rmp,'0' ; subtract 0
	brcs UartGetParErr
	cpi rmp,10 ; larger than 9?
	brcc UartGetParErr
	mov rir,R0 ; copy to rir
	lsl R0 ; * 2
	brcs UartGetParErr
	lsl R0 ; * 4
	brcs UartGetParErr
	add R0,rir ; * 5
	brcs UartGetParErr
	lsl R0 ; * 10
	brcs UartGetParErr
	add R0,rmp ; add new decimal
	brcs UartGetParErr
	rjmp UartGetPar1
UartGetPar2:
	sez
	ret
UartGetParErr:
	ldi ZL,LOW(2*txtUartErr)
	ldi ZH,HIGH(2*txtUartErr)
	rcall UartSendTxt
UartGetParNoPar:
	clz ; No parameter set
	ret
;
; Hex output over Uart, for debugging
;
UartHexR:
	push rmp
	swap rmp
	rcall UartHexN
	pop rmp
UartHexN:
	andi rmp,0x0F
	subi rmp,-'0'
	cpi rmp,'9'+1
	brcs UartHexN1
	subi rmp,-7
UartHexN1:
	rjmp UartSendChar
	ret 
;
; Return from Uart-Routines, displays text in Z
;
UartReturn:
	rcall UartSendTxt ; send text in Z
	ldi ZL,LOW(2*txtUartCursor)
	ldi ZH,HIGH(2*txtUartCursor)
	rjmp UartSendTxt
;
; Send character in rmp over Uart
;
UartSendChar:
	sbis UCSRA,UDRE ; wait for empty buffer
	rjmp UartSendChar
	out UDR,rmp
	ret
;
; Monitoring the voltage over the Uart
;
UartMonU:
	lds rmp,sUartFlag ; flag register for Uart
	sbrs rmp,bUMonU ; displays voltage over Uart
	ret
	lds rmp,sUartMonUCnt ; read counter
	dec rmp
	sts sUartMonUCnt,rmp
	brne UartMonU2
	lds rmp,sUartMonURpt
	sts sUartMonUCnt,rmp
	ldi ZL,LOW(s_video_mem+16)
	ldi ZH,HIGH(s_video_mem+16)
	ldi rmp,8
UartMonU1:
	sbis UCSRA,UDRE ; wait for empty buffer
	rjmp UartMonU1
	ld R0,Z+
	out UDR,R0
	dec rmp
	brne UartMonU1
	ldi rmp,cCr
	rcall UartSendChar
	ldi rmp,cLf
	rjmp UartSendChar
UartMonU2:
	ret
;
; Monitor frequency over UART
;
UartMonF:
	lds rmp,sUartFlag ; flag register for Uart
	sbrs rmp,bUMonF ; displays frequency over Uart
	ret
	lds rmp,sUartMonFCnt ; read counter
	dec rmp
	sts sUartMonFCnt,rmp
	brne UartMonF2
	lds rmp,sUartMonFRpt
	sts sUartMonFCnt,rmp
	ldi ZL,LOW(s_video_mem)
	ldi ZH,HIGH(s_video_mem)
	ldi rmp,16
UartMonF1:
	sbis UCSRA,UDRE ; wait for empty buffer
	rjmp UartMonF1
	ld R0,Z+
	out UDR,R0
	dec rmp
	brne UartMonF1
	ldi rmp,cCr
	rcall UartSendChar
	ldi rmp,cLf
	rjmp UartSendChar
UartMonF2:
	ret
;
; Send text from flash to UART, null byte ends transmit
;
UartSendTxt:
	lpm ; read character from flash
	adiw ZL,1
	tst R0 ; check end of text
	breq UartSendTxtRet
UartSendTxtWait:
	sbis UCSRA,UDRE ; wait for empty char
	rjmp UartSendTxtWait
	out UDR,R0 ; send char
	rjmp UartSendTxt
UartSendTxtRet:
	ret
;
; Uart text constants
;
txtUartInit:
.DB " ", cClrScr
.DB "************************************************* ",cCr,cLf
.DB "* Frequency- and voltmeter (C)2005 by g.schmidt * ",cCr,cLf
.DB "************************************************* ",cCr,cLf
txtUartMenue:
	.DB cCR, cLF, "Commands: <h>elp", cCR, cLF
txtUartCursor:
	.DB cCR, cLF, "i> ", cNul
txtUartUnknown:
	.DB cCR, cLF, "Unknown command!", cNul, cNul
txtUartUOff:
	.DB "Voltage monitoring is off.", cNul, cNul
txtUartUOn:
	.DB "Voltage monitoring is on. ", cNul, cNul
txtUartFOff:
	.DB "Frequency monitoring is off.", cNul, cNul
txtUartFOn:
	.DB "Frequency monitoring is on. ", cNul, cNul
txtUartErr:
	.DB "Error in parameter! ", cNul, cNul
txtUartHelp:
	.DB cCR, cLF, "Help: ", cCR, cLF
	.DB "U[=N](on) or u(Off): monitor voltage output, N=1..255,", cCR, cLF
	.DB "F[=N](On) or f(Off): monitor frequency output N=1..255, ", cCR, cLF
	.DB "p: display monitoring parameters, ", cCR, cLF
	.DB "h or ?: this text."
txtUartNul:
	.DB cNul, cNul
.ENDIF
;
; End of source code
;
