;
; Update track effects
;
ft_run_effects:

	; Volume slide
	lda var_ch_VolSlide, x
	beq @NoVolSlide
	; First calculate volume decrease
	lda var_ch_VolSlide, x
	and #$0F
	sta var_Temp
	sec
	lda var_ch_VolColumn, x
	sbc var_Temp
	bpl :+
	lda #$00
:	sta var_ch_VolColumn, x
	lda var_ch_VolSlide, x
	lsr a
	lsr a
	lsr a
	lsr a
	sta var_Temp
	clc
	lda var_ch_VolColumn, x
	adc var_Temp
	bpl :+
	lda #$7F
:	sta var_ch_VolColumn, x
@NoVolSlide:

	; Arpeggio and portamento
	lda var_ch_Effect, x
	beq @NoEffect
	cmp #EFF_ARPEGGIO
	beq @EffArpeggio
	cmp #EFF_PORTAMENTO
	beq @EffPortamento
	cmp #EFF_PORTA_UP
	beq @EffPortaUp
	cmp #EFF_SLIDE_UP
	beq @EffSlideUp
	cmp #EFF_SLIDE_DOWN
	beq @EffSlideDown
	
	cmp #EFF_SLIDE_UP_LOAD
	beq @EffLoadSlide
	cmp #EFF_SLIDE_DOWN_LOAD
	beq @EffLoadSlide

	jmp ft_portamento_down

@EffArpeggio:
	jmp ft_arpeggio
@EffPortamento:
	jmp ft_portamento
@EffPortaUp:
	jmp ft_portamento_up
@EffSlideUp:
	jmp	ft_slide_up
@EffSlideDown:
	jmp	ft_slide_down
@EffLoadSlide:
	jmp ft_load_slide
@NoEffect:

ft_post_effects:
	rts

ft_load_slide:
	lda var_ch_TimerPeriod, x
	pha
	lda var_ch_TimerPeriod + WAVE_CHANS, x
	pha
	; Load note
	lda var_ch_EffParam, x			; Store speed
	and #$0F						; Get note
	sta var_Temp					; Store note in temp
	
	lda var_ch_Effect, x
	cmp #EFF_SLIDE_UP_LOAD
	beq @aa
	lda var_ch_Note, x
	sec
	sbc var_Temp	
	jmp @bb
@aa:
	lda var_ch_Note, x
	clc
	adc var_Temp
@bb:

	sta var_ch_Note, x
	jsr	ft_translate_freq_only
	lda var_ch_TimerPeriod, x
	sta var_ch_PortaTo, x
	lda var_ch_TimerPeriod + WAVE_CHANS, x
	sta var_ch_PortaTo + WAVE_CHANS, x
	; Store speed
	lda var_ch_EffParam, x
	lsr a
	lsr a
	lsr a
	ora #$01
	sta var_ch_EffParam, x
	; Load new period
	pla
	sta var_ch_TimerPeriod + WAVE_CHANS, x
	pla
	sta var_ch_TimerPeriod, x
	; change mode to sliding
	clc
	lda var_ch_Effect, x
	adc #01
	sta var_ch_Effect, x
	rts

ft_calc_freq:

 	; Apply fine pitch
 	lda var_ch_FinePitch, x
 	cmp #$80
 	beq @SkipFinePitch
	clc
	lda var_ch_TimerPeriod, x
	adc #$80
	sta var_ch_TimerCalculated, x
	lda var_ch_TimerPeriod + WAVE_CHANS, x
	adc #$00
	sta var_ch_TimerCalculated + WAVE_CHANS, x
	sec
	lda var_ch_TimerCalculated, x
	sbc var_ch_FinePitch, x
	sta var_ch_TimerCalculated, x
	lda var_ch_TimerCalculated + WAVE_CHANS, x
	sbc #$00
	sta var_ch_TimerCalculated + WAVE_CHANS, x
	jmp @DoTheRest
@SkipFinePitch:
	lda var_ch_TimerPeriod, x
	sta var_ch_TimerCalculated, x
	lda var_ch_TimerPeriod + WAVE_CHANS, x
	sta var_ch_TimerCalculated + WAVE_CHANS, x
@DoTheRest:

	jsr ft_vibrato
	jsr ft_tremolo
	rts

	
