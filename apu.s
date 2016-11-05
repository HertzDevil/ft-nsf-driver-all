;
; Updates the APU registers. x and y are free to use
;

.if 0
; Found this on nesdev bbs by blargg, 
; this can replace the volume table but takes a little more CPU
ft_get_volume:

	lda var_ch_VolColumn, x
	lsr a
	lsr a
	lsr a
	sta var_Temp
	lda var_ch_OutVolume, x
	sta var_Temp2

    lda var_Temp				; 4x4 multiplication
    lsr var_Temp2
    bcs :+
    lsr a
:   lsr var_Temp2
    bcc :+
    adc var_Temp
:   lsr a
    lsr var_Temp2
    bcc :+
    adc var_Temp
:   lsr a
    lsr var_Temp2
    bcc :+
    adc var_Temp
:   lsr a
	beq :+
	rts
:	lda var_Temp
	ora var_ch_OutVolume, x
	beq :+
	lda #$01					; Round up to 1
:	rts
.endif

ft_update_apu:
	lda var_PlayerFlags
	bne @Play
	lda #$00					; Kill all channels
	sta $4015
	rts
@KillSweepUnit:					; Reset sweep unit to avoid strange problems
	lda #$C0
	sta $4017
	lda #$40
	sta $4017
	rts
@Play:

	;
	; Square 1
	;
	lda var_Channels
	and #$01
	bne :+
	jmp @Square2
:
	lda var_ch_Note				; Kill channel if note = off
	beq @KillSquare1
	
	; Calculate volume
.if 0
	ldx #$00
	jsr ft_get_volume
	beq @KillSquare1
.endif
	; Calculate volume	
	lda var_ch_VolColumn + 0		; Kill channel if volume column = 0
	asl a
	and #$F0
	beq @KillSquare1
	sta var_Temp
	lda var_ch_OutVolume + 0
	beq @KillSquare1
	ora var_Temp
	tax
	lda ft_volume_table, x

	; Write to registers
	pha 
	lda var_ch_DutyCycle
	and #$03
	tax
	pla
	ora ft_duty_table, x		; Add volume
	ora #$30					; And disable length counter and envelope
	sta $4000
	; Period table isn't limited to $7FF anymore
	lda var_ch_TimerCalculated + EFF_CHANS
	and #$F8
	beq @TimerOverflow1
	lda #$07
	sta var_ch_TimerCalculated + EFF_CHANS
	lda #$FF
	sta var_ch_TimerCalculated
@TimerOverflow1:
	
	lda var_ch_Sweep 			; Check if sweep is active
	beq @NoSquare1Sweep
	and #$80
	beq @Square2				; See if sweep is triggered, if then don't touch sound registers until next note

	lda var_ch_Sweep 			; Trigger sweep
	sta $4001
	and #$7F
	sta var_ch_Sweep
	
	lda var_ch_TimerCalculated
	sta $4002
	lda var_ch_TimerCalculated + EFF_CHANS
	sta $4003

	lda #$FF
	sta var_ch_PrevFreqHigh
	
;	jsr @KillSweepUnit
	jmp @Square2

@KillSquare1:
	lda #$30
	sta $4000
	jmp @Square2
	
@NoSquare1Sweep:				; No Sweep
	lda #$08
	sta $4001
	jsr @KillSweepUnit
	lda var_ch_TimerCalculated
	sta $4002
	lda var_ch_TimerCalculated + EFF_CHANS
	cmp var_ch_PrevFreqHigh
	beq @SkipHighPartSq1
	sta $4003
	sta var_ch_PrevFreqHigh
@SkipHighPartSq1:
;	jmp @Square2

	;
	; Square 2
	;
@Square2:
	lda var_Channels
	and #$02
	bne :+
	jmp @Triangle
:
	lda var_ch_Note + 1
	beq @KillSquare2
	
	.if 1
	; Calculate volume	
	lda var_ch_VolColumn + 1		; Kill channel if volume column = 0
	asl a
	and #$F0
	beq @KillSquare2
	sta var_Temp
	lda var_ch_OutVolume + 1
	beq @KillSquare2
	ora var_Temp
	tax
	lda ft_volume_table, x
	.endif

	.if 0	
	ldx #$01
	jsr ft_get_volume
	beq @KillSquare2
	.endif
	
	; Write to registers
	pha 
	lda var_ch_DutyCycle + 1
	and #$03
	tax
	pla
	ora ft_duty_table, x
	ora #$30
	sta $4004
	; Period table isn't limited to $7FF anymore
	lda var_ch_TimerCalculated + 1 + EFF_CHANS
	and #$F8
	beq @TimerOverflow2
	lda #$07
	sta var_ch_TimerCalculated + 1 + EFF_CHANS
	lda #$FF
	sta var_ch_TimerCalculated + 1
@TimerOverflow2:
	
	lda var_ch_Sweep + 1		; Check if there should be sweep 
	beq @NoSquare2Sweep
	and #$80
	beq @Triangle				; See if sweep is triggered
	lda var_ch_Sweep + 1		; Trigger sweep
	sta $4005
	and #$7F
	sta var_ch_Sweep + 1
	lda #$FF
	sta var_ch_PrevFreqHigh + 1
	lda var_ch_TimerCalculated + 1	; Could this be done by that below? I don't know
	sta $4006
	lda var_ch_TimerCalculated + EFF_CHANS + 1
	sta $4007
