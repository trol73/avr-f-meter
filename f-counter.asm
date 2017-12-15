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
	.EQU cCR = 0x0D
	.EQU cLF = 0x0A
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

.extern DisplDecY1 (val: ZL)
.extern LcdText (len: r16)

.extern s_video_mem : ptr
.extern sCtr : ptr
.extern sUartRxBs : ptr
.extern sEncoderPrev, sModeNext, sUartMonFCnt, sUartFlag, sUartMonFRpt, sUartMonURpt, sUartMonUCnt, sUartRxBp : byte

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
	rCpy3 = rCtr2 			; 6, copy the counter bytes
	rCpy4 = rCtr3 			; 7
	sbr	rFlg, 1<<bCyc 		; 8, set cycle end flag bit
	cbr	rFlg, 1<<bEdge 	; 9, set falling edge
	sbic	PIND, 2 			; 10/11, check if input = 0
	sbr	rFlg, 1<<bEdge 	; 11, no, set edge flag to rising
Int0Int1: 				; 4/11
	ldi	rimp, 0 			; 5/12, reset the timer
	out	TCNT1H, rimp 		; 6/13, set TC1 zero to restart
	out	TCNT1L, rimp 		; 7/14
	rCtr1 =  rimp 			; 8/15, clear the upper bytes
	rCtr2 = rimp 			; 9/16
	rCtr3 = rimp 			; 10/17
	out	SREG, rSreg 		; 11/18, restore SREG
	reti 				; 15/22
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
	rCpy2 = rCtr1			; 5, copy counter bytes to result
	rCpy3 = rCtr2 			; 6
	rCpy4 = rCtr3 			; 7
	sbr	rFlg, 1<<bCyc 		; 8, set cycle end flag bit
Tc1CmpAInt1: 				; 4/8
	ldi	rimp, 0 			; 5/9, clear counter
	out	TCNT0, rimp 		; 6/10
	rCtr1 = rimp 			; 7/11, clear counter bytes
	rCtr2 = rimp 			; 8/12
	rCtr3 = rimp 			; 9/13
	out	SREG, rSreg 		; 10/14, restore SREG
	reti ; 			14/18
;
; TC1 Overflow Interrupt Service Routine
;   active in modes 2 to 6 counting clock cycles to measure time
;   increases the upper bytes and detects overflows
;
Tc1OvfInt:
	in	rSreg, SREG 			; 1, save SREG
	rCtr2 ++					; 2, increase byte 3 of the counter
	brne	Tc1OvfInt1 			; 3/4, no overflow
	rCtr3++					; 4, increase byte 4 of the counter
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
	rCtr1 ++		 			; 2, increase byte 2 of the counter
	brne	Tc0OvfInt1 			; 3/4, no overflow
	rCtr2 ++	 				; 4, increase byte 3 of the counter
	brne	Tc0OvfInt1 			; 5/6, no overflow
	rCtr3 ++					; 6, increase byte 4 of the counter
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
	rimp =  '*'						; 6, signal an error
	out	UDR, rimp						; 7
	rjmp	SioRxCIsr4 					; 9, return from int
SioRxCIsr1: 							; 6
	out	UDR, rimp						; 7, echo the character
	push	ZH ZL 						; 9, 11, Save Z register
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
	pop	ZL ZH						; 24/25/26/27, 26/27/28/29, restore Z-register
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
	rmp =  0xC0 ; line 2
	rcall LcdRs4
	rcall delay40us ; delay 40 us
	Z = MODE_0

	rmp = rMode
	; rmp *= 16
	; rmp <<= 4
	lsl	rmp
	lsl	rmp
	lsl	rmp
	lsl	rmp						; mode * 16

	XL = 0
	Z += XL.rmp
	rmp = 16					; length
	X = s_video_mem + 16
	
LcdInitMode:
	.loop (rmp)
		lpm
		Z++
		st	X+, R0
	.endloop
	rcall LcdText (len: 16)
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
	rmp = sModeNext 		; read next mode
	rMode = rmp
	rcall	SetModeName

	rmp = sModeNext 		; read next mode
	rMode = rmp

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
	rmp = 0xFF 		; disable the compare match B
	out	OCR1BH, rmp
	out	OCR1BL, rmp
	ldi	rmp, 0 			; CTC mode
	out	TCCR1A, rmp
	ldi	rmp, cPre1F 		; set the prescaler value for TC1
	out	TCCR1B, rmp
	rmp = (1<<CS02)|(1<<CS01)|(1<<CS00) 	; count rising edges on T0
	out	TCCR0, rmp
	rmp = (1<<OCIE2)|(1<<OCIE1A)|(1<<TOIE0) ; enable TC2Cmp, TC1CmpAInt and TC0OverflowInt
	out	TIMSK, rmp
	ret
;
; Set timer/counter mode to time measurement
;
SetModeT:
	sbi	pPresc, bPresc 				; disable prescaler
	ldi	rmp, 0 						; timing mode
	out	TCCR1A, rmp
	rmp = 1<<CS10 					; count with prescaler = 1
	out	TCCR1B, rmp
	rmp = (1<<SE)|(1<<ISC01)|(1<<ISC00)	; sleep enable, positive edges on INT0 interrupt
	out	MCUCR, rmp
	rmp = 1<<INT0					; enable INT0 interrupt
	out	GICR, rmp
	rmp = (1<<OCIE2)|(1<<TOIE1)		; enable TC2Cmp, TC1Ovflw
	out	TIMSK, rmp
	ret
