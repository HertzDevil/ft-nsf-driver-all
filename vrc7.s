
ft_translate_note_vrc7:
	
	; Calculate Fnum & Bnum
	
	; Input: A = note + 1
	; Result: EXT = Fnum index, ACC = Bnum

;	sec
;	sbc #$01
	sta ACC
	
	lda #12
	sta AUX

	lda #$00
	sta ACC + 1
	sta AUX + 1

	jsr DIV

	;lda ACC
	;asl a
	;sta ACC
;	asl ACC

	rts

; VRC7 commands
;  0 = halt
;  1 = trigger
;  80 = update

ft_clear_vrc7:
	clc
	txa
	adc #$20	; $20: Clear channel
	sta $9010
	lda var_Period + 1
	;	lda #$00
	ora var_ch_Bnum, x
	sta $9030	
	rts

; Update all VRC7 channels
ft_update_vrc7:

	lda var_PlayerFlags
	bne @Play
	; Close all channels
	ldx #$06
:	txa
	clc
	adc #$1F
	sta $9010
	lda #$00
	sta $9030
	dex
	bne :-
	rts
@Play:

	ldx #$00					; x = channel
@LoopChannels:

.if 0
	lda var_ch_Command, x
	bne :+
	; Kill channel
	jsr ft_vrc7_effects
	jsr ft_clear_vrc7
	jmp @NextChan
:
.endif

	lda var_ch_Command, x
	beq @UpdateChannel
	
	; Retrigger channel
	lda var_ch_ActiveNote, x
	jsr ft_translate_note_vrc7
	ldy EXT	; note index -> y

	lda ft_note_table_vrc7_l, y
	sta var_ch_Fnum, x
	lda ft_note_table_vrc7_h, y
	sta var_ch_Fnum + 6, x

;	lda ACC
;	sta var_ch_Bnum, x
	
	lda var_ch_Command, x
	bmi @UpdateChannel				; Jump if command = 80

	; Retrigger channel
	jsr ft_clear_vrc7

;	lda var_ch_Command
;	beq @UpdateChannel
	lda #$80
	sta var_ch_Command, x

@UpdateChannel:	

	;jsr ft_vrc7_effects

	; Load VRC7 Fnum value and shift down two steps
	lda var_ch_Effect + VRC7_CHANNEL, x
	cmp #EFF_PORTAMENTO
	bne :+
	lda var_ch_EffParam + VRC7_CHANNEL, x
	beq :+
	lda var_ch_TimerPeriod + VRC7_CHANNEL, x
	cmp var_ch_PortaTo + VRC7_CHANNEL, x
	bne :+
	lda var_ch_TimerPeriod + VRC7_CHANNEL + EFF_CHANS, x
	cmp var_ch_PortaTo + VRC7_CHANNEL + EFF_CHANS, x
	bne :+
	jsr ft_vrc7_get_freq_only
:

	lda var_ch_TimerCalculated + VRC7_CHANNEL, x
	sta var_Period
	lda var_ch_TimerCalculated + VRC7_CHANNEL + EFF_CHANS, x
	sta var_Period + 1

	lsr var_Period + 1
	ror var_Period
	lsr var_Period + 1
	ror var_Period

	clc
	txa
	adc #$10	; $10: Low part of Fnum
	sta $9010
	lda var_Period
	sta $9030

	; Note on or off
	lda #$00
	sta var_Temp2
	lda var_ch_Command, x
	beq :+
	; Check release
	lda var_ch_State + VRC7_CHANNEL, x
	and #$01
	tay
	lda ft_vrc7_cmd, y
	sta var_Temp2
:
	clc
	txa
	adc #$20	; $20: High part of Fnum, Bnum, Note on & sustain on
	sta $9010
	lda var_ch_Bnum, x
	asl a
	ora var_Period + 1
	;ora #$30	; Note on | sustain on
	ora var_Temp2
	sta $9030

	clc
	txa
	adc #$30	; $30: Patch & Volume
	sta $9010
	lda var_ch_VolColumn + VRC7_CHANNEL, x
	lsr a
	lsr a
	lsr a
	eor #$0F
	ora var_ch_Patch, x
	sta $9030
	
	; Leave channel on
