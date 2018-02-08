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
	rSreg = io[SREG] 		; save SREG
	rTDiv-- 				; count down
	brne	TC2CmpInt1 		; not zero, interval not ended
	lds	rTDiv, sTMeas 		; restart interval timer
TC2CmpInt1:
	io[SREG] = rSreg 		; restore SREG
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
	rSreg = io[SREG] 		; 1, save SREG
	sbrc	rFlg, bCyc 		; 2/3, check if cycle flag signals ok for copy
	rjmp	Int0Int1 			; 4, no, last result hasn't been read
	rCpy1 = io[TCNT1L] 		; 4, read timer 1 LSB
	rCpy2 = io[TCNT1H] 		; 5, dto., MSB
	rCpy3 = rCtr2 			; 6, copy the counter bytes
	rCpy4 = rCtr3 			; 7
	rFlg |= 1<<bCyc 		; 8, set cycle end flag bit
	cbr	rFlg, 1<<bEdge 	; 9, set falling edge
	sbic	PIND, 2 			; 10/11, check if input = 0
	rFlg |= 1<<bEdge 	; 11, no, set edge flag to rising
Int0Int1: 				; 4/11
	ldi	rimp, 0 			; 5/12, reset the timer
	io[TCNT1H] = rimp 		; 6/13, set TC1 zero to restart
	io[TCNT1L] = rimp 		; 7/14
	rCtr1 = rimp 			; 8/15, clear the upper bytes
	rCtr2 = rimp 			; 9/16
	rCtr3 = rimp 			; 10/17
	io[SREG] = rSreg 		; 11/18, restore SREG
	reti 				; 15/22
;
; TC1 Compare Match A Interrupt Service Routine
;   active in modes 0 and 1 (measuring the number of
;   sigals on the T1 input), timeout every 0.25s,
;   reads the counter TC0, copies the count to
;   the result registers and clears TC0
;
Tc1CmpAInt:
	rSreg = io[SREG] 		; 1, save SREG
	sbrc	rFlg, bCyc 		; 2/3, check if cycle flag signals ok for copy
	rjmp TC1CmpAInt1 		; 4, no, last result hasn't been read
	rCpy1 = io[TCNT0] 		; 4, read counter TC0
	rCpy2 = rCtr1			; 5, copy counter bytes to result
	rCpy3 = rCtr2 			; 6
	rCpy4 = rCtr3 			; 7
	rFlg |= 1<<bCyc 		; 8, set cycle end flag bit
Tc1CmpAInt1: 				; 4/8
	ldi	rimp, 0 			; 5/9, clear counter
	io[TCNT0] = rimp 		; 6/10
	rCtr1 = rimp 			; 7/11, clear counter bytes
	rCtr2 = rimp 			; 8/12
	rCtr3 = rimp 			; 9/13
	io[SREG] = rSreg 		; 10/14, restore SREG
	reti ; 			14/18
;
; TC1 Overflow Interrupt Service Routine
;   active in modes 2 to 6 counting clock cycles to measure time
;   increases the upper bytes and detects overflows
;
Tc1OvfInt:
	rSreg = io[SREG] 			; 1, save SREG
	rCtr2++					; 2, increase byte 3 of the counter
	brne	Tc1OvfInt1 			; 3/4, no overflow
	rCtr3++					; 4, increase byte 4 of the counter
	brne	Tc1OvfInt1 			; 5/6, no overflow
	rFlg |= (1<<bOvf)|(1<<bCyc) ; 6, set overflow and end of cycle bit
Tc1OvfInt1: 					; 4/6
	io[SREG] = rSreg 			; 5/7, restore SREG
	reti						; 9/11
;
; TC0 Overflow Interrupt Service Routine
;   active in modes 0 and 1 counting positive edges on T1
;   increases the upper bytes and detects overflows
;
Tc0OvfInt:
	rSreg = io[SREG] 			; 1, save SREG
	rCtr1++		 			; 2, increase byte 2 of the counter
	brne	Tc0OvfInt1 			; 3/4, no overflow
	rCtr2++	 				; 4, increase byte 3 of the counter
	brne	Tc0OvfInt1 			; 5/6, no overflow
	rCtr3++					; 6, increase byte 4 of the counter
	brne	Tc0OvfInt1 			; 7/8, no overflow
	rFlg |= (1<<bOvf)|(1<<bCyc)   ; 8, set overflow bit
Tc0OvfInt1: 				; 4/6/8
	io[SREG] = rSreg 			; 5/7/9, restore SREG
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
	rSreg = io[SREG] 					; 1, Save SReg
	rimp = io[UCSRA] 					; 2, Read error flags
	rimp &= (1<<FE)|(1<<DOR)|(1<<PE) 	; 3, isolate error bits
	rimp = io[UDR] 					; 4, read character from UART
	breq SioRxCIsr1 					; 5/6, no errors
	rimp = '*'						; 6, signal an error
	io[UDR] = rimp						; 7
	rjmp	SioRxCIsr4 					; 9, return from int
SioRxCIsr1: 							; 6
	io[UDR] = rimp						; 7, echo the character
	push	ZH ZL 						; 9, 11, Save Z register
	ZH = HIGH(sUartRxBs) 			; 12, Load Position for next RX char
	ZL = sUartRxBp 					; 14
	ram[Z++] = rimp					; 16, save char in buffer
	cpi	ZL, LOW(sUartRxBe+1) 			; 17, End of buffer?
	brcc SioRxCIsr2 					; 18/19, Buffer overflow
	sUartRxBp = ZL 					; 20, Save next pointer position