;
; Set timer/counter mode to time measurement, all edges
;
SetModeE:
	sbi pPresc, bPresc ; disable prescaler
	ldi rmp, 0 ; timing mode
	out TCCR1A,rmp
	rmp = 1<<CS10 ; count with prescaler = 1
	out TCCR1B,rmp
	rmp = (1<<SE)|(1<<ISC00) ; sleep enable, any logical change on INT0 interrupts
	out MCUCR,rmp
	rmp = 1<<INT0 ; enable INT0 interrupt
	out GICR,rmp
	rmp = (1<<OCIE2)|(1<<TOIE1) ; enable TC2Cmp, TC1Ovflw
	out TIMSK,rmp
	ret
;
;
; clears the timers and resets the upper bytes
;
ClrTc:
	rmp = 0 					; disable INT0
	out	GICR, rmp
	rmp = 0					; TODO !!! stop the counters/timers
	out	TCCR0, rmp 			; stop TC0 counting/timing
	out	TCCR1B, rmp			; stop TC1 counting/timing
	out	TCNT0, rmp			; clear TC0
	out	TCNT1L, rmp			; clear TC1
	out	TCNT1H, rmp
	rCtr1 = 0				; clear upper bytes
	rCtr2 = 0
	rCtr3 = 0
	rmp = 1<<OCIE2			; enable only output compare of TC2 ints
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
.proc Divide
	rmp = 0 ; rmp:R0:ZH:ZL:XH:XL is divisor
	R0 = 0
	ZH = 0
	ZL = BYTE3(cFreq/256) ; set divisor
	XH = BYTE2(cFreq/256)
	XL = BYTE1(cFreq/256)
	rRes1 = 0 ; set result
	rRes1++
	rRes2 = 0
	rRes3 = 0
	rRes4 = 0
@1:
	; rmp.r0.ZH.ZL.XH.XL *= 2
	; rmp.r0.ZH.ZL.XH.XL <<= 1
	lsl XL ; multiply divisor by 2
	rol XH
	rol ZL
	rol ZH
	rol R0
	rol rmp
	if (rmp.r0.ZH.ZL < rDiv4.rDiv3.rDiv2.rDiv1) goto @2		; compare with divident
	rmp.r0.ZH.ZL -= rDiv4.rDiv3.rDiv2.rDiv1
	sec
	rjmp @3
@2:
	clc
@3:
	rol rRes1
	rol rRes2
	rol rRes3
	rol rRes4
	brcc @1
	ret
.endproc	
;
; Multiply measured time in rRes4:rRes3:rRes2:rRes1 by 65536 / fq(MHz)
;   rmp:R0 are the upper bytes of the input
;   ZH:ZL:rDiv4:rDiv3:rDiv2:rDiv1 is the interim result
;   XH:XL is the multiplicator
;   result is in rRes4:rRes3:rRes2:rRes1
;
.equ cMulti = 65536000 / (cFreq/1000)
;
.proc Multiply
	;X = cMulti
	ldi XH,HIGH(cMulti) ; set multiplicator
	ldi XL,LOW(cMulti)
	ZH = 0
	ZL = 0
	rDiv4 = 0
	rDiv3 = 0
	rDiv2 = 0
	rDiv1 = 0
	r0 = 0
	rmp = 0
@1:
	;if (XL != 0) goto @2
	cpi XL, 0
	brne @2
	cpi XH, 0
	breq @4
@2:
	; XL.XH >>= 1
	lsr XH
	ror XL
	brcc @3
	ZH.ZL.rDiv4.rDiv3.rDiv2.rDiv1 += rmp.r0.rRes4.rRes3.rRes2.rRes1
@3:
	; rmp.r0.rRes4.rRes3.rRes2.rRes1 <<= 1
	lsl rRes1
	rol rRes2
	rol rRes3
	rol rRes4
	rol R0
	rol rmp
	rjmp @1
@4:
	rmp = 128 ; round result
	R0 = 0
	ZH.ZL.rDiv4.rDiv3.rDiv2 += r0.r0.r0.r0.rmp
	rRes4.rRes3.rRes2.rRes1 = ZH.ZL.rDiv4.rDiv3
	ret
.endproc
	
;
; Display seconds at buffer end
;
DisplSec:
	rmp = ' '
	st	X+, rmp
	rmp = 'u'
	st	X+, rmp
	rmp = 's'
	st	X+, rmp
	rmp = ' '
	st	X, rmp
	ret
;
; An overflow has occurred during pulse width calculation
;

.proc PulseOvflw
	;.extern TxtPOvflw16 : prgptr
	X = s_video_mem
	st	X+, rmp

	;Z = TxtPOvflw16
	ldi	ZL, LOW(2*TxtPOvflw16)
	ldi	ZH, HIGH(2*TxtPOvflw16)
	.loop (rmp = 15)
		lpm
		Z++
		st	X+, R0
	.endloop
	ret
TxtPOvflw16:
	.DB ":error calcul.! "