;	lda var_ch_Command, x
;	beq @NextChan
;	lda #$80
;	sta var_ch_Command, x
	
@NextChan:
	inx
	cpx #$06
	beq :+
	jmp @LoopChannels
:
	rts

; Update vrc7 channel effects, and load frequency -> var_Period
ft_vrc7_effects:
	.if 0
	lda #$00
	sta var_Temp16
	sta var_Temp16 + 1

	txa
	clc
	adc #VRC7_CHANNEL
	tax
	jsr ft_vibrato
	txa
	sec
	sbc #VRC7_CHANNEL
	tax

	; Vibrato
	lda var_ch_Fnum, x
	sec
	sbc var_Temp16
	sta var_Period
	lda var_ch_Fnum + 6, x
	sbc var_Temp16 + 1
	sta var_Period + 1
;.if 0
	; Fine pitch
	lda var_Period
	clc
	adc var_ch_FinePitch + VRC7_CHANNEL, x
	sta var_Period
	lda var_Period + 1
	adc #$00
	sta var_Period + 1
	lda var_Period
	sec
	sbc #$80
	sta var_Period
	lda var_Period + 1
	sbc #$00
	sta var_Period + 1
;.endif
.endif
	rts

; Used to adjust the Bnum setting when portamento is used
;
ft_vrc7_adjust_octave:

	; Get octave
	lda var_ch_ActiveNote - VRC7_CHANNEL, x
	sta ACC
	lda #12
	sta AUX
	lda #$00
	sta ACC + 1
	sta AUX + 1
	tya
	pha
	jsr DIV
	pla
	tay

	lda	ACC					; if new octave > old octave
	cmp var_ch_OldOctave
	bcs :+
	; Old octave > new octave, shift down portamento frequency
	lda var_ch_OldOctave
	sta var_ch_Bnum - VRC7_CHANNEL, x
	sec
	sbc ACC
	jsr @ShiftFreq2
	rts
:	lda	var_ch_OldOctave	; if old octave > new octave
	cmp ACC
	bcs @Return
	; New octave > old octave, shift down old frequency
	lda ACC
	sta var_ch_Bnum - VRC7_CHANNEL, x
	sec
	sbc var_ch_OldOctave
	jsr @ShiftFreq
@Return:
	rts

@ShiftFreq:
	sty var_Temp
	tay
:	lsr var_ch_TimerPeriod + EFF_CHANS, x
	ror var_ch_TimerPeriod, x
	dey
	bne :-
	ldy var_Temp
	rts

@ShiftFreq2:
	sty var_Temp
	tay
:	lsr var_ch_PortaTo + EFF_CHANS, x
	ror var_ch_PortaTo, x
	dey
	bne :-
	ldy var_Temp
	rts

ft_vrc7_trigger:

    lda var_ch_Effect, x
    cmp #EFF_PORTAMENTO
   	bne :+
    lda var_ch_Command - VRC7_CHANNEL, x
    bne :++
:
	lda #$01							; Trigger VRC7 channel
	sta var_ch_Command - VRC7_CHANNEL, x
:

	; Adjust Fnum if portamento is enabled
	lda var_ch_Effect, x
	cmp #EFF_PORTAMENTO
	bne @Return
	; Load portamento
	lda var_ch_Note, x
;	sec
;	sbc #$01
	beq @Return

	;rts

	lda var_ch_OldOctave
	bmi @Return

	jsr ft_vrc7_adjust_octave

@Return:
	rts

