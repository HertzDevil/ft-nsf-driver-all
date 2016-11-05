; Update the instrument for channel X
;
; I might consider storing the sequence address variables in ZP??
;
ft_return:
	rts
ft_update_channel:
;	cpx #$04
;	beq ft_return
	; Volume
	;
	lda var_ch_SeqVolume + WAVE_CHANS, x
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
	lda var_ch_SeqArpeggio + WAVE_CHANS, x
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
	lda var_ch_SeqPitch + WAVE_CHANS, x
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
	adc var_ch_TimerPeriod, x
	sta var_ch_TimerPeriod, x
	lda var_sequence_result
	bpl @NoNegativePitch 
	lda #$FF
	bmi @LoadLowPitch
@NoNegativePitch:
	lda #$00
@LoadLowPitch:
	adc var_ch_TimerPeriod + WAVE_CHANS, x
	sta var_ch_TimerPeriod + WAVE_CHANS, x
	jsr ft_limit_freq
	; ^^^^^^^^^^

	; Save pitch
@SkipPitchUpdate:
	; HiPitch bend
	;
	lda var_ch_SeqHiPitch + WAVE_CHANS, x
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
@MultiplyByTen:
	clc
	rol var_Temp16 						; multiply by 2
	rol var_Temp16 + 1
	dey
	bne @MultiplyByTen
	
	clc	
	lda var_Temp16
	adc var_ch_TimerPeriod, x
	sta var_ch_TimerPeriod, x
	lda var_Temp16 + 1
	adc var_ch_TimerPeriod + WAVE_CHANS, x
	sta var_ch_TimerPeriod + WAVE_CHANS, x
	jsr ft_limit_freq	
	; ^^^^^^^^^^

@SkipHiPitchUpdate:
	; Duty cycle/noise mode
	;
	lda var_ch_SeqDutyCycle + WAVE_CHANS, x
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
	sta var_ch_DutyCycle, x
	; Save pitch
@SkipDutyUpdate:
	rts
	
	
; Process an item in a sequence, next position is returned in A, result in Y (not anymore)
;
; In: A = Sequence index
; Out: A = New sequence index
;
ft_run_sequence:
	clc
	adc #$02						; Offset is 2 items
	tay
	lda (var_Temp_Pointer), y
	sta var_sequence_result
	dey
	tya
	ldy #$00						; Check if halt point
	cmp (var_Temp_Pointer), y
	beq @HaltSequence
	rts
@HaltSequence:						; Stop the sequence
	iny						
	lda (var_Temp_Pointer), y		; Check loop point
	cmp #$FF
	bne @LoopSequence
	lda #$FF						; Disable sequence by loading $FF into length
	rts
@LoopSequence:						; Just return A
	rts

; Reset instrument sequences
;	
ft_reset_instrument:
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

	; Get the specified instrument
	lda (var_Temp16), y
	adc ft_music_addr
	sta var_Temp_Pointer
	iny
	lda (var_Temp16), y
	adc ft_music_addr + 1
	sta var_Temp_Pointer + 1

	; var_Temp_Pointer points to instrument data
	ldy #$00
	tya
	sta var_ch_SeqVolume, x
	sta var_ch_SeqVolume + WAVE_CHANS, x
	sta var_ch_SeqArpeggio, x
	sta var_ch_SeqArpeggio + WAVE_CHANS, x
	sta var_ch_SeqPitch, x
	sta var_ch_SeqPitch + WAVE_CHANS, x
	sta var_ch_SeqHiPitch, x
	sta var_ch_SeqHiPitch + WAVE_CHANS, x
	sta var_ch_SeqDutyCycle, x
	sta var_ch_SeqDutyCycle + WAVE_CHANS, x

	; Read instrument data
	lda (var_Temp_Pointer), y		; Read mod switch
	sta var_Temp2
	iny

	; Volume
	ror var_Temp2
	bcc	:+
	clc
	lda (var_Temp_Pointer), y
	adc ft_music_addr
	sta var_ch_SeqVolume, x
	iny
	lda (var_Temp_Pointer), y
	adc ft_music_addr + 1
	sta var_ch_SeqVolume + WAVE_CHANS, x
	iny
: 	; Arpeggio
	ror var_Temp2
	bcc	:+
	clc
	lda (var_Temp_Pointer), y
	adc ft_music_addr
	sta var_ch_SeqArpeggio, x
	iny
	lda (var_Temp_Pointer), y
	adc ft_music_addr + 1
	sta var_ch_SeqArpeggio + WAVE_CHANS, x
	iny
:	; Pitch
	ror var_Temp2
	bcc	:+
	clc
	lda (var_Temp_Pointer), y
	adc ft_music_addr
	sta var_ch_SeqPitch, x
	iny
	lda (var_Temp_Pointer), y
	adc ft_music_addr + 1
	sta var_ch_SeqPitch + WAVE_CHANS, x
	iny
:	; Hi-Pitch
	ror var_Temp2
	bcc	:+
	clc
	lda (var_Temp_Pointer), y
	adc ft_music_addr
	sta var_ch_SeqHiPitch, x
	iny
	lda (var_Temp_Pointer), y
	adc ft_music_addr + 1
	sta var_ch_SeqHiPitch + WAVE_CHANS, x
	iny
:	; Duty cycle
	ror var_Temp2
	bcc	:+
	clc
	lda (var_Temp_Pointer), y
	adc ft_music_addr
	sta var_ch_SeqDutyCycle, x
	iny
	lda (var_Temp_Pointer), y
	adc ft_music_addr + 1
	sta var_ch_SeqDutyCycle + WAVE_CHANS, x
	iny
:
	jsr ft_reset_instrument
	ldy var_Temp
	
	rts

; Make sure the frequency doesn't exceed max or min
ft_limit_freq:
	lda var_ch_TimerPeriod + WAVE_CHANS, x
	bmi @LimitMin						; min
	cmp #$08							; max
	bmi @NoLimit
	lda #$07
	sta var_ch_TimerPeriod + WAVE_CHANS, x
	lda #$FF
	sta var_ch_TimerPeriod, x
@NoLimit:
	rts
@LimitMin:
	lda #$00
	sta var_ch_TimerPeriod, x
	sta var_ch_TimerPeriod + WAVE_CHANS, x
	rts