.endproc	
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
.proc CalcPw
	rRes1 = rmp ; copy active cycle time to rRes
	rRes2 = R0
	rRes3 = rDelL
	rRes4 = rDelH
	; rRes4.rRes3.rRes2.rRes1
	lsl rRes1 ; * 2
	rol rRes2
	rol rRes3
	rol rRes4
	brcs CalcPwO ; overflow
	; rRes4.rRes3.rRes2.rRes1
	lsl rRes1 ; * 4
	rol rRes2
	rol rRes3
	rol rRes4
	brcs CalcPwO ; overflow
	; rRes4.rRes3.rRes2.rRes1
	lsl rRes1 ; * 8
	rol rRes2
	rol rRes3
	rol rRes4
	brcs CalcPwO ; overflow
	X = rRes2.rRes1
	Z = rRes4.rRes3
	; rRes4.rRes3.rRes2.rRes1
	lsl rRes1 ; * 16 <<= 1
	rol rRes2
	rol rRes3
	rol rRes4
	brcs CalcPwO
	rRes4.rRes3.rRes2.rRes1 += ZH.ZL.XH.XL		; * 24
	ZH = 0 ; clear the four MSBs of divisor
	ZL = 0
	XH = 0
	XL = rDelH ; * 256
	rDelH = rDelL
	rDelL = R0
	R0 = rmp
	rmp = 0
	
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
	XH.XL.rDelH.rDelL.r0.rmp -= ZH.ZH.rRes4.rRes3.rRes2.rRes1		; * 1000
	if (ZH.ZL.XH.XL >= rDiv4.rDiv3.rDiv2.rDiv1) goto CalcPwO		; overflow?
	rRes1 = 0 ; clear result
	rRes1++
	rRes2 = 0
	rRes3 = 0
	rRes4 = 0
@1: ; dividing loop
	; ZH.ZL.XH.XL.rDelH.rDelL.r0.rmp <<= 1
	lsl rmp ; multiply by 2
	rol R0
	rol rDelL
	rol rDelH
	rol XL
	rol XH
	rol ZL
	rol ZH
	if (ZH.ZL.XH.XL < rDiv4.rDiv3.rDiv2.rDiv1) goto @2 ; smaller, roll zero in
	ZH.ZL.XH.XL -= rDiv4.rDiv3.rDiv2.rDiv1				 ; subtract divisor
	sec ; roll one in
	rjmp @3
@2:
	clc
@3: ; roll result
	rol rRes1
	rol rRes2
	rol rRes3
	rol rRes4
	brcc @1 ; roll on
	lsl rDelL ; round result
	rol XL
	rol XH
	rol ZL
	rol ZH
	if (ZH.ZL.XH.XL < rDiv4.rDiv3.rDiv2.rDiv1) goto @4
	rmp = 1 ; round up
	add rRes1,rmp
	ldi rmp,0
	adc rRes2,rmp
	adc rRes3,rmp
	adc rRes4,rmp
@4:
	if (rRes4 != 0) goto @E
	if (rRes3 != 0) goto @E
	ldi rmp,LOW(1001)
	cp rRes1,rmp
	ldi rmp,HIGH(1001)
	cpc rRes2,rmp
	brcc @E
	clc ; no error
	ret
@E: ; error
	sec
	ret
.endproc
;
; Display the binary in R2:R1 in the form "  100,0%"
;
DisplPw:
	X = s_video_mem
	rmp = ' '
	st	X+, rmp
	st	X+, rmp
	R0 = 0
	Z = 1000
	rcall DisplDecX2
	Z = 100
	rcall	DisplDecX2
	ZL = 10
	R0++
	rcall DisplDecX2
	ldi	rmp, cDecSep
	st	X+, rmp
	rmp = '0' + rRes1
	st	X+, rmp
	rmp = '%'
	st	X+, rmp
	ZL = ' '
	.loop (rmp = 8)
		st	X+, ZL
	.endloop
	ret
;
; If the first characters in the result buffer are empty,
;   place the character in ZL here and add equal, if possible
;
.proc DisplMode
.args val(ZL)
	X = s_video_mem+1
	ld	rmp, X 							; read second char
	if (rmp != ' ') goto @1
	rmp = '='
	st	X, rmp
@1:
	X--
	ld	rmp, X 							; read first char
	if (rmp != ' ') goto @end
	st	X, ZL
@end:
	ret
.endproc
;
;=================================================
;        Display binary numbers as decimal
;=================================================
;
; Converts a binary in R2:R1 to a digit in X
;   binary in Z
;
.proc DecConv
	rmp = 0
@1:
	if (r2.r1 < ZH.ZL) goto @2 ; ended subtraction
;	cp R1,ZL ; smaller than binary digit?
;	cpc R2,ZH
;	brcs @2 ; ended subtraction
	r2.r1 -= Z 
	rmp++
	rjmp @1
@2:
	if (rmp != 0) goto @3
	if (r0 != 0) goto @3
	rmp = ' ' ; suppress leading zero
	rjmp @4
@3:
	rmp += '0'
@4:
	st X+, rmp
	ret	
.endproc	
;
; Display fractional number in R3:R2:(Fract)R1
;
.proc DisplFrac
	X = s_video_mem
	rmp = ' '
	st X+, rmp
	st X+, rmp

	r0 = 0
	Z = 10000
	rcall DisplDecY2
	Z = 1000
	rcall DisplDecY2

	rmp = c1kSep
	if (r0 != 0) goto @0
	rmp = ' '
@0:
	st X+, rmp

	rcall DisplDecY1 (val: 100)
	rcall DisplDecY1 (val: 10)
	rmp = '0' + R2
	st	X+, rmp
	if (R1 != 0) goto @1
	rmp = ' '
	st	X+, rmp
	rmp = 'H'
	st	X+, rmp
	rmp = 'z'
	st	X+, rmp

	rmp = ' '
	st	X+, rmp
	st	X+, rmp
	st	X+, rmp
	st	X+, rmp
	ret