SioRxCIsr2: 							; 19/20
	cpi	rimp, cCR 					; 20/21, Carriage Return?
	brne SioRxCIsr3 					; 21/22/23, No, go on
	rimp = cLF	 					; 22/23, Echo linefeed
	io[UDR] = rimp 					; 23/24
	rFlg |= (1<<bUartRxLine) 			; 24/25, Set line complete flag
	rjmp	SioRxCIsr3a
SioRxCIsr3: 							; 22/23/24/25
	cpi	rimp, cLF
	brne	SioRxCIsr3a
	rFlg |= (1<<bUartRxLine)
SioRxCIsr3a:
	pop	ZL ZH						; 24/25/26/27, 26/27/28/29, restore Z-register
SioRxCIsr4:							; 9/26/27/28/29
	io[SREG] = rSreg					; 10/27/28/29/30, restore SREG
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
	rcall LcdRs4 (0xC0)	; line 2
	rcall delay40us 	; delay 40 us
	Z = MODE_0

	rmp = rMode
	; rmp *= 16
	rmp <<= 4		; mode * 16

	XL = 0
	Z += XL.rmp
	rmp = 16					; length
	X = s_video_mem + 16
	
LcdInitMode:
	loop (rmp) {
		r0 = prg[Z]
		Z++		; TODO
		ram[X++] = r0
	}
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
	rMode = rmp = sModeNext 		; read next mode
	rcall	SetModeName

	rMode = rmp = sModeNext 		; read next mode

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
	io[pPresc].bPresc = 0	; enable prescaler
	rjmp	SetModeF 			; frequency measurement
;
; Set counters/timers to mode 1
;
SetMode1:
	io[pPresc].bPresc = 1 	; disable prescaler
; Set timer/counter mode to frequency measurement
SetModeF:
	io[OCR1AH] = rmp = HIGH(cCmp1F)		; set the compare match high value
	io[OCR1AL] = rmp = LOW(cCmp1F) 		; set the compare match low value
	io[OCR1BH] = rmp = 0xff				; disable the compare match B
	io[OCR1BL] = rmp
	io[TCCR1A] = rmp = 0				; CTC mode
	io[TCCR1B] = rmp = cPre1F 			; set the prescaler value for TC1
	io[TCCR0] = rmp = (1<<CS02)|(1<<CS01)|(1<<CS00) 	; count rising edges on T0
	io[TIMSK] = rmp = (1<<OCIE2)|(1<<OCIE1A)|(1<<TOIE0) ; enable TC2Cmp, TC1CmpAInt and TC0OverflowInt
	ret
;
; Set timer/counter mode to time measurement
;
SetModeT:
	io[pPresc].bPresc = 1				; disable prescaler
	io[TCCR1A] = rmp = 0				; timing mode
	io[TCCR1B] = rmp = 1<<CS10 			; count with prescaler = 1
	io[MCUCR] = rmp = (1<<SE)|(1<<ISC01)|(1<<ISC00)	; sleep enable, positive edges on INT0 interrupt
	io[GICR] = rmp = 1<<INT0					; enable INT0 interrupt
	io[TIMSK] = rmp = (1<<OCIE2)|(1<<TOIE1)		; enable TC2Cmp, TC1Ovflw
	ret
;
; Set timer/counter mode to time measurement, all edges
;
SetModeE:
	io[pPresc].bPresc = 1					; disable prescaler
	io[TCCR1A] = rmp = 0 					; timing mode
	io[TCCR1B] = rmp = 1<<CS10 				; count with prescaler = 1
	io[MCUCR] = rmp = (1<<SE)|(1<<ISC00) 		; sleep enable, any logical change on INT0 interrupts
	io[GICR] = rmp = 1<<INT0 				; enable INT0 interrupt
	io[TIMSK] = rmp = (1<<OCIE2)|(1<<TOIE1) 	; enable TC2Cmp, TC1Ovflw
	ret
;
;
; clears the timers and resets the upper bytes
;
ClrTc:
	io[GICR] = rmp = 0			; disable INT0
	rmp = 0					; TODO !!! stop the counters/timers
	io[TCCR0] = rmp 			; stop TC0 counting/timing
	io[TCCR1B] = rmp			; stop TC1 counting/timing
	io[TCNT0] = rmp			; clear TC0
	io[TCNT1L] = rmp			; clear TC1
	io[TCNT1H] = rmp
	rCtr1 = 0				; clear upper bytes
	rCtr2 = 0
	rCtr3 = 0
	io[TIMSK] = rmp = 1<<OCIE2			; enable only output compare of TC2 ints, timer int disable
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
	r0 = 0
	ZH = 0
	ZL = BYTE3(cFreq/256) ; set divisor
	XH = BYTE2(cFreq/256)
	XL = BYTE1(cFreq/256)
	rRes1 = 0 ; set result
	rRes1++
	rRes2 = 0
	rRes3 = 0
	rRes4 = 0
@loop:
	rmp.r0.ZH.ZL.XH.XL <<= 1		; multiply divisor by 2
	if (rmp.r0.ZH.ZL >= rDiv4.rDiv3.rDiv2.rDiv1) {		; compare with divident
		rmp.r0.ZH.ZL -= rDiv4.rDiv3.rDiv2.rDiv1
		F_CARRY = 1
		rjmp @3
	}
	F_CARRY = 0
@3:
	rol rRes1
	rol rRes2
	rol rRes3
	rol rRes4
	if (!F_CARRY) goto @loop
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
	X = cMulti		; set multiplicator
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
	;if (XH != 0) goto @4
	cpi XH, 0
	breq @4
@2:
	XL.XH >>= 1
	if (!F_CARRY) goto @3
	ZH.ZL.rDiv4.rDiv3.rDiv2.rDiv1 += rmp.r0.rRes4.rRes3.rRes2.rRes1
@3:
	rmp.r0.rRes4.rRes3.rRes2.rRes1 <<= 1
	rjmp @1
