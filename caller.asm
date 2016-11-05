
.ifndef DRIVER
	PLAY = $8888
	INIT = $9999
.endif

.segment "CODE"

;
; Following code is from Nullsleep's guide
;
RESET:
	cld			; clear decimal flag
	sei			; disable interrupts
	lda #%00000000		; disable vblank interrupts by clearing
	sta $2000		; the most significant bit of $2000
;	sta $2001
WaitV1:	
	lda $2002		; give the PPU a little time to initialize
	bpl WaitV1		; by waiting for a vblank
WaitV2:	
	lda $2002		; wait for a second vblank to be safe
	bpl WaitV2		; and now the PPU should be initialized
	lda #$00				; Clear RAM
	ldx #$FF
CLEAR_RAM:
	sta $0000, x
	sta $0100, x
	sta $0200, x
	sta $0300, x
	sta $0400, x
	sta $0500, x
	sta $0600, x
	sta $0700, x
	dex
	bne CLEAR_RAM	
; *** CLEAR SOUND REGISTERS ***
	lda #$00		; clear all the sound registers by setting
	ldx #$00		; everything to 0 in the Clear_Sound loop
Clear_Sound:
	sta $4000,x		; store accumulator at $4000 offset by x
	inx			; increment x
	cpx #$0F		; compare x to $0F
	bne Clear_Sound		; branch back to Clear_Sound if x != $0F
	lda #$10		; load accumulator with $10
	sta $4010		; store accumulator in $4010
	lda #$00		; load accumulator with 0
	sta $4011		; clear these 3 registers that are 
	sta $4012		; associated with the delta modulation
	sta $4013		; channel of the NES
; *** ENABLE SOUND CHANNELS ***
	lda #%00001111		; enable all sound channels except
	sta $4015		; the delta modulation channel
; *** RESET FRAME COUNTER AND CLOCK DIVIDER ***
	lda #$C0		; synchronize the sound playback routine 
	sta $4017		; to the internal timing of the NES
; *** SET SONG # & PAL/NTSC SETTING ***
	lda #$00		; replace dashes with song number
	ldx #$00
	jsr INIT
; *** ENABLE VBLANK NMI ***
	lda #%10000000		; enable vblank interrupts by setting the 
	sta $2000		; most significant bit of $2000
Loop:
	jmp Loop		; loop loop loop loop ...		
NMI:
	lda $2002		; read $2002 to reset the vblank flag
	lda #%00000000		; clear the first PPU control register  
	sta $2000		; writing 0 to it
	lda #%10000000		; reenable vblank interrupts by setting
	sta $2000		; the most significant bit of $2000
	jsr PLAY
	;-------------extra
	
	.if 0
	
	;read controller
	lda #$01
	sta $4016
	lda #$00
	sta $4016

	lda $4016
	and #$01
	bne reset_song

	lda $4016
	and #$01
	bne kill_song

	lda $4016
	and #$01
	bne ppu_on
	lda $4016
	and #$01
	bne ppu_off
	rti
reset_song:
	lda #$00		; replace dashes with song number
	ldx #$00
	jsr INIT
	rti
kill_song:
	lda #$00		; replace dashes with song number
	sta mdv_playing
	sta $4015
	rti
ppu_on:
	lda #$18
	sta $2001
	rti
ppu_off:
	lda #$00
	sta $2001
	rti
	;--------------------
	
	.endif
	
IRQ:
	rti			; return from interrupt routine
	.segment "VECTORS"
	.word NMI, RESET, IRQ