@1:
	rmp = cDecSep
	;rmp = cDecSep
	st	X+, rmp
	
	.loop (ZL = 3)
		rRes3 = 0
		rRes2 = 0
		R0 = rRes1 ; * 1
		lsl	rRes1 ; * 2
		adc	rRes2,rRes3
		lsl	rRes1 ; * 4
		rol	rRes2
		rRes2.rRes1 += rRes3.r0
		lsl	rRes1 ; * 10
		rol	rRes2
		rmp = '0' + rRes2
		st	X+, rmp
	.endloop

	rmp = ' '
	st	X+, rmp
	rmp = 'H'
	st	X+, rmp
	rmp = 'z'
	st	X+, rmp
	rmp = ' '
	st	X+, rmp
	ret
.endproc	
;
; Convert a decimal in R4:R3:R2, decimal in ZH:ZL
;
.proc DisplDecY2
	rDiv1 = 0 ; rDiv1 is counter
	rDiv2 = 0 ; overflow byte
@a:
	if (rRes4.rRes3.rRes2 < rDiv2.ZH.ZL) goto @b ; ended
	rRes4.rRes3.rRes2 -= rDiv2.ZH.ZL
	rDiv1++
	rjmp @a
@b:
	rmp = '0' + rDiv1
	r0 += rDiv1
	if (r0 != 0) goto @c
	rmp = ' '
@c:
	st X+,rmp
	ret
.endproc
;
; Convert a decimal decimal in R:R2, decimal in ZL
;
.proc DisplDecY1
.args val(ZL)
	rDiv1 = 0 ; rDiv1 is counter
	rDiv2 = 0 ; overflow byte
@a:
	if (rRes3.rRes2 < rDiv2.ZL) goto @b ; ended
	rRes3.rRes2 -= rDiv2.ZL
	rDiv1++
	rjmp @a
@b:
	rmp = '0' + rDiv1
	r0 += rDiv1
	if (r0 != 0) goto @c
	rmp = ' '
@c:
	st X+, rmp
	ret
.endproc
;
; Display a 4-byte-binary in decimal format on result line 1
;   8-bit-display: "12345678"
;   16-bit-display: "  12.345.678 Hz "
;
.proc Displ4Dec
	rmp = BYTE1(100000000) ; check overflow
	cp rRes1, rmp
	rmp = BYTE2(100000000)
	cpc rRes2, rmp
	rmp = BYTE3(100000000)
	cpc rRes3, rmp
	rmp = BYTE4(100000000)
	cpc rRes4, rmp
	brcs @1
	rjmp CycleOvf
@1:
	r0 = 0 ; suppress leading zeroes
	X = s_video_mem	; X to result buffer

	rmp = ' ' ; clear the first two digits
	st X+, rmp
	st X+, rmp

	ZH.ZL.rmp = 10000000	; 10 mio
	rcall DisplDecX3
	ZH.ZL.rmp = 1000000		; 1 mio
	rcall DisplDecX3

	rmp = c1kSep ; set separator
	if (R0 != 0) goto @2
	rmp = ' '
@2:
	st X+, rmp

	ZH.ZL.rmp = 100000	; 100 k
	rcall DisplDecX3
	Z = 10000			; 10 k
	rcall DisplDecX2
	Z = 1000			; 1 k
	rcall DisplDecX2

	rmp = c1kSep ; set separator
	if (r0 != 0) goto @3
	rmp = ' '
@3:
	st X+, rmp

	rcall DisplDecX1 (100)
	rcall DisplDecX1 (10)
	rmp = '0' + r1
	st X+, rmp
	ret
.endproc
;
; Convert a decimal in R3:R2:R1, decimal in ZH:ZL:rmp
;
.proc DisplDecX3
	rDiv1 = 0 ; rDiv1 is counter
	rDiv2 = 0 ; subtractor for byte 4
@a:
	if (rRes4.rRes3.rRes2.rRes1 < rDiv2.ZH.ZL.rmp) goto @b ; ended
	rRes4.rRes3.rRes2.rRes1 -= rDiv2.ZH.ZL.rmp
	rDiv1++
	rjmp @a
@b:
	rmp = '0' + rDiv1
	r0 += rDiv1
	if (r0 != 0) goto @c
	rmp = ' '
@c:
	st X+, rmp
	ret
.endproc	
;
; Convert a decimal in R3:R2:R1, decimal in ZH:ZL
;
.proc DisplDecX2
	rDiv1 = 0 ; rDiv1 is counter
	rDiv2 = 0 ; next byte overflow
@a:
	if (rRes3.rRes2.rRes1 < rDiv2.ZH.ZL) goto @b		; ended
	rRes3.rRes2.rRes1 -= rDiv2.ZH.ZL
	rDiv1++
	rjmp @a
@b:
	rmp = '0' + rDiv1
	r0 += rDiv1
	if (r0 != 0) goto @c
	rmp = ' '
@c:
	st X+, rmp
	ret
.endproc	
;
; Convert a decimal in R2:R1, decimal in ZL
;
.proc DisplDecX1
.args val(ZL)
	rDiv1 = 0 ; rDiv1 is counter
	rDiv2 = 0 ; next byte overflow