@4:
	rmp = 128 ; round result
	r0 = 0
	ZH.ZL.rDiv4.rDiv3.rDiv2 += r0.r0.r0.r0.rmp
	rRes4.rRes3.rRes2.rRes1 = ZH.ZL.rDiv4.rDiv3
	ret
.endproc
	
;
; Display seconds at buffer end
;
DisplSec:
	ram[X++] = rmp = ' '
	ram[X++] = rmp = 'u'
	ram[X++] = rmp = 's'
	ram[X] = rmp = ' '
	ret
;
; An overflow has occurred during pulse width calculation
;
.proc PulseOvflw (v: rmp)
	X = s_video_mem
	ram[X++] = rmp

	Z = TxtPOvflw16
	loop (rmp = 15) {
		r0 = prg[Z]
		Z++	; TODO use prg[Z++]
		ram[X++] = r0
	}
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
	F_CARRY = 1
	ret
	
.proc CalcPw
	rRes4.rRes3.rRes2.rRes1 = rDelH.rDelL.r0.rmp		; copy active cycle time to rRes
	rRes4.rRes3.rRes2.rRes1 <<= 1		; * 2
	if (F_CARRY) goto CalcPwO 		; overflow
	rRes4.rRes3.rRes2.rRes1 <<= 1		; * 4
	if (F_CARRY) goto CalcPwO 		; overflow
	rRes4.rRes3.rRes2.rRes1 <<= 1		; * 8
	if (F_CARRY) goto CalcPwO 		; overflow
	X = rRes2.rRes1
	Z = rRes4.rRes3
	rRes4.rRes3.rRes2.rRes1 <<= 1		; * 16
	if (F_CARRY) goto CalcPwO 		; overflow
	rRes4.rRes3.rRes2.rRes1 += ZH.ZL.XH.XL		; * 24
	ZH = 0 ; clear the four MSBs of divisor
	ZL = 0
	XH = 0
	XL = rDelH ; * 256
	rDelH = rDelL
	rDelL = r0
	r0 = rmp
	rmp = 0

	XH.XL.rDelH.rDelL.r0 <<= 1		; * 512
	XH.XL.rDelH.rDelL.r0 <<= 1		; * 1024
	
	XH.XL.rDelH.rDelL.r0.rmp -= ZH.ZH.rRes4.rRes3.rRes2.rRes1		; * 1000
	if (ZH.ZL.XH.XL >= rDiv4.rDiv3.rDiv2.rDiv1) goto CalcPwO		; overflow?
	rRes1 = 0 ; clear result
	rRes1++
	rRes2 = 0
	rRes3 = 0
	rRes4 = 0
@1: ; dividing loop
	ZH.ZL.XH.XL.rDelH.rDelL.r0.rmp <<= 1
	if (ZH.ZL.XH.XL >= rDiv4.rDiv3.rDiv2.rDiv1) { ; smaller, roll zero in
		ZH.ZL.XH.XL -= rDiv4.rDiv3.rDiv2.rDiv1				 ; subtract divisor
		F_CARRY = 1 	; roll one in
		rjmp @3
	}
	F_CARRY = 0
@3: ; roll result
	rol rRes1
	rol rRes2
	rol rRes3
	rol rRes4
	if (!F_CARRY) goto @1 ; roll on
	ZH.ZL.XH.XL.rDelL <<= 1	; round result
	if (ZH.ZL.XH.XL >= rDiv4.rDiv3.rDiv2.rDiv1) {
		rmp = 1 ; round up
		rRes1 += rmp
		ldi rmp, 0
		adc rRes2, rmp
		adc rRes3, rmp
		adc rRes4, rmp
	}
	if (rRes4 != 0) goto @Error
	if (rRes3 != 0) goto @Error
	;if (rRes2.rRes1 >= (rmp)1001)
	rmp = LOW(1001)
	cp rRes1, rmp
	rmp = HIGH(1001)
	cpc rRes2, rmp
	if (!F_CARRY) goto @Error
	F_CARRY = 0 	; no error
	ret
@Error:
	F_CARRY = 1
	ret
.endproc
;
; Display the binary in R2:R1 in the form "  100,0%"
;
.proc DisplPw
	X = s_video_mem
	ram[X++] = rmp = ' '
	ram[X++] = rmp
	r0 = 0
	rcall	DisplDecX2 (1000)
	rcall	DisplDecX2 (100)
	ZL = 10	
	r0++
	rcall DisplDecX2
	ram[X++] = rmp = cDecSep
	ram[X++] = rmp = '0' + rRes1
	ram[X++] = rmp = '%'
	ZL = ' '
	loop (rmp = 8) {
		ram[X++] = ZL
	}
	ret
.endproc

;
; If the first characters in the result buffer are empty,
;   place the character in ZL here and add equal, if possible
;
.proc DisplMode (val: ZL)
	X = s_video_mem+1
	rmp = ram[X] 							; read second char
	if (rmp == ' ') {
		ram[X] = rmp = '='
	}
	; TODO use ram[--X]
	X--
	rmp = ram[X] 							; read first char
	if (rmp == ' ') {
		ram[X] = ZL
	}
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
	if (r2.r1 >= ZH.ZL) { ; ended subtraction
		r2.r1 -= Z 
		rmp++
		rjmp @1
	}
	if (rmp != 0) goto @3
	if (r0 != 0) goto @3
	rmp = ' ' ; suppress leading zero
	rjmp @end
@3:
	rmp += '0'
@end:
	ram[X++] = rmp
	ret	