ft_vrc7_get_freq:

	tya
	pha

	lda var_ch_Bnum - VRC7_CHANNEL, x	
	sta var_ch_OldOctave

	; Retrigger channel
	lda var_ch_ActiveNote - VRC7_CHANNEL, x
	jsr ft_translate_note_vrc7
	ldy EXT	; note index -> y

	lda var_ch_Effect, x
	cmp #EFF_PORTAMENTO
	bne @NoPorta
	lda ft_note_table_vrc7_l, y
	sta var_ch_PortaTo, x
	lda ft_note_table_vrc7_h, y
	sta var_ch_PortaTo + EFF_CHANS, x
	
	; Check if previous note was silent, move this frequency directly to it
	lda var_ch_TimerPeriod, x
	ora var_ch_TimerPeriod + EFF_CHANS, x
	bne :+

	lda var_ch_PortaTo, x
	sta var_ch_TimerPeriod, x
	lda var_ch_PortaTo + EFF_CHANS, x
	sta var_ch_TimerPeriod + EFF_CHANS, x

	lda #$80				; Indicate new note (no previous)
	sta var_ch_OldOctave

	jmp :+

@NoPorta:
	lda ft_note_table_vrc7_l, y
	sta var_ch_TimerPeriod, x
	lda ft_note_table_vrc7_h, y
	sta var_ch_TimerPeriod + EFF_CHANS, x

:	lda ACC
	sta var_ch_Bnum - VRC7_CHANNEL, x

	pla
	tay
	
	lda #$00
	sta var_ch_State, x

	rts

ft_vrc7_get_freq_only:

	tya
	pha

	; Retrigger channel
	lda var_ch_ActiveNote - VRC7_CHANNEL, x
	jsr ft_translate_note_vrc7
	ldy EXT	; note index -> y

	lda ft_note_table_vrc7_l, y
	sta var_ch_TimerPeriod, x
	lda ft_note_table_vrc7_h, y
	sta var_ch_TimerPeriod + EFF_CHANS, x

	lda var_ch_Bnum - VRC7_CHANNEL, x
	sta var_ch_OldOctave

	lda ACC
	sta var_ch_Bnum - VRC7_CHANNEL, x
	
	lda #$00
	sta var_ch_State, x

	pla
	tay

	rts

; Setup note slides
;
ft_vrc7_load_slide:

	lda var_ch_TimerPeriod, x
	pha
	lda var_ch_TimerPeriod + EFF_CHANS, x
	pha

	; Load note
	lda var_ch_EffParam, x			; Store speed
	and #$0F						; Get note
	sta var_Temp					; Store note in temp

	lda var_ch_Effect, x
	cmp #EFF_SLIDE_UP_LOAD
	beq :+
	lda var_ch_Note, x
	sec
	sbc var_Temp
	jmp :++
:	lda var_ch_Note, x
	clc
	adc var_Temp
:	sta var_ch_Note, x

	jsr ft_translate_freq_only

	lda var_ch_TimerPeriod, x
	sta var_ch_PortaTo, x
	lda var_ch_TimerPeriod + EFF_CHANS, x
	sta var_ch_PortaTo + EFF_CHANS, x

    ; Store speed
	lda var_ch_EffParam, x
	lsr a
	lsr a
	lsr a
	ora #$01
	sta var_ch_EffParam, x

    ; Load old period
	pla
	sta var_ch_TimerPeriod + EFF_CHANS, x
	pla
	sta var_ch_TimerPeriod, x

    ; change mode to sliding
	clc
	lda var_ch_Effect, x
	cmp #EFF_SLIDE_UP_LOAD
	bne :+
	lda #EFF_SLIDE_DOWN
	jmp :++
:	lda #EFF_SLIDE_UP
:	sta var_ch_Effect, x
	jsr ft_vrc7_adjust_octave
    rts

; Fnum table, multiplied by 4 for more resolution
ft_note_table_vrc7_l:
	.byte 176, 212, 0, 48, 96, 148, 200, 4, 64, 128, 196, 12
;	.byte 172, 181, 192, 204, 216, 229, 242, 1, 16, 32, 49, 67
ft_note_table_vrc7_h:
	.byte 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 4, 5
;	.byte 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1
ft_vrc7_cmd:
	.byte $30, $20