@a:
	if (rRes2.rRes1 < rDiv2.ZL) goto @b ; ended
	rRes2.rRes1 -= rDiv2.ZL
	rDiv1 ++
	rjmp @a
@b:
	rmp = '0' + rDiv1
	R0 += rDiv1
	if (R0 != 0) goto @c
	rmp = ' '
@c:
	st X+, rmp
	ret
.endproc
;
;=================================================
;             Delay routines
;=================================================
;
Delay50ms:
	rDelH.rDelL = 50000 
	rjmp DelayZ
Delay10ms:
	rDelH.rDelL = 10000 
	rjmp DelayZ
Delay15ms:
	rDelH.rDelL = 15000 
	rjmp DelayZ
Delay4_1ms:
	rDelH.rDelL = 4100 
	rjmp DelayZ
Delay1_64ms:
	rDelH.rDelL = 1640
	rjmp DelayZ
Delay100us:
	; rDelH.rDelL = 100
	rDelH = 0
	rDelL = 100
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
	sbiw rDelL, 1 ; 2
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
	rFlg = 0 ; set flags to default
;
.IF debug
.EQU number = 100000000
	; rRes4 = rmp = BYTE4(number)
	rmp = BYTE4(number)
	rRes4 = rmp
	rDiv4 = rmp
	rmp = BYTE3(number)
	rRes3 = rmp
	rDiv3 = rmp
	ldi rmp,BYTE2(number)
	rRes2 = rmp
	rDiv2 = rmp
	ldi rmp,BYTE1(number)
	rRes1 = rmp
	rDiv1 = rmp
	rcall CycleM6
beloop:	
	rjmp beloop
.ENDIF
.IF debugpulse
	.EQU nhigh = 100000000
	.EQU nlow = 15000
	rmp = BYTE4(nhigh)
	sts sCtr+3,rmp
	rmp = BYTE3(nhigh)
	sts sCtr+2,rmp
	rmp = BYTE2(nhigh)
	sts sCtr+1,rmp
	rmp = BYTE1(nhigh)
	sts sCtr,rmp
	rmp = BYTE4(nlow)
	rRes4 = rmp
	rDiv4 = rmp
	rmp = BYTE3(nlow)
	rRes3 = rmp
	rDiv3 = rmp
	rmp = BYTE2(nlow)
	rRes2 = rmp
	rDiv2 = rmp
	rmp = BYTE1(nlow)
	rRes1 = rmp
	rDiv1 = rmp
	sbr rFlg,1<<bEdge
	rcall CycleM7
bploop: 
	rjmp bploop
.ENDIF
;
; Clear the output storage
;
	Z = s_video_mem
	rmp = ' '
	R0 = rmp
	.loop (rmp = 32)
		st	Z+, R0
	.endloop
;
; Init the Uart
;
.IF cUart
	rcall UartInit
	ldi rmp,1<<bUMonU ; monitor U over Uart
	sUartFlag = rmp
	rmp = 20 ; 5 seconds
	sUartMonURpt = rmp ; set repeat default value
	rmp = 1
	sUartMonUCnt = rmp
	rmp = 4 ; 1 seconds
	sUartMonFCnt = rmp
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
	sEncoderPrev = rmp

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
	rmp = 1 					; initial mode = 1
	sModeNext = rmp
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
	ZL = sEncoderPrev
	lsl	ZL
	lsl	ZL
	in	rmp, PINC
	andi	rmp, 3
	sEncoderPrev = rmp
	or	ZL, rmp	; encoder value in ZL

	ZH = rMode
	; 1 7 8 14 -> clockwise
	if (ZL == 1) goto Interval_enc_clockwise
	if (ZL == 7) goto Interval_enc_clockwise
	if (ZL == 8) goto Interval_enc_clockwise
	if (ZL == 14) goto Interval_enc_clockwise
	; 2 4 11 13 -> counterclockwise
	if (ZL == 2) goto Interval_enc_counterclockwise
	if (ZL == 4) goto Interval_enc_counterclockwise
	if (ZL == 11) goto Interval_enc_counterclockwise
	if (ZL == 13) goto Interval_enc_counterclockwise
	rjmp	Interval_noChanges
Interval_enc_clockwise:
	ZH++
	if (ZH < 9) goto Interval_enc_done
	ZH = 8			; set to 9
	rjmp Interval_enc_done
Interval_enc_counterclockwise:
	if (ZH == 0) goto Interval_enc_done
	ZH--
Interval_enc_done:



	sModeNext = ZH 			; store next mode
	if (rMode == ZH) goto Interval_noChanges

	; delay for 100 ms duration
	cli
	rcall delay50ms
	rcall delay50ms
	in	rmp, PINC
	andi	rmp, 3
	sEncoderPrev = rmp
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
;.extern TxtOvf16 : prgptr
Cycle:
	sbrc rFlg, bOvf ; check overflow
	rjmp CycleOvf ; jump to overflow
	rRes4.rRes3.rRes2.rRes1 = rCpy4.rCpy3.rCpy2.rCpy1		; copy counter
	cbr rFlg, (1<<bCyc)|(1<<bOvf) ; clear cycle flag and overflow
	rDiv4.rDiv3.rDiv2.rDiv1 = rRes4.rRes3.rRes2.rRes1		; copy again
.IF cUart
	;Z = UartMonF
	ldi ZH, HIGH(UartMonF) ; put monitoring frequency on stack
	ldi ZL, LOW(UartMonF)
	push ZL ZH