.endproc	
;
; Display fractional number in R3:R2:(Fract)R1
;
.proc DisplFrac
	X = s_video_mem
	ram[X++] = rmp = ' '
	ram[X++] = rmp

	r0 = 0
	rcall DisplDecY2 (10000)
	rcall DisplDecY2 (1000)

	rmp = c1kSep
	if (r0 == 0) {
		rmp = ' '
	}
	ram[X++] = rmp

	rcall DisplDecY1 (val: 100)
	rcall DisplDecY1 (val: 10)
	ram[X++] = rmp = '0' + r2
	
	if (r1 == 0) {
		ram[X++] = rmp = ' '
		ram[X++] = rmp = 'H'
		ram[X++] = rmp = 'z'
		ram[X++] = rmp = ' '
		ram[X++] = rmp
		ram[X++] = rmp
		ram[X++] = rmp
		ret
	}
	ram[X++] = rmp = cDecSep
	
	loop (ZL = 3) {
		rRes3 = 0
		rRes2 = 0
		r0 = rRes1 ; * 1
		rRes2.rRes1 += rRes3.rRes1	; *2
		rRes2.rRes1 <<= 1	; *4
		rRes2.rRes1 += rRes3.r0
		rRes2.rRes1 <<= 1	; *10
		
		ram[X++] = rmp = '0' + rRes2
	}

	ram[X++] = rmp = ' '
	ram[X++] = rmp = 'H'
	ram[X++] = rmp = 'z'
	ram[X++] = rmp = ' '
	ret
.endproc	
;
; Convert a decimal in R4:R3:R2, decimal in ZH:ZL
;
.proc DisplDecY2 (val: Z)
	rDiv1 = 0 ; rDiv1 is counter
	rDiv2 = 0 ; overflow byte

	loop {
		if (rRes4.rRes3.rRes2 < rDiv2.ZH.ZL) break
		rRes4.rRes3.rRes2 -= rDiv2.ZH.ZL
		rDiv1++
	}
	rmp = '0' + rDiv1
	r0 += rDiv1
	if (r0 == 0) {
		rmp = ' '
	}
	ram[X++] = rmp
	ret
.endproc
;
; Convert a decimal decimal in R:R2, decimal in ZL
;
.proc DisplDecY1 (val: ZL)
	rDiv1 = 0 ; rDiv1 is counter
	rDiv2 = 0 ; overflow byte

	loop {
		if (rRes3.rRes2 < rDiv2.ZL) break
		rRes3.rRes2 -= rDiv2.ZL
		rDiv1++
	}
	rmp = '0' + rDiv1
	r0 += rDiv1
	if (r0 == 0) {
		rmp = ' '
	}
	ram[X++] = rmp
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
	if (!F_CARRY) {
		rjmp CycleOvf
	}
	r0 = 0 ; suppress leading zeroes
	X = s_video_mem	; X to result buffer

	ram[X++] = rmp = ' '	; clear the first two digits
	ram[X++] = rmp

	rcall DisplDecX3 (10000000)	; 10 m
	rcall DisplDecX3 (1000000)	; 1 mio

	rmp = c1kSep ; set separator
	if (r0 == 0) {
		rmp = ' '
	}
	ram[X++] = rmp

	rcall DisplDecX3 (100000)	; 100 k
	rcall DisplDecX2 (10000)		; 10 k
	rcall DisplDecX2 (1000)		; 1 k

	rmp = c1kSep ; set separator
	if (r0 == 0) {
		rmp = ' '
	}
	ram[X++] = rmp
	rcall DisplDecX1 (100)
	rcall DisplDecX1 (10)
	ram[X++] = rmp = '0' + r1
	ret
.endproc
;
; Convert a decimal in R3:R2:R1, decimal in ZH:ZL:rmp
;
.proc DisplDecX3 (val: ZH.ZL.rmp)
	rDiv1 = 0 ; rDiv1 is counter
	rDiv2 = 0 ; subtractor for byte 4

	loop {
		if (rRes4.rRes3.rRes2.rRes1 < rDiv2.ZH.ZL.rmp) break
		rRes4.rRes3.rRes2.rRes1 -= rDiv2.ZH.ZL.rmp
		rDiv1++
	}
	rmp = '0' + rDiv1
	r0 += rDiv1
	if (r0 == 0) {
		rmp = ' '
	}
	ram[X++] = rmp
	ret
.endproc	
;
; Convert a decimal in R3:R2:R1, decimal in ZH:ZL
;
.proc DisplDecX2 (val: Z)
	rDiv1 = 0 ; rDiv1 is counter
	rDiv2 = 0 ; next byte overflow

	loop {
		if (rRes3.rRes2.rRes1 < rDiv2.ZH.ZL) break
		rRes3.rRes2.rRes1 -= rDiv2.ZH.ZL
		rDiv1++
	}
	rmp = '0' + rDiv1
	r0 += rDiv1
	if (r0 == 0) {
		rmp = ' '
	}
	ram[X++] = rmp
	ret
.endproc	
;
; Convert a decimal in R2:R1, decimal in ZL
;
.proc DisplDecX1 (val: ZL)
	rDiv1 = 0 ; rDiv1 is counter
	rDiv2 = 0 ; next byte overflow

	loop {
		if (rRes2.rRes1 < rDiv2.ZL) break
		rRes2.rRes1 -= rDiv2.ZL
		rDiv1++
	}

	rmp = '0' + rDiv1
	r0 += rDiv1
	if (r0 == 0) {
		rmp = ' '
	}
	ram[X++] = rmp
	ret
.endproc
;
;=================================================
;             Delay routines
;=================================================
;
Delay50ms:
	rjmp DelayZ (50000)
Delay10ms:
	rjmp DelayZ (10000)
Delay15ms:
	rjmp DelayZ (15000)
Delay4_1ms:
	rjmp DelayZ (4100)
Delay1_64ms:
	rjmp DelayZ (1640)
