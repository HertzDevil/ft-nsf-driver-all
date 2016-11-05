; Update the instrument for channel X
;
; I might consider storing the sequence address variables in ZP??
;
ft_return:
	rts
ft_update_channel:
.ifdef USE_VRC7
	cpx #VRC7_CHANNEL
	bcc :+
	cpx #VRC7_CHANNEL + 6
	bcs :+
	rts
:
.endif
	; Volume
	;
	lda var_ch_SeqVolume + SFX_WAVE_CHANS, x	; High part of address = 0 mean sequence is disabled
	beq @SkipVolumeUpdate
	sta var_Temp_Pointer + 1
	lda var_ch_SeqVolume, x					; Store the sequence address in a zp variable
	sta var_Temp_Pointer
	lda var_ch_SequencePtr1, x				; Sequence item index
	cmp #$FF
	beq @SkipVolumeUpdate					; Skip if end is reached
	jsr ft_run_sequence						; Run an item in the sequence
	sta var_ch_SequencePtr1, x				; Store new index
	lda var_sequence_result					; Take care of the result
	sta var_ch_Volume, x
@SkipVolumeUpdate:

	; Arpeggio
	;
	lda var_ch_SeqArpeggio + SFX_WAVE_CHANS, x
	beq @SkipArpeggioUpdate
	sta var_Temp_Pointer + 1
	lda var_ch_SeqArpeggio, x
	sta var_Temp_Pointer
	lda var_ch_SequencePtr2, x
	cmp #$FF
	beq @SkipArpeggioUpdate
	jsr ft_run_sequence
	sta var_ch_SequencePtr2, x
	lda var_ch_Note, x					; No arp if no note
	beq @SkipArpeggioUpdate
	clc
	lda var_ch_Note, x
	adc var_sequence_result
	jsr ft_translate_freq_only
@SkipArpeggioUpdate:

	; Pitch bend
	;
	lda var_ch_SeqPitch + SFX_WAVE_CHANS, x
	beq @SkipPitchUpdate
	sta var_Temp_Pointer + 1
	lda var_ch_SeqPitch, x
	sta var_Temp_Pointer
	lda var_ch_SequencePtr3, x
	cmp #$FF
	beq @SkipPitchUpdate
	jsr ft_run_sequence
	sta var_ch_SequencePtr3, x
	
	; Check this
	clc
	lda var_sequence_result
	adc var_ch_TimerPeriodLo, x
	sta var_ch_TimerPeriodLo, x
	lda var_sequence_result
	bpl @NoNegativePitch 
	lda #$FF
	bmi @LoadLowPitch
@NoNegativePitch:
	lda #$00
@LoadLowPitch:
	adc var_ch_TimerPeriodHi, x
	sta var_ch_TimerPeriodHi, x
	jsr ft_limit_freq
	; ^^^^^^^^^^

	; Save pitch
@SkipPitchUpdate:
	; HiPitch bend
	;
	lda var_ch_SeqHiPitch + SFX_WAVE_CHANS, x
	beq @SkipHiPitchUpdate
	sta var_Temp_Pointer + 1
	lda var_ch_SeqHiPitch, x
	sta var_Temp_Pointer
	lda var_ch_SequencePtr4, x
	cmp #$FF
	beq @SkipHiPitchUpdate
	jsr ft_run_sequence
	sta var_ch_SequencePtr4, x

	; Check this
	lda var_sequence_result
	sta var_Temp16
	rol a
	bcc @AddHiPitch
	lda #$FF
	sta var_Temp16 + 1
	jmp @StoreHiPitch
@AddHiPitch:
	lda #$00
	sta var_Temp16 + 1
@StoreHiPitch:
	ldy #$04
:	clc
	rol var_Temp16 						; multiply by 2
	rol var_Temp16 + 1
	dey
	bne :-
	
	clc	
	lda var_Temp16
	adc var_ch_TimerPeriodLo, x
	sta var_ch_TimerPeriodLo, x
	lda var_Temp16 + 1
	adc var_ch_TimerPeriodHi, x
	sta var_ch_TimerPeriodHi, x
	jsr ft_limit_freq
	; ^^^^^^^^^^

@SkipHiPitchUpdate:
	; Duty cycle/noise mode
	;
	lda var_ch_SeqDutyCycle + SFX_WAVE_CHANS, x
	beq @SkipDutyUpdate
	sta var_Temp_Pointer + 1
	lda var_ch_SeqDutyCycle, x
	sta var_Temp_Pointer
	lda var_ch_SequencePtr5, x
	cmp #$FF
	beq @SkipDutyUpdate
	jsr ft_run_sequence
	sta var_ch_SequencePtr5, x
	lda var_sequence_result
	pha
	lda var_ch_DutyCycle, x
	and #$F0
	sta var_ch_DutyCycle, x
	pla
	ora var_ch_DutyCycle, x
	sta var_ch_DutyCycle, x
	; Save pitch
@SkipDutyUpdate:
	rts
	
	