;
; Portamento
;
ft_portamento:
	lda var_ch_EffParam, x						; Check portamento, if speed > 0
	beq @NoPortamento
	lda var_ch_PortaTo, x						; and if freq > 0, else stop
	ora var_ch_PortaTo + WAVE_CHANS, x
	beq @NoPortamento
	lda var_ch_TimerPeriod + WAVE_CHANS, x		; Compare high byte
	cmp var_ch_PortaTo + WAVE_CHANS, x
	bcc @Increase
	bne @Decrease
	lda var_ch_TimerPeriod, x						; Compare low byte
	cmp var_ch_PortaTo, x
	bcc @Increase
	bne @Decrease
	;rts										; done
	jmp ft_post_effects
@Decrease:										; Decrease frequency
	sec
	lda var_ch_TimerPeriod, x
	sbc var_ch_EffParam, x
	sta var_ch_TimerPeriod, x
	lda var_ch_TimerPeriod + WAVE_CHANS, x
	sbc #$00
	sta var_ch_TimerPeriod + WAVE_CHANS, x
	; Check if sign bit has changed, if so load the desired frequency
	lda var_ch_TimerPeriod + WAVE_CHANS, x		; Compare high byte
	cmp var_ch_PortaTo + WAVE_CHANS, x
	bcc @LoadFrequency
	bmi @LoadFrequency
	bne @NoPortamento
	lda var_ch_TimerPeriod, x						; Compare low byte
	cmp var_ch_PortaTo, x
	bcc @LoadFrequency
;	rts											; Portamento is done at this point
	jmp ft_post_effects

@Increase:										; Increase frequency
	clc
	lda var_ch_TimerPeriod, x
	adc var_ch_EffParam, x
	sta var_ch_TimerPeriod, x
	lda var_ch_TimerPeriod + WAVE_CHANS, x
	adc #$00
	sta var_ch_TimerPeriod + WAVE_CHANS, x
	; Check if sign bit has changed, if so load the desired frequency
	lda var_ch_PortaTo + WAVE_CHANS, x			; Compare high byte
	cmp var_ch_TimerPeriod + WAVE_CHANS, x
	bcc @LoadFrequency
	bne @NoPortamento
	lda var_ch_PortaTo, x						; Compare low byte
	cmp var_ch_TimerPeriod, x
	bcc @LoadFrequency
;	rts
	jmp ft_post_effects

@LoadFrequency:									; Load the correct frequency
	lda var_ch_PortaTo, x
	sta var_ch_TimerPeriod, x
	lda var_ch_PortaTo + WAVE_CHANS, x
	sta var_ch_TimerPeriod + WAVE_CHANS, x
@NoPortamento:
	jmp ft_post_effects

ft_portamento_up:
	sec
	lda var_ch_TimerPeriod, x
	sbc var_ch_EffParam, x
	sta var_ch_TimerPeriod, x
	lda var_ch_TimerPeriod + WAVE_CHANS, x
	sbc #$00
	sta var_ch_TimerPeriod + WAVE_CHANS, x
	jsr ft_limit_freq
	jmp ft_post_effects
ft_portamento_down:
	clc
	lda var_ch_TimerPeriod, x
	adc var_ch_EffParam, x
	sta var_ch_TimerPeriod, x
	lda var_ch_TimerPeriod + WAVE_CHANS, x
	adc #$00
	sta var_ch_TimerPeriod + WAVE_CHANS, x	
	jsr ft_limit_freq
	jmp ft_post_effects
	
;
; Note slide
;
ft_slide_up:
	sec
	lda var_ch_TimerPeriod, x
	sbc var_ch_EffParam, x
	sta var_ch_TimerPeriod, x
	lda var_ch_TimerPeriod + WAVE_CHANS, x
	sbc #$00
	sta var_ch_TimerPeriod + WAVE_CHANS, x
	cmp var_ch_PortaTo + WAVE_CHANS, x
	bcc ft_slide_done
	bne ft_slide_not_done
	lda var_ch_TimerPeriod, x						; Compare low byte
	cmp var_ch_PortaTo, x
	bcc ft_slide_done
	jmp ft_post_effects
ft_slide_down:
	clc
	lda var_ch_TimerPeriod, x
	adc var_ch_EffParam, x
	sta var_ch_TimerPeriod, x
	lda var_ch_TimerPeriod + WAVE_CHANS, x
	adc #$00
	sta var_ch_TimerPeriod + WAVE_CHANS, x
	cmp var_ch_PortaTo + WAVE_CHANS, x			; Compare high byte
	bcc ft_slide_done
	bne ft_slide_not_done
	lda var_ch_PortaTo, x						; Compare low byte
	cmp var_ch_TimerPeriod, x
	bcc ft_slide_done
	jmp ft_post_effects