Delay100us:
	rjmp DelayZ (100)
Delay40us:
	rjmp DelayZ (40)
;
; Delays execution for Z microseconds
;
.proc DelayZ (ms: rDelH.rDelL)
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
	rDelH.rDelL -= 1
	brne DelayZ ; 2
	ret
.endproc
;
; =========================================
; Main Program Start
; =========================================
;
main:
	io[SPH] = rmp = HIGH(RAMEND) ; set stack pointer
	io[SPL] = rmp = LOW(RAMEND)
	rFlg = 0 ; set flags to default
;

.IF debug
.EQU number = 100000000
	rDiv4 = rRes4 = rmp = BYTE4(number) 
	rDiv3 = rRes3 = rmp = BYTE3(number)
	rDiv2 = rRes2 = rmp = BYTE2(number)
	rDiv1 = rRes1 = rmp = BYTE1(number)
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
	
	rDiv4 = rRes4 = rmp = BYTE4(nlow)
	rDiv3 = rRes3 = rmp = BYTE3(nlow)
	rDiv2 = rRes2 = rmp = BYTE2(nlow)
	rDiv1 = rRes1 = rmp  = BYTE1(nlow)
	rFlg |= 1<<bEdge
	rcall CycleM7
bploop: 
	rjmp bploop
.ENDIF
;
; Clear the output storage
;
	Z = s_video_mem
	r0 = rmp = ' '
	loop (rmp = 32) {
		ram[Z++] = r0
	}
;
; Init the Uart
;
.IF cUart
	rcall UartInit
	sUartFlag = rmp = 1<<bUMonU ; monitor U over Uart
	sUartMonURpt = rmp = 20 ; set repeat default value (5 seconds)
	sUartMonUCnt = rmp = 1
	sUartMonFCnt = rmp = 4 ; 1 second
.ENDIF

	rcall LcdInit					; Init the LCD
	
	io[ACSR] = rmp = 1<<ACD			; Disable the Analog comparator

	; Disable the external prescaler by 16
	io[pPrescD].bPresc = 1			; set prescaler port bit to output
	io[pPresc].bPresc = 1			; disable the prescaler

	; Init encoder
	io[DDRC].0 = 0
	io[DDRC].1 = 0
	io[PORTC].0 = 1
	io[PORTC].1 = 1

	sEncoderPrev = rmp = io[PINC] & 3
	
	; Start main interval timer
	io[OCR2] = rmp = cCmp2				; set Compare Match
	io[TCCR2] = rmp = cPre2 | (1<<WGM21)	; CTC mode and prescaler
	io[TIMSK] = rmp = 1<<OCIE2 			; Start timer/counter TC2 interrupts
	sModeNext = rmp = 1					; Set initial mode to mode 1
	rcall SetModeNext
	sei 								; enable interrupts
;
; --------[main loop] start --------------------
main_loop:
	sleep 								; send CPU to sleep
	nop
	; if meassure cycle ended then call Cycle()
	if (rFlg[bCyc]) rcall Cycle							; calculate and display result
	; if adc conversation ended then call Interval
	rcall Interval
.IF cUart
	; if Uart line complete rhen can UartRxLine
	if (rFlg[bUartRxLine]) rcall UartRxLine						; call line complete
.ENDIF
	rjmp main_loop 						; go to sleep
; --------[main loop] end --------------------	
;
; Timer interval for calculation and display
;



.proc Interval
	ZL = sEncoderPrev
	ZL <<= 2
	sEncoderPrev = rmp = io[PINC] & 3
	ZL |= rmp			; encoder value in ZL

	ZH = rMode
	; 1 7 8 14 -> clockwise
	if (ZL == 1) goto @clockwise
	if (ZL == 7) goto @clockwise
	if (ZL == 8) goto @clockwise
	if (ZL == 14) goto @clockwise
	; 2 4 11 13 -> counterclockwise
	if (ZL == 2) goto @counterclockwise
	if (ZL == 4) goto @counterclockwise
	if (ZL == 11) goto @counterclockwise
	if (ZL == 13) goto @counterclockwise
	rjmp	@noChanges
@clockwise:
	ZH++
	if (ZH < 9) goto @done
	ZH = 8			; set to 9
	rjmp @done
@counterclockwise:
	if (ZH == 0) goto @done
	ZH--
@done:

	sModeNext = ZH 			; store next mode
	if (rMode != ZH) {
		cli
		rcall delay50ms
		rcall delay50ms
		sEncoderPrev = rmp = io[PINC] & 3
		sei
		
		rcall SetModeNext ; start new mode
	}
@noChanges:


;	rcall cAdc2U 			; convert to text
	rcall LcdDisplayFT
	rcall LcdDisplayU
	
.IF cUart
	rcall UartMonU
.ENDIF
	ret
.endproc	
;
; Frequency/Time measuring cycle ended, calculate results
;
;.extern TxtOvf16 : prgptr
.proc Cycle
	if (rFlg[bOvf]) goto CycleOvf
	rRes4.rRes3.rRes2.rRes1 = rCpy4.rCpy3.rCpy2.rCpy1		; copy counter
	cbr rFlg, (1<<bCyc)|(1<<bOvf) ; clear cycle flag and overflow
	rDiv4.rDiv3.rDiv2.rDiv1 = rRes4.rRes3.rRes2.rRes1		; copy again
.IF cUart
	Z = UartMonF/2		; put monitoring frequency on stack
	;ldi ZH, HIGH(UartMonF) ; put monitoring frequency on stack
	;ldi ZL, LOW(UartMonF)
	push ZL ZH
.ENDIF
	; calculate and display result
	Z = CycleTab/2		; point to mode table
	ZL += rMode ; displace table by mode
	if (F_CARRY) {
		ZH++
	}
	ijmp ; call the calculation routine

