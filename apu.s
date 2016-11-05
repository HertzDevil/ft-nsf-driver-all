;
; Updates the APU registers. x and y are free!
;
ft_update_apu:
	lda var_Flags
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
	lda var_ch_Note				; Kill channel if note = off
	beq @KillSquare1
	lda var_ch_VolumeOffset		; Kill channel if volume column = 0
	cmp #$0F
	beq @KillSquare1
	lda var_ch_OutVolume		; Kill channel if volume = 0
	beq @KillSquare1
	clc							; Calculate volume to A, set carry to remove one more
	sbc var_ch_VolumeOffset
	bpl @SkipVol1Clear
	lda #$00
@SkipVol1Clear:
	clc
	adc #$01					; And add one more, this is because volume always will round off to 1 (as reqested)
	;ldx var_ch_DutyCycle		; Get the duty cycle setting
	pha 
	lda var_ch_DutyCycle
	and #$03
	tax
	pla
	ora ft_duty_table, x		; Add volume
	ora #$30					; And disable length counter and envelope
	sta $4000
	lda var_ch_Sweep 			; Check if sweep is used
	beq @NoSquare1Sweep
	and #$80
	beq @Square2				; See if sweep is triggered
	lda var_ch_Sweep 			; Trigger sweep
	sta $4001
	and #$7F
	sta var_ch_Sweep
	lda #$FF
	sta var_ch_PrevFreqHigh
	lda var_ch_FreqCalculated	; Could this be done by that below? I don't know
	sta $4002
	lda var_ch_FreqCalculated + 4
	sta $4003
	jsr @KillSweepUnit
	jmp @Square2
@NoSquare1Sweep:				; No Sweep
	lda #$08
	sta $4001
	jsr @KillSweepUnit
	lda var_ch_FreqCalculated
	sta $4002
	lda var_ch_FreqCalculated + 4
	cmp var_ch_PrevFreqHigh
	beq @SkipHighPartSq1
	sta $4003
	sta var_ch_PrevFreqHigh
@SkipHighPartSq1:
	jmp @Square2
@KillSquare1:
	lda #$30
	sta $4000
	;
	; Square 2
	;
@Square2:
	lda var_ch_Note + 1
	beq @KillSquare2
	lda var_ch_VolumeOffset + 1	; Kill channel if volume column = 0
	cmp #$0F
	beq @KillSquare2
	lda var_ch_OutVolume + 1
	beq @KillSquare2
	clc							; Calculate volume to A, see channel 1
	sbc var_ch_VolumeOffset + 1
	bpl @SkipVol2Clear
	lda #$00
@SkipVol2Clear:
	clc
	adc #$01					; And add one more, this is because volume always will round off to 1 (as reqested)
	;ldx var_ch_DutyCycle + 1
	pha 
	lda var_ch_DutyCycle + 1
	and #$03
	tax
	pla
	ora ft_duty_table, x
	ora #$30
	sta $4004
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
	lda var_ch_FreqCalculated + 1	; Could this be done by that below? I don't know
	sta $4006
	lda var_ch_FreqCalculated + 5
	sta $4007
	jsr @KillSweepUnit
	jmp @Triangle
@NoSquare2Sweep:				; No Sweep
	lda #$08
	sta $4005
	jsr @KillSweepUnit
	lda var_ch_FreqCalculated + 1
	sta $4006
	lda var_ch_FreqCalculated + 5
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
	;
	; Triangle
	;
	lda var_ch_Volume + 2
	beq @KillTriangle
	lda var_ch_Note + 2
	beq @KillTriangle
	lda #$FF
	sta $4008
	lda #$08
	sta $4009
	lda var_ch_FreqCalculated + 2
	sta $400A
	lda var_ch_FreqCalculated + 6
	sta $400B
	jmp @SkipTriangleKill
@KillTriangle:
	lda #$00
	sta $4008
@SkipTriangleKill:
	;
	; Noise
	;
	lda var_ch_Note + 3
	beq @KillNoise
	sec							; Calculate volume to A
	lda var_ch_OutVolume + 3
	sbc var_ch_VolumeOffset + 3
	bpl @SkipVol3Clear
	lda #$00
@SkipVol3Clear:
	ora #$30
	sta $400C
	lda #$00
	sta $400D
	lda var_ch_DutyCycle + 3
	and #$01
	ror a
	ror a
	and #$80
	sta var_Temp
	lda var_ch_FreqCalculated + 3
	and #$0F
	ora var_Temp
	;and #$8F
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
	lda var_ch_DPCMDAC				; See if delta counter should be updated
	bmi @SkipDAC
	sta $4011
@SkipDAC:
	lda #$80						; Skip that later by storing a negative value
	sta var_ch_DPCMDAC
	lda var_ch_Note + 4
	beq @KillDPCM
	bmi @SkipDPCM
	lda var_ch_SamplePitch
	sta $4010
	
	clc
	lda var_ch_SamplePtr
	adc var_ch_DPCM_Offset
	sta $4012

	lda var_ch_DPCM_Offset
	lsr a
	lsr a
	sta var_Temp
	sec
	lda var_ch_SampleLen
	sbc var_Temp
	sta $4013
	lda #$80
	sta var_ch_Note + 4
	lda #$0F
	sta $4015
	lda #$1F
	sta $4015
@SkipDPCM:
	rts
@KillDPCM:
	lda #$0F
	sta $4015
	rts

; Lookup table
ft_duty_table:
	.byte $00, $40, $80, $C0
	