ft_slide_done:
	lda var_ch_PortaTo, x
	sta var_ch_TimerPeriod, x
	lda var_ch_PortaTo + WAVE_CHANS, x
	sta var_ch_TimerPeriod + WAVE_CHANS, x
	lda #$00									; Reset effect
	sta var_ch_Effect, x
ft_slide_not_done:
	jmp ft_post_effects

;
; Arpeggio
;
ft_arpeggio:
	lda var_ch_ArpeggioCycle, x
	cmp #$01
	beq @LoadSecond
	cmp #$02
	beq @LoadThird
	lda var_ch_Note, x							; Load first note
	jsr ft_translate_freq_only
	inc var_ch_ArpeggioCycle, x
	jmp ft_post_effects
@LoadSecond:									; Second note (second nybble)
	lda var_ch_EffParam, x
	lsr a
	lsr a
	lsr a
	lsr a
	clc
	adc var_ch_Note, x
	jsr ft_translate_freq_only
	lda var_ch_EffParam, x						; see if cycle should reset here
	and #$0F
	bne @DoNextStep
	sta var_ch_ArpeggioCycle, x
	jmp ft_post_effects
@DoNextStep:
	inc var_ch_ArpeggioCycle, x
	jmp ft_post_effects
@LoadThird:										; Third note (first nybble)
	lda var_ch_EffParam, x
	and #$0F
	clc
	adc var_ch_Note, x
	jsr ft_translate_freq_only	
	lda #$00
	sta var_ch_ArpeggioCycle, x
	jmp ft_post_effects
	
;
; Vibrato. ** This is CPU intensive, optimize!! **
;
ft_vibrato:
	lda var_ch_VibratoSpeed, x
	bne @DoVibrato
	rts
@DoVibrato:
	clc
	adc var_ch_VibratoPos, x
	and #$3F
	sta var_ch_VibratoPos, x
	
	ldy var_ch_VibratoPos, x
	lda ft_sine, y
	pha
	lda var_ch_VibratoParam, x
	and #$0F
	lsr a
	sta var_Temp
	sec
	lda #$07
	sbc var_Temp
	tay
	pla
	cpy #$00
	beq @NoVibratoIteration
@VibratoIteration:
	lsr a
	dey
	bne @VibratoIteration
@NoVibratoIteration:
	sta var_Temp
	lda var_ch_VibratoParam, x
	and #$01
	bne @VibratoMoreDec
	lda var_Temp
	pha
	lsr a
	sta var_Temp
	sec
	pla
	sbc var_Temp
	sta var_Temp
@VibratoMoreDec:
	sec
	lda var_ch_TimerCalculated, x
	sbc var_Temp
	sta var_ch_TimerCalculated, x
	lda var_ch_TimerCalculated + WAVE_CHANS, x
	sbc #$00
	sta var_ch_TimerCalculated + WAVE_CHANS, x
	rts

;
; Tremolo
;
ft_tremolo:
	lda var_ch_TremoloSpeed, x
	bne @DoTremolo
	lda var_ch_Volume, x
	sta var_ch_OutVolume, x	
	rts
@DoTremolo:

	clc
	adc var_ch_TremoloPos, x
	and #$3F
	sta var_ch_TremoloPos, x
	
	ldy var_ch_TremoloPos, x
	lda ft_sine, y
	pha
	lda var_ch_TremoloParam, x
	and #$0F
	lsr a
	sta var_Temp
	sec
	lda #$07
	sbc var_Temp
	tay
	pla
	cpy #$00
	beq @NoTremoloIteration
@TremoloIteration:
	lsr a
	dey
	bne @TremoloIteration
@NoTremoloIteration:
	sta var_Temp
	lda var_ch_TremoloParam, x
	and #$01
	bne @TremoloMoreDec
	lda var_Temp
	pha
	lsr a
	sta var_Temp
	sec
	pla
	sbc var_Temp
	sta var_Temp
@TremoloMoreDec:
	sec
	lda var_ch_Volume, x
	sbc var_Temp
	bmi :+
	sta var_ch_OutVolume, x
	rts
:	lda #$00
	sta var_ch_OutVolume, x
	rts