CycleOvf:	; overflow occurred
	cbr rFlg, (1<<bCyc)|(1<<bOvf) ; clear cycle flag and overflow
	X = s_video_mem	; point to result buffer
	Z = TxtOvf16		; point to long message
	loop (rmp = 16) {
		r0 = prg[Z]
		Z++		; TODO !!! use [Z++]
		ram[X++] = r0
	}
	ret
.endproc	
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
.proc CycleM0
	rDiv1 = 0 ; for detecting an overflow in R5
	rDiv1.rRes4.rRes3.rRes2.rRes1 <<= 6		; * 64
	
	if (rDiv1 == 0) goto @ok
	rjmp CycleOvf
	
@ok:
	rcall Displ4Dec
	ram[X++] = rmp = ' '
	ram[X++] = rmp = 'H'
	ram[X++] = rmp = 'z'
	ram[X] = rmp = ' '
	rjmp DisplMode ('F')
.endproc

;
; Mode 1: Frequency measured, prescale = 1, display frequency
;
.proc CycleM1
	rDiv1 = 0 ; detect overflow in rDiv1
	rDiv1.rRes4.rRes3.rRes2.rRes1 <<= 2		; * 4
	if (rDiv1 == 0) goto @ok
	rjmp CycleOvf
@ok:
	rcall Displ4Dec
	ram[X++] = rmp = ' '
	ram[X++] = rmp = 'H'
	ram[X++] = rmp = 'z'
	ram[X] = rmp = ' '
	rjmp	DisplMode ('f')
.endproc
;
; Mode 2: Time measured, prescale = 1, display frequency
;
.proc CycleM2
	rcall Divide
	if (rRes4 != 0) goto @to_big
	rcall DisplFrac
	rcall DisplMode ('v')
	ret
@to_big:
	rRes3.rRes2.rRes1 = rRes4.rRes3.rRes2		; number too big, skip fraction
	rRes4 = 0
	rcall Displ4Dec
	ram[X++] = rmp = ' '
	ram[X++] = rmp = 'H'
	ram[X++] = rmp = 'z'
	ram[X] = rmp = ' '
	rcall DisplMode ('v')
	ret
.endproc
;
; Measure time, display rounds per minute
;
.proc CycleM3
	rcall Divide
	r0 = 0 ; overflow detection
	rmp = 0
	rRes4.rRes3.rRes2.rRes1 <<= 1		; * 2
	;r0 += rmp + F_CARRY
	;r0 = r0 + rmp + F_CARRY
	adc r0, rmp
	rRes4.rRes3.rRes2.rRes1 <<= 1		; * 4
	adc r0,rmp
	rDiv4.rDiv3.rDiv2.rDiv1 = rRes4.rRes3.rRes2.rRes1
	rRes4.rRes3.rRes2.rRes1 <<= 1		; * 8
	adc r0,rmp
	rRes4.rRes3.rRes2.rRes1 <<= 1		; * 16
	adc r0,rmp
	rRes4.rRes3.rRes2.rRes1 <<= 1		; * 32
	adc r0,rmp
	rRes4.rRes3.rRes2.rRes1 <<= 1		; * 64
	adc r0,rmp
	if (r0 != 0) {
		rjmp CycleOvf
	}
	rRes4.rRes3.rRes2.rRes1 -= rDiv4.rDiv3.rDiv2.rDiv1
	rRes3.rRes2.rRes1 = rRes4.rRes3.rRes2
	rRes4 = 0
	rcall Displ4Dec
	ram[X++] = rmp = ' '
	ram[X++] = rmp = 'r'
	ram[X++] = rmp = 'p'
	ram[X++] = rmp = 'm'
	rcall DisplMode ('u')
	ret
.endproc
;
; Measure time high+low, display time
;
.proc CycleM4
	rcall Multiply
	rcall Displ4Dec
	rcall DisplSec
	rcall DisplMode ('t')
	ret
.endproc

;
; Measure time high, display time
;
.proc CycleM5
	if (rFlg[bEdge]) {
		rcall Multiply
		rcall Displ4Dec
		rcall DisplSec
		rcall DisplMode ('h')
	}
	ret
.endproc
;
; Measure time low, display time
;
.proc CycleM6
	if (!rFlg[bEdge]) {
		rcall Multiply
		rcall Displ4Dec
		rcall DisplSec
		rcall DisplMode ('l')
	}
	ret
.endproc
;
; Measure time high and low, display pulse width ratio high in %
;   if the edge was negative, store the measured time, if positive calculate
;   rRes and rDiv hold the active low time, sCtr the last active high time
;   to CalcPw: rDelH:rDelL:R0:rmp = active high time
;
.proc CycleM7
	if (rFlg[bEdge]) {	; TODO !!!!! move Z = sCtr brefore this line !!!
		Z = sCtr			; edge is high, calculate
		rRes1 = ram[Z++]	; copy counter value
		rRes2 = ram[Z++]
		rRes3 = ram[Z++]
		rRes4 = ram[Z++]
		rDiv4.rDiv3.rDiv2.rDiv1 += rRes4.rRes3.rRes2.rRes1		; add to total time
		if (F_CARRY) goto @overflow
		rDelH.rDelL.r0.rmp = rRes4.rRes3.rRes2.rRes1				; copy high value to divisor
		rcall CalcPw ; calculate the ratio
		if (F_CARRY) goto @overflow
		rcall DisplPw ; display the ratio
		rjmp DisplMode ('P')
	}
	Z = sCtr
	ram[Z++] = rRes1 ; copy counter value
	ram[Z++] = rRes2
	ram[Z++] = rRes3
	ram[Z++] = rRes4
	ret
@overflow:
	rjmp PulseOvflw ('P')