.ENDIF
; calculate and display result
	ldi ZH, HIGH(CycleTab) ; point to mode table
	ldi ZL, LOW(CycleTab)
	add ZL, rMode ; displace table by mode
	brcc Cycle1
	ZH++
Cycle1:
	ijmp ; call the calculation routine
; overflow occurred
CycleOvf:
	cbr rFlg, (1<<bCyc)|(1<<bOvf) ; clear cycle flag and overflow
	X = s_video_mem	; point to result buffer
	Z = TxtOvf16		; point to long message
	.loop (rmp = 16):
		lpm
		Z ++
		st X+, R0
	.endloop
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
	rDiv1 = 0 ; for detecting an overflow in R5

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

	if (rDiv1 == 0) goto CycleM0a ; no error
	rjmp CycleOvf

	
CycleM0a:
	rcall Displ4Dec
	rmp = ' '
	st	X+, rmp
	rmp = 'H'
	st	X+, rmp
	rmp = 'z'
	st	X+, rmp
	rmp = ' '
	st	X, rmp
	rjmp DisplMode ('F')
;
; Mode 1: Frequency measured, prescale = 1, display frequency
;
CycleM1:
	rDiv1 = 0 ; detect overflow in rDiv1
	
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

	if (rDiv1 == 0) goto CycleM1a ; no error
	rjmp CycleOvf
CycleM1a:
	rcall Displ4Dec
	rmp = ' '
	st	X+, rmp
	rmp = 'H'
	st	X+, rmp
	rmp = 'z'
	st	X+, rmp
	rmp = ' '
	st	X, rmp
	rjmp	DisplMode ('f')
;
; Mode 2: Time measured, prescale = 1, display frequency
;
CycleM2:
	rcall Divide
	if (rRes4 != 0) goto CycleM2a
	rcall DisplFrac
	rcall DisplMode ('v')
	ret
CycleM2a:
	rRes3.rRes2.rRes1 = rRes4.rRes3.rRes2		; number too big, skip fraction
	rRes4 = 0
	rcall Displ4Dec
	rmp = ' '
	st X+,rmp
	rmp = 'H'
	st X+,rmp
	rmp = 'z'
	st X+,rmp
	rmp = ' '
	st X,rmp
	rcall DisplMode ('v')
	ret
;
; Measure time, display rounds per minute
;
CycleM3:
	rcall Divide
	r0 = 0 ; overflow detection
	rmp = 0
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
	rDiv4.rDiv3.rDiv2.rDiv1 = rRes4.rRes3.rRes2.rRes1
;	mov rDiv1,rRes1 ; copy
;	mov rDiv2,rRes2
;	mov rDiv3,rRes3
;	mov rDiv4,rRes4
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
	if (r0 == 0) goto CycleM3a
	rjmp CycleOvf
CycleM3a:
	rRes4.rRes3.rRes2.rRes1 -= rDiv4.rDiv3.rDiv2.rDiv1
	rRes3.rRes2.rRes1 = rRes4.rRes3.rRes2
	rRes4 = 0
	rcall Displ4Dec
	rmp = ' '
	st X+, rmp
	rmp = 'r'
	st X+,rmp
	rmp = 'p'
	st X+,rmp
	rmp = 'm'
	st X+, rmp

	rcall DisplMode ('u')
	ret
;
; Measure time high+low, display time
;
CycleM4:
	rcall Multiply
	rcall Displ4Dec
	rcall DisplSec
	rcall DisplMode ('t')
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
	rcall DisplMode ('h')
CycleM5a:
	ret
;
; Measure time low, display time
;
CycleM6:
	sbrc	rFlg,bEdge
	rjmp	CycleM6a
	rcall Multiply
	rcall Displ4Dec
	rcall DisplSec
	rcall DisplMode ('l')
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
	Z = sCtr			; edge is high, calculate
	ld rRes1, Z+ ; copy counter value
	ld rRes2, Z+
	ld rRes3, Z+
	ld rRes4, Z+
	rDiv4.rDiv3.rDiv2.rDiv1 += rRes4.rRes3.rRes2.rRes1		; add to total time
	brcs CycleM7b
	rDelH.rDelL.r0.rmp = rRes4.rRes3.rRes2.rRes1				; copy high value to divisor
	rcall CalcPw ; calculate the ratio
	brcs CycleM7b ; error
	rcall DisplPw ; display the ratio
	rjmp DisplMode ('P')
CycleM7a:
	Z = sCtr
	st Z+, rRes1 ; copy counter value
	st Z+, rRes2
	st Z+, rRes3
	st Z+, rRes4
	ret
CycleM7b: ; overflow
	rmp = 'P'
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
	Z = sCtr		; edge is high, calculate
	ld rmp,Z+ ; read high-time
	ld R0, Z+
	ld rDelL, Z+
	ld rDelH, Z
	rDiv4.rDiv3.rDiv2.rDiv1 += rDelH.rDelL.R0.rmp		; add to total time
	rDelH.rDelL.R0.rmp = rRes4.rRes3.rRes2.rRes1
	rcall CalcPw ; calculate the ratio
	brcs CycleM8b ; error
	rcall DisplPw ; display the ratio
	rjmp DisplMode ('p')
CycleM8a:
	Z = sCtr
	st Z+,rRes1 ; copy counter value
	st Z+,rRes2
	st Z+,rRes3
	st Z+,rRes4
	ret