;
; Process a sequence, next position is returned in A
;
; In: A = Sequence index
; Out: A = New sequence index
;
ft_run_sequence:
	clc
	adc #$03						; Offset is 3 items
	tay
	lda (var_Temp_Pointer), y
	sta var_sequence_result
	dey
	dey
	tya
	ldy #$00						; Check if halt point
	cmp (var_Temp_Pointer), y
	beq @HaltSequence
	ldy #$02						; Check release point
	cmp (var_Temp_Pointer), y
	beq @ReleasePoint
	rts
@HaltSequence:						; Stop the sequence
	iny
	lda (var_Temp_Pointer), y		; Check loop point
	cmp #$FF
	bne @LoopSequence
	lda #$FF						; Disable sequence by loading $FF into length
	rts
@Skip:
	lda	var_Temp
@LoopSequence:						; Just return A
    pha
	lda var_ch_State, x
	bne :+
	pla
	rts								; Return new index
:	ldy #$02						; Check release point
	lda (var_Temp_Pointer), y
	bne :+
	pla								; Release point not found, loop
 	rts
:	pla								; Release point found, don't loop
	lda #$FF
	rts
@ReleasePoint:						; Release point has been reached
	sta	var_Temp					; Save index
	lda var_ch_State, x
	bne @Skip						; Note is releasing, continue until end
	dey
	lda (var_Temp_Pointer), y		; Check loop point
	cmp #$FF
	bne @LoopSequence
	lda var_Temp
	sec								; Step back one step
	sbc #$01
	rts

; Called on note release instruction
;
ft_instrument_release:
    tya
    pha
	lda var_ch_SeqVolume + SFX_WAVE_CHANS, x
	beq :+
	sta var_Temp_Pointer + 1
	lda var_ch_SeqVolume, x
	sta var_Temp_Pointer
	ldy #$02
	lda (var_Temp_Pointer), y
	beq :+
	sta var_ch_SequencePtr1, x
:	lda var_ch_SeqArpeggio + SFX_WAVE_CHANS, x
	beq :+
	sta var_Temp_Pointer + 1
	lda var_ch_SeqArpeggio, x
	sta var_Temp_Pointer
	ldy #$02
	lda (var_Temp_Pointer), y
	beq :+
	sta var_ch_SequencePtr2, x
:	lda var_ch_SeqPitch + SFX_WAVE_CHANS, x
	beq :+
	sta var_Temp_Pointer + 1
	lda var_ch_SeqPitch, x
	sta var_Temp_Pointer
	ldy #$02
	lda (var_Temp_Pointer), y
	beq :+
	sta var_ch_SequencePtr3, x
:	lda var_ch_SeqHiPitch + SFX_WAVE_CHANS, x
	beq :+
	sta var_Temp_Pointer + 1
	lda var_ch_SeqHiPitch, x
	sta var_Temp_Pointer
	ldy #$02
	lda (var_Temp_Pointer), y
	beq :+
	sta var_ch_SequencePtr4, x
:	lda var_ch_SeqDutyCycle + SFX_WAVE_CHANS, x
	beq :+
	sta var_Temp_Pointer + 1
	lda var_ch_SeqDutyCycle, x
	sta var_Temp_Pointer
	ldy #$02
	lda (var_Temp_Pointer), y
	beq :+
	sta var_ch_SequencePtr5, x
:   pla
	tay
	rts

; Reset instrument sequences
;
ft_reset_instrument:

.ifdef USE_FDS
	cpx #FDS_CHANNEL
	bne :+
	lda var_ch_ModDelay
	sta var_ch_ModDelayTick
;	lda #$00
;	sta $4085
;	lda #$80
;	sta $4087
;	rts
:
.endif

	lda #$00
	sta var_ch_SequencePtr1, x
	sta var_ch_SequencePtr2, x
	sta var_ch_SequencePtr3, x
	sta var_ch_SequencePtr4, x
	sta var_ch_SequencePtr5, x
	rts

; Load the instrument in A for channel X (Y must be saved)
;
; Optimize
;
ft_load_instrument:

.ifdef USE_VRC7
	sta var_Temp_Inst		; Save current instrument number
.endif

	sty var_Temp
	ldy #$00

	; Instrument_pointer_list + a => instrument_address
	; instrument_address + ft_music_addr => instrument_data

	; Get the instrument data pointer
	clc
	adc var_Instrument_list
	sta var_Temp16
	tya
	adc var_Instrument_list + 1
	sta var_Temp16 + 1
	clc

	; Get the instrument
	lda (var_Temp16), y
	adc ft_music_addr
	sta var_Temp_Pointer
	iny
	lda (var_Temp16), y
	adc ft_music_addr + 1
	sta var_Temp_Pointer + 1

.ifdef USE_FDS
	; FDS instruments
	cpx #FDS_CHANNEL
	bne @SkipFDS

	; Read FDS instrument
	ldy #$00
	lda (var_Temp_Pointer), y	; Load wave index
	iny
	pha

	; Load modulation table
	jsr ft_reset_modtable