.endproc
;
; Measure time high and low, display pulse width ratio low in %
;   if the edge was negative, store the measured time, if positive calculate
;   rRes and rDiv hold the active low time, sCtr the last active high time
;   to CalcPw: rDelH:rDelL:R0:rmp = active low time
;
.proc CycleM8
	if (rFlg[bEdge]) {		; TODO !!!!! move Z = sCtr brefore this line !!!
		Z = sCtr		; edge is high, calculate
		rmp = ram[Z++]	; read high-time
		r0 = ram[Z++]
		rDelL = ram[Z++]
		rDelH = ram[Z]
		rDiv4.rDiv3.rDiv2.rDiv1 += rDelH.rDelL.r0.rmp		; add to total time
		rDelH.rDelL.r0.rmp = rRes4.rRes3.rRes2.rRes1
		rcall CalcPw ; calculate the ratio
		if (F_CARRY) goto @overflow
		rcall DisplPw ; display the ratio
		rjmp DisplMode ('p')
	}
	Z = sCtr
	ram[Z++] = rRes1 ; copy counter value
	ram[Z++] = rRes2
	ram[Z++] = rRes3
	ram[Z++] = rRes4
	ret
@overflow:
	rjmp	PulseOvflw ('p')
.endproc	
;
; ===========================================
; Lcd display routines
; ===========================================
;
;
; LcdE pulses the E output for at least 1 us
;
LcdE:
	io[PORTB].bLcdE = 1
	.IF cFreq > 14000000
		nop
		nop
	.ENDIF
	.IF cFreq > 12000000
		nop
		nop
	.ENDIF
	.IF cFreq > 10000000
		nop
		nop
	.ENDIF
	.IF cFreq > 8000000
		nop
		nop
	.ENDIF
	.IF cFreq > 6000000
		nop
		nop
	.ENDIF
	.IF cFreq > 4000000
		nop
		nop
	.ENDIF
	.IF cFreq > 2000000
		nop
		nop
	.ENDIF
	nop
	nop
	io[PORTB].bLcdE = 0
	ret
;
; outputs the content of rmp (temporary 8-Bit-Interface during startup)
;
.proc LcdRs8 (val: rmp)
	io[PORTB] = val
	rcall LcdE		; TODO !!! rjmp
	ret
.endproc
;
; write rmp as 4-bit-command to the LCD
;
.proc LcdRs4 (val: rmp)
	r0 = rmp 			; copy rmp
	swap rmp 			; upper nibble to lower nibble
	rmp &= 0x0F 		; clear upper nibble
	io[PORTB] = rmp 	; write to display interface
	rcall LcdE 		; pulse E
	io[PORTB] = rmp = r0 & 0x0F ; copy original back and clear upper nibble
	rcall LcdE
	rmp = r0 ; restore rmp

	; TODO add delay 40 us here !!!
	ret
.endproc
;
; write rmp as data over 4-bit-interface to the LCD
;
.proc LcdData4 (val: r0)
	push	rmp
	rmp = r0
	swap	rmp 			; upper nibble to lower nibble
	rmp &= 0x0F 		; clear upper nibble
	rmp |= 1 << bLcdRs 	; set Rs to one
	io[PORTB] = rmp 	; write to display interface
	rcall LcdE 		; pulse E
	rmp = r0 & 0x0F 	; copy original again and clear upper nibble
	rmp |= 1 << bLcdRs	; set Rs to one
	io[PORTB] = rmp 	; write to display interface
	rcall LcdE
	rcall Delay40us
	pop rmp
	ret
.endproc
;
; writes the text in flash to the LCD, number of
; characters in rmp
;
.proc LcdText (len: r16)
	loop (len) {
		rcall	LcdData4 (prg[Z++])			; write to 
		rcall	delay40us
	}
	ret
.endproc
;
; Inits the LCD with a 4-bit-interface
;
LcdInit:
	io[DDRB] = rmp = 0x0F | (1<<bLcdE) | (1<<bLcdRs)
	io[PORTB] = rmp = 0
	rcall delay15ms ; wait for complete self-init
	rcall LcdRs8 (0x03)		; Function set 8-bit interface
	rcall delay4_1ms
	rcall LcdRs8 (0x03)		; Function set 8-bit interface
	rcall delay100us
	rcall LcdRs8 (0x03)		; Function set 8-bit interface
	rcall delay40us
	rcall LcdRs8 (0x02)		; Function set 4-bit-interface
	rcall delay40us
	rcall LcdRs4 (0x28)		; 4-bit-interface, two line display
	rcall delay40us
	rcall LcdRs4 (0x08)		; display off
	rcall delay40us
	rcall LcdRs4 (0x01)		; display clear
	rcall delay1_64ms
	rcall LcdRs4 (0x06)		; increment, don't shift
	rcall delay40us
	rcall LcdRs4 (0x0C)		; display on
	rcall delay40us
	rcall LcdRs4 (0x80)		; position on line 1
	rcall delay40us
	Z = LcdInitTxt16
	rcall LcdText (16)

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

	loop (rmp = 16) {
		rcall LcdData4 (ram[Z++])				; display on LCD
	}
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
	loop (rmp = 16) {
		rcall LcdData4 (ram[Z++])			; write r0 as data over 4-bit-interface to the LCD
	}
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
	sUartRxBp = rmp = LOW(sUartRxBs) 			; set buffer pointer to start
	io[UBRRH] = rmp = HIGH(cUbrr) 			; set URSEL to zero, set baudrate msb
	io[UBRRL] = rmp = LOW(cUbrr) 				; set baudrate lsb
	io[UCSRC] = rmp = (1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0) ; set 8 bit characters
	io[UCSRB] = rmp = (1<<RXCIE)|(1<<RXEN)|(1<<TXEN) ; enable RX/TX and RX-Ints
	rcall delay10ms ; delay for 10 ms duration
	rjmp UartSendTxt (txtUartInit)
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
	cbr rFlg, 1<<bUartRxLine ; clear line complete flag
	sUartRxBp = rmp = LOW(sUartRxBs) ; set buffer pointer to start
	Z = UartReturn
	push ZL ZH
	Z = sUartRxBs
	rmp = ram[Z++]			 ; read first character
	if (rmp == 'h') {		; help?
		rjmp @help
	}
	if (rmp == '?') {		; help?
		rjmp @help
	}
	if (rmp == 'U') {		; monitor U on
		rcall UartGetPar
		F_CARRY = 1
		rjmp @USetC
	}
	if (rmp == 'u') {		; monitor U off
		F_CARRY = 0
		rjmp @USetC
	}
	if (rmp == 'F') {		; monitor F on
		rcall UartGetPar
		F_CARRY = 1
		rjmp @FSetC
	}
	if (rmp == 'f') {		; monitor f off
		F_CARRY = 0
		rjmp @FSetC
	}
	if (rmp == 'p') {		; parameter?
		rjmp @param
	}
	Z = txtUartUnknown
	ret