CycleM8b: ; overflow
	rmp = 'p'
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
.proc LcdRs8
.args val(rmp)
	out PORTB, val
	rcall LcdE
	ret
.endproc
;
; write rmp as 4-bit-command to the LCD
;
.proc LcdRs4
.args val(rmp)
	R0 = rmp ; copy rmp
	swap rmp ; upper nibble to lower nibble
	andi rmp,0x0F ; clear upper nibble
	out PORTB,rmp ; write to display interface
	rcall LcdE ; pulse E
	rmp = R0 ; copy original back
	andi rmp,0x0F ; clear upper nibble
	out PORTB,rmp ; write to display interface
	rcall LcdE
	rmp = R0 ; restore rmp
	ret
.endproc
;
; write rmp as data over 4-bit-interface to the LCD
;
LcdData4:
	push rmp
	rmp = R0
	swap rmp ; upper nibble to lower nibble
	andi rmp,0x0F ; clear upper nibble
	sbr rmp,1<<bLcdRs ; set Rs to one
	out PORTB,rmp ; write to display interface
	rcall LcdE ; pulse E
	rmp = r0 ; copy original again
	andi rmp,0x0F ; clear upper nibble
	sbr rmp,1<<bLcdRs ; set Rs to one
	out PORTB,rmp ; write to display interface
	rcall LcdE
	rcall Delay40us
	pop rmp
	ret
;
; writes the text in flash to the LCD, number of
; characters in rmp
;
.proc LcdText
.args len(R16)
	.loop (len)
		lpm						; read character from flash
		Z++
		rcall	LcdData4 			; write to 
		rcall	delay40us
	.endloop
	ret
.endproc
;
; Inits the LCD with a 4-bit-interface
;
LcdInit:
	ldi rmp,0x0F | (1<<bLcdE) | (1<<bLcdRs)
	out DDRB,rmp
	rmp = 0
	out PORTB,rmp
	rcall delay15ms ; wait for complete self-init
	rcall LcdRs8 (0x03)		; Function set 8-bit interface
	rcall delay4_1ms ; wait for 4.1 ms
	rcall LcdRs8 (0x03)		; Function set 8-bit interface
	rcall delay100us ; wait for 100 us
	rcall LcdRs8 (0x03)		; Function set 8-bit interface
	rcall delay40us ; delay 40 us
	rcall LcdRs8 (0x02)		; Function set 4-bit-interface
	rcall delay40us
	rcall LcdRs4 (0x28)		; 4-bit-interface, two line display
	rcall delay40us ; delay 40 us
	rcall LcdRs4 (0x08)		; display off
	rcall delay40us ; delay 40 us
	rcall LcdRs4 (0x01)		; display clear
	rcall delay1_64ms ; delay 1.64 ms
	rcall LcdRs4 (0x06)		; increment, don't shift
	rcall delay40us ; delay 40 us
	rcall LcdRs4 (0x0C)		; display on
	rcall delay40us
	rcall LcdRs4 (0x80)		; position on line 1
	rcall delay40us ; delay 40 us
	rmp = 16
	Z = LcdInitTxt16
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
	rcall LcdRs4 (0x80)				; set display position to line 1
	rcall Delay40us
	Z = s_video_mem

	.loop (rmp = 16)
		ld	R0, Z+				; read a char
		rcall LcdData4				; display on LCD
	.endloop
	ret
;
; Display voltage on the display
;
LcdDisplayU:
;	lds	rmp, sModeNext
;	subi	rmp, -'0'
;	sts	s_video_mem+31, rmp

	rcall LcdRs4 (0xC0) ; set output position, output to line 2
	rcall Delay40us
	Z = s_video_mem + 16		; point to result
	.loop (rmp = 16)
		ld	R0, Z+			; read character
		rcall LcdData4			; write r0 as data over 4-bit-interface to the LCD
	.endloop
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
	sUartRxBp = rmp
	ldi rmp,HIGH(cUbrr) ; set URSEL to zero, set baudrate msb
	out UBRRH,rmp
	ldi rmp,LOW(cUbrr) ; set baudrate lsb
	out UBRRL,rmp
	rmp = (1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0) ; set 8 bit characters
	out UCSRC,rmp
	rmp = (1<<RXCIE)|(1<<RXEN)|(1<<TXEN) ; enable RX/TX and RX-Ints
	out UCSRB, rmp
	rcall delay10ms ; delay for 10 ms duration
	;Z = txtUartInit
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
.extern UartReturn : ptr

.proc UartRxLine
	cbr rFlg,1<<bUartRxLine ; clear line complete flag
	ldi rmp, LOW(sUartRxBs) ; set buffer pointer to start
	sUartRxBp = rmp
	Z = UartReturn
	push ZL ZH
	Z = sUartRxBs
	ld rmp, Z+ ; read first character
	if (rmp != 'h') goto @1		; help?
	rjmp UartHelp
@1:
	if (rmp != '?') goto @2		; help?
	rjmp UartHelp
@2:
	if (rmp != 'U') goto @3		; monitor U on
	rcall UartGetPar
	sec
	rjmp UartMonUSetC
@3:
	if (rmp != 'u') goto @4		; monitor U off
	clc
	rjmp UartMonUSetC
@4:
	if (rmp != 'F') goto @5		; monitor F on
	rcall UartGetPar
	sec
	rjmp UartMonFSetC