:
	lda (var_Temp_Pointer), y
	pha
	and #$07
	sta $4088
	pla
	lsr a
	lsr a
	lsr a
	sta $4088
	iny
	cpy #$11
	bne :-

	lda (var_Temp_Pointer), y	; Modulation delay
	iny
	sta var_ch_ModDelay
	lda (var_Temp_Pointer), y	; Modulation depth
	iny
	sta var_ch_ModDepth
	lda (var_Temp_Pointer), y	; Modulation freq low
	iny
	sta var_ch_ModRate
	lda (var_Temp_Pointer), y	; Modulation freq high
	sta var_ch_ModRate + 1

	clc
	lda var_Temp_Pointer
	adc #$15
	sta var_Temp16
	lda var_Temp_Pointer + 1
	adc #$00
	sta var_Temp16 + 1

	pla							; Load wave index

	jsr ft_load_fds_wave

	lda var_Temp16
	sta var_Temp_Pointer
	lda var_Temp16 + 1
	sta var_Temp_Pointer + 1
	
;	jmp @Return
@SkipFDS:
.endif

.ifdef USE_VRC7
	; VRC7 instruments
	cpx #VRC7_CHANNEL
	bcc @SkipVRC7
	; Read VRC7 instrument
	ldy #$00
	lda (var_Temp_Pointer), y		; Load patch number
	sta var_ch_vrc7_Patch - VRC7_CHANNEL, x			; vrc7 channel offset
	sta var_ch_vrc7_DefPatch - VRC7_CHANNEL, x
	bne :++							; Skip custom settings if patch > 0
	lda var_Temp_Inst
	cmp var_ch_vrc7_CustomPatch			; Check if it's the same custom instrument
	beq :++							; Skip if it is
	; Load custom instrument regs
	txa
	pha
	ldx #$00
:	iny
	lda (var_Temp_Pointer), y		; Load register
	stx $9010						; Register index
	sta $9030						; Store the setting
	inx
	cpx #$08
	bne :-
	pla
	tax
	lda var_Temp_Inst
	sta var_ch_vrc7_CustomPatch
: 	;jmp @Return
	ldy var_Temp
	rts
@SkipVRC7:
.endif

	; Read instrument data, var_Temp_Pointer points to instrument data
	ldy #$00
	lda (var_Temp_Pointer), y		; sequence switch
	sta var_Temp3
	iny

; Macro used to load instrument envelopes
.macro load_inst seq_addr, seq_ptr

	ror var_Temp3
	bcc	:++
	clc
	lda (var_Temp_Pointer), y
	adc ft_music_addr
	sta var_Temp16
	iny
	lda (var_Temp_Pointer), y
	adc ft_music_addr + 1
	sta var_Temp16 + 1
	iny

	lda var_Temp16
	cmp seq_addr, x
	bne :+
	lda var_Temp16 + 1
	cmp seq_addr + SFX_WAVE_CHANS, x
;	bne :+

	; Both equal

	jmp :+++

:	lda var_Temp16
	sta seq_addr, x
	lda var_Temp16 + 1
	sta seq_addr + SFX_WAVE_CHANS, x

	lda #$00
	sta seq_ptr, x

	jmp :++		; branch always
:	lda #$00
	sta seq_addr, x
	sta seq_addr + SFX_WAVE_CHANS, x
:
.endmacro

    load_inst var_ch_SeqVolume, var_ch_SequencePtr1
    load_inst var_ch_SeqArpeggio, var_ch_SequencePtr2
    load_inst var_ch_SeqPitch, var_ch_SequencePtr3
    load_inst var_ch_SeqHiPitch, var_ch_SequencePtr4
    load_inst var_ch_SeqDutyCycle, var_ch_SequencePtr5

	ldy var_Temp

	rts

; Make sure the frequency doesn't exceed max or min
ft_limit_freq:
	lda var_ch_TimerPeriodHi, x
	bmi @LimitMin						; period < 0
.ifdef USE_VRC6
	cpx #VRC6_CHANNELS
	bcc :+
	cmp #$10							; period > $FFF
	bcc @NoLimit
	lda #$0F
	sta var_ch_TimerPeriodHi, x
	lda #$FF
	sta var_ch_TimerPeriodLo, x
	rts
:
.endif
.ifdef USE_FDS
	cpx #FDS_CHANNEL
	bne :+
	cmp #$11							; period > $1000?
	bcc @NoLimit
	lda #$10
	sta var_ch_TimerPeriodHi, x
	lda #$FF
	sta var_ch_TimerPeriodLo, x
	rts
:	
.endif
	cmp #$08							; period > $7FF
	bcc @NoLimit
	lda #$07
	sta var_ch_TimerPeriodHi, x
	lda #$FF
	sta var_ch_TimerPeriodLo, x
@NoLimit:
	rts
@LimitMin:
	lda #$00
	sta var_ch_TimerPeriodLo, x
	sta var_ch_TimerPeriodHi, x
	rts