@help:
	Z = txtUartHelp
	ret
@USetC:
	rmp = sUartFlag
	if (!F_CARRY) {
		cbr rmp, 1<<bUMonU ; clear flag
		sUartFlag = rmp
		Z = txtUartUOff
		ret
	}
	if (F_ZERO) {
		sUartMonURpt = r0
		sUartMonUCnt = r0
	}
	rmp |= 1<<bUMonU ; set flag
	sUartFlag = rmp
	Z = txtUartUOn
	ret
@FSetC:
	rmp = sUartFlag
	if (!F_CARRY) {
		cbr rmp, 1<<bUMonF ; clear flag
		sUartFlag = rmp
		Z = txtUartFOff
		ret
	}
	if (F_ZERO) {
		sUartMonFRpt = r0
		sUartMonFCnt = r0
	}
	rmp |= 1<<bUMonF ; set flag
	sUartFlag = rmp
	Z = txtUartFOn
	ret
@param:
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
	r0 = 0 			; result register
	rmp = ram[Z++]		; read char
	if (rmp == cCR) goto @no_param
	if (rmp == cLF) goto @no_param
	if (rmp != '=') goto @Err

	loop {
		rmp = ram[Z++]		; read next char
		if (rmp == cCR) break
		if (rmp == cLF) break
		rmp -= '0'
		if (F_CARRY) goto @Err
		if (rmp >= 10) goto @Err
		rir = r0
		r0 <<= 1 ; * 2
		if (F_CARRY) goto @Err
		r0 <<= 1 ; * 4
		if (F_CARRY) goto @Err
		r0 += rir ; * 5
		if (F_CARRY) goto @Err
		r0 <<= 1 ; * 10
		if (F_CARRY) goto @Err
		r0 += rmp ; add new decimal
		if (F_CARRY) goto @Err
	}

	F_ZERO = 1
	ret
@Err:
	rcall UartSendTxt (txtUartErr)
@no_param:
	F_ZERO = 0 ; No parameter set
	ret
.endproc
;
; Hex output over Uart, for debugging
;
.proc UartHexR (val: rmp)
	push	val
	swap	val
	rcall @send_nibble
	pop	val
@send_nibble:
	val &= 0x0F
	val += '0'
	if (val >= '9'+1) {
		val += 7
	}
	rjmp UartSendChar
	ret 			; TODO extra ret !!!
.endproc
;
; Return from Uart-Routines, displays text in Z
;
UartReturn:
	rcall UartSendTxt ; send text in Z
	rjmp UartSendTxt (txtUartCursor)
;
; Send character in rmp over Uart
;
.proc UartSendChar (char: rmp)
	if (!io[UCSRA].UDRE) goto UartSendChar		; wait for empty buffer
	io[UDR] = char
	ret
.endproc
;
; Monitoring the voltage over the Uart
;
.proc UartMonU
	rmp = sUartFlag ; flag register for Uart
	if (!rmp[bUMonU]) ret		; displays voltage over Uart
	sUartMonUCnt = rmp = sUartMonUCnt - 1 ; read counter
	if (!F_ZERO) goto @return
	sUartMonUCnt = rmp = sUartMonURpt
	Z = s_video_mem + 16
	loop (rmp = 8) {
		if (!io[UCSRA].UDRE) continue	; wait for empty buffer
		io[UDR] = r0 = ram[Z++]
	}
	rcall UartSendChar (cCR)
	rjmp UartSendChar (cLF)
@return:
	ret
.endproc

;
; Monitor frequency over UART
;
.proc UartMonF
	rmp = sUartFlag 			; flag register for Uart
	if (!rmp[bUMonF]) ret		; displays frequency over Uart
	sUartMonFCnt = rmp = sUartMonFCnt - 1	; read counter
	if (!F_ZERO) goto @return
	sUartMonFCnt = rmp = sUartMonFRpt
	Z = s_video_mem
	loop (rmp = 16) {
		if (!io[UCSRA].UDRE) continue	; wait for empty buffer
		io[UDR] = r0 = ram[Z++]
	}
	rcall UartSendChar (cCR)
	rjmp UartSendChar (cLF)
@return:
	ret
.endproc
;
; Send text from flash to UART, null byte ends transmit
;
.proc UartSendTxt (ptr: Z)
	r0 = prg[Z] ; read character from flash
	Z++	; TODO
	if (r0 != 0) {
@wait:
		if (!io[UCSRA].UDRE) goto @wait
		io[UDR] = r0 ; send char
		rjmp	UartSendTxt
	}
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