@5:
	if (rmp != 'f') goto @6		; monitor f off
	clc
	rjmp UartMonFSetC
@6:
	if (rmp != 'p') goto @7		; parameter?
	rjmp UartMonPar
@7:
	Z = txtUartUnknown
	ret
UartHelp:
	Z = txtUartHelp
	ret
UartMonUSetC:
	rmp = sUartFlag
	brcs UartMonUSetC1
	cbr rmp,1<<bUMonU ; clear flag
	sUartFlag = rmp
	Z = txtUartUOff
	ret
UartMonUSetC1:
	brne UartMonUSetC2
	sUartMonURpt = r0
	sUartMonUCnt = r0
UartMonUSetC2:
	sbr rmp,1<<bUMonU ; set flag
	sUartFlag = rmp
	Z = txtUartUOn
	ret
UartMonFSetC:
	rmp = sUartFlag
	brcs UartMonFSetC1
	cbr rmp,1<<bUMonF ; clear flag
	sUartFlag = rmp
	Z = txtUartFOff
	ret
UartMonFSetC1:
	brne UartMonFSetC2
	sUartMonFRpt = r0
	sUartMonFCnt = r0
UartMonFSetC2:
	sbr rmp,1<<bUMonF ; set flag
	sUartFlag = rmp
	Z = txtUartFOn
	ret
UartMonPar:
	Z = txtUartNul
	rcall UartSendChar ('U')
	rcall UartSendChar ('=')
	rcall UartSendChar ('$')
	rcall UartHexR (sUartMonURpt)
	rcall UartSendChar (',')
	rcall UartSendChar (' ')
	rcall UartSendChar ('F')
	rcall UartSendChar ('=')
	rcall UartSendChar ('$')
	rjmp UartHexR (sUartMonFRpt)
.endproc	
;
; Get Parameter from line
;
.proc UartGetPar
	r0 = 0 ; result register
	ld rmp, Z+ ; read char
	if (rmp == cCr) goto @NoPar
	if (rmp == cLf) goto @NoPar
	if (rmp != '=') goto @Err
@1:
	; rmp = $data[Z++]
	ld rmp, Z+ ; read next char
	if (rmp == cCr) goto @2
	if (rmp == cLf) goto @2
	rmp -= '0'
	brcs @Err
	if (rmp >= 10) goto @Err
	rir = r0
	lsl r0 ; * 2
	brcs @Err
	lsl r0 ; * 4
	brcs @Err
	r0 += rir ; * 5
	brcs @Err
	lsl R0 ; * 10
	brcs @Err
	r0 += rmp ; add new decimal
	brcs @Err
	rjmp @1
@2:
	sez
	ret
@Err:
	Z = txtUartErr
	rcall UartSendTxt
@NoPar:
	clz ; No parameter set
	ret
.endproc
;
; Hex output over Uart, for debugging
;
.proc UartHexR
.args val(rmp)
	push	val
	swap	val
	rcall @N
	pop	val
@N:
	andi val, 0x0F
	val += '0'
	if (val < '9'+1) goto @N1
	val += 7
@N1:
	rjmp UartSendChar
	ret 			; TODO extra ret !!!
.endproc
;
; Return from Uart-Routines, displays text in Z
;
UartReturn:
	rcall UartSendTxt ; send text in Z
	Z = txtUartCursor
	rjmp UartSendTxt
;
; Send character in rmp over Uart
;
.proc UartSendChar
.args char(rmp)
	sbis	UCSRA, UDRE		; wait for empty buffer
	rjmp	UartSendChar
	out	UDR, rmp
	ret
.endproc
;
; Monitoring the voltage over the Uart
;
UartMonU:
	rmp = sUartFlag ; flag register for Uart
	sbrs rmp,bUMonU ; displays voltage over Uart
	ret
	rmp = sUartMonUCnt - 1 ; read counter
	sUartMonUCnt = rmp
	brne UartMonU2
	rmp = sUartMonURpt
	sUartMonUCnt = rmp
	Z = s_video_mem + 16
	.loop (rmp = 8)
UartMonU1:
		sbis UCSRA,UDRE ; wait for empty buffer
		rjmp UartMonU1
		ld R0,Z+
		out UDR,R0
	.endloop
	rcall UartSendChar (cCR)
	rjmp UartSendChar (cLF)
UartMonU2:
	ret
;
; Monitor frequency over UART
;
UartMonF:
	rmp = sUartFlag ; flag register for Uart
	sbrs rmp, bUMonF ; displays frequency over Uart
	ret
	rmp = sUartMonFCnt - 1	; read counter
	sUartMonFCnt = rmp
	brne UartMonF2
	rmp = sUartMonFRpt
	sUartMonFCnt = rmp
	Z = s_video_mem
	.loop (rmp = 16)
	UartMonF1:
		sbis UCSRA, UDRE ; wait for empty buffer
		rjmp UartMonF1
		ld R0, Z+
		out UDR, R0
	.endloop
	rcall UartSendChar (cCR)
	rjmp UartSendChar (cLF)
UartMonF2:
	ret
;
; Send text from flash to UART, null byte ends transmit
;
.proc UartSendTxt
	lpm ; read character from flash
	Z++
	if (r0 == 0) goto @ret
@wait:
	sbis	UCSRA, UDRE ; wait for empty char
	rjmp	@wait
	out	UDR, r0 ; send char
	rjmp	UartSendTxt
@ret:
	ret
.endproc
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