;	jsr @KillSweepUnit
	jmp @Triangle
@NoSquare2Sweep:				; No Sweep
	lda #$08
	sta $4005
	jsr @KillSweepUnit
	lda var_ch_TimerCalculated + 1
	sta $4006
	lda var_ch_TimerCalculated + EFF_CHANS + 1
	cmp var_ch_PrevFreqHigh + 1
	beq @SkipHighPartSq2
	sta $4007
	sta var_ch_PrevFreqHigh + 1
@SkipHighPartSq2:
	jmp @Triangle
@KillSquare2:
	lda #$30
	sta $4004

@Triangle:
	lda var_Channels
	and #$04
	beq @Noise
	;
	; Triangle
	;
	lda var_ch_Volume + 2
	beq @KillTriangle
	lda var_ch_Note + 2
	;ora var_ch_Note + 2
	beq @KillTriangle
	lda #$81
	sta $4008
	; Period table isn't limited to $7FF anymore
	lda var_ch_TimerCalculated + 2 + EFF_CHANS
	and #$F8
	beq @TimerOverflow3
	lda #$07
	sta var_ch_TimerCalculated + 2 + EFF_CHANS
	lda #$FF
	sta var_ch_TimerCalculated + 2
@TimerOverflow3:	
;	lda #$08
;	sta $4009
	lda var_ch_TimerCalculated + 2
	sta $400A
	lda var_ch_TimerCalculated + EFF_CHANS + 2
	sta $400B
	jmp @SkipTriangleKill
@KillTriangle:
	lda #$00
	sta $4008
@SkipTriangleKill:

	;
	; Noise
	;
@Noise:
	lda var_Channels
	and #$08
	beq @DPCM
		
	lda var_ch_Note + 3
	beq @KillNoise
	; Calculate volume
	.if 1
	lda var_ch_VolColumn + 3		; Kill channel if volume column = 0
	asl a
	and #$F0
	sta var_Temp
	beq @KillNoise
	lda var_ch_OutVolume + 3
	beq @KillNoise
	ora var_Temp
	tax
	lda ft_volume_table, x
	.endif
;	ldx #$03
;	jsr ft_get_volume
;	beq @KillNoise

	; Write to registers
	ora #$30
	sta $400C
	lda #$00
	sta $400D
	lda var_ch_DutyCycle + 3
;	and #$01
	ror a
	ror a
	and #$80
	sta var_Temp
	lda var_ch_TimerCalculated + 3
	and #$0F
	ora var_Temp
	eor #$0F
	sta $400E
	lda #$00
	sta $400F
	beq @DPCM
@KillNoise:
	lda #$30
	sta $400C
@DPCM:
	;
	; DPCM
	;
.ifdef USE_DPCM
	lda var_Channels
	and #$10
	beq @Return
	
	lda var_ch_DPCM_Retrig			; Retrigger
	beq :+
	dec var_ch_DPCM_RetrigCntr
	bne :+
	sta var_ch_DPCM_RetrigCntr
	lda #$01
	sta var_ch_Note + DPCM_CHANNEL
:
	
	lda var_ch_DPCMDAC				; See if delta counter should be updated
	bmi @SkipDAC
	sta $4011
@SkipDAC:
	lda #$80						; Skip that later by storing a negative value
	sta var_ch_DPCMDAC
	lda var_ch_Note + DPCM_CHANNEL
	beq @KillDPCM
	bmi @SkipDPCM
	lda var_ch_SamplePitch
	sta $4010
	
	clc
	lda var_ch_SamplePtr
	adc var_ch_DPCM_Offset
	sta $4012

	lda var_ch_DPCM_Offset
	asl a
	asl a
	sta var_Temp
	sec
	lda var_ch_SampleLen
	sbc var_Temp
	sta $4013
	lda #$80
	sta var_ch_Note + DPCM_CHANNEL
	lda #$0F
	sta $4015
	lda #$1F
	sta $4015
@SkipDPCM:
	rts
@KillDPCM:
	lda #$0F
	sta $4015
.endif
@Return:
	rts

; Lookup tables

ft_duty_table:
	.byte $00, $40, $80, $C0

; Volume table: (column volume) * (instrument volume)
ft_volume_table:
	.byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.byte 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
	.byte 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2 
 	.byte 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3 
 	.byte 0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4 
 	.byte 0, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5 
 	.byte 0, 1, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4, 5, 5, 6 
 	.byte 0, 1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7 
 	.byte 0, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 8 
 	.byte 0, 1, 1, 1, 2, 3, 3, 4, 4, 5, 6, 6, 7, 7, 8, 9 
 	.byte 0, 1, 1, 2, 2, 3, 4, 4, 5, 6, 6, 7, 8, 8, 9, 10 
 	.byte 0, 1, 1, 2, 2, 3, 4, 5, 5, 6, 7, 8, 8, 9, 10, 11 
 	.byte 0, 1, 1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 11, 12 
 	.byte 0, 1, 1, 2, 3, 4, 5, 6, 6, 7, 8, 9, 10, 11, 12, 13 
 	.byte 0, 1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 
 	.byte 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 
