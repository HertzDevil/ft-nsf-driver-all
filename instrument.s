; Update the instrument for channel X
;
; I might consider storing the sequence address variables in ZP??
;
ft_update_channel:
	; Volume
	;
	lda var_ch_SeqVolume + 4, x
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
	lda var_ch_SeqArpeggio + 4, x
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
	lda var_ch_SeqPitch + 4, x
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
	adc var_ch_Frequency, x
	sta var_ch_Frequency, x
	lda var_sequence_result
	bpl @NoNegativePitch 
	lda #$FF
	bmi @LoadLowPitch
@NoNegativePitch:
	lda #$00
@LoadLowPitch:
	adc var_ch_Frequency + 4, x
	sta var_ch_Frequency + 4, x
	jsr ft_limit_freq
	; ^^^^^^^^^^

	; Save pitch
@SkipPitchUpdate:
	; HiPitch bend
	;
	lda var_ch_SeqHiPitch + 4, x
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
	adc var_ch_Frequency, x
	sta var_ch_Frequency, x
	lda var_Temp16 + 1
	adc var_ch_Frequency + 4, x
	sta var_ch_Frequency + 4, x
	jsr ft_limit_freq	
	; ^^^^^^^^^^

@SkipHiPitchUpdate:
	; Duty cycle/noise mode
	;
	lda var_ch_SeqDutyCycle + 4, x
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
	cpx #$04
	beq @Return						; Skip when DPCM
	lda #$00
	sta var_ch_SequencePtr1, x
	sta var_ch_SequencePtr2, x
	sta var_ch_SequencePtr3, x
	sta var_ch_SequencePtr4, x
	sta var_ch_SequencePtr5, x
@Return:
	rts

; Loads a 16-bit address
;
ft_get_sequence_address:
	lda (var_Temp_Pointer), y				; See if there's an sequence for this address
	iny
	ora (var_Temp_Pointer), y
	beq @SkipSequence
	dey
	clc										; Not empty, load address to sequenec
	lda (var_Temp_Pointer), y
	adc ft_music_addr
	sta var_Temp16
	iny
	lda (var_Temp_Pointer), y
	adc ft_music_addr + 1
	sta var_Temp16 + 1
	iny
	rts
@SkipSequence:								; Just load zero so it'll be skipped later
;	dey
	lda #$0
	sta var_Temp16
	sta var_Temp16 + 1
	iny
	rts

; Load the instrument in A for channel X (Y must be saved)
;
ft_load_instrument:
	sty var_Temp
	ldy #$00
	; Load the address for selected instrument
	clc
	adc var_instrument_list
	sta var_Temp_Pointer
	tya
	adc var_instrument_list + 1
	sta var_Temp_Pointer + 1
	clc
	ldy #$00
	lda (var_Temp_Pointer), y		; Load a
	adc ft_music_addr
	pha
	iny
	lda (var_Temp_Pointer), y		; Load a
	adc ft_music_addr + 1
	sta var_Temp_Pointer + 1
	pla
	sta var_Temp_Pointer
	
	; var_Temp_Pointer is now pointing to the selected instrument in memory
	; Data there is ordered as 
	; { 2 bytes pointing to volume }
	; { 2 bytes pointing to arpeggio }
	; ...
	
	;
	;
	; Optimize the part below
	;
	;
	
	ldy #$00
	
	; Load sequence numbers
	jsr ft_get_sequence_address		; Volume
	lda var_Temp16
	sta var_ch_SeqVolume, x
	lda var_Temp16 + 1
	sta var_ch_SeqVolume + 4, x

	jsr ft_get_sequence_address		; Arpeggio
	lda var_Temp16
	sta var_ch_SeqArpeggio, x
	lda var_Temp16 + 1
	sta var_ch_SeqArpeggio + 4, x
		
	jsr ft_get_sequence_address		; Pitch
	lda var_Temp16
	sta var_ch_SeqPitch, x
	lda var_Temp16 + 1
	sta var_ch_SeqPitch + 4, x
	
	jsr ft_get_sequence_address		; Hi-pitch
	lda var_Temp16
	sta var_ch_SeqHiPitch, x
	lda var_Temp16 + 1
	sta var_ch_SeqHiPitch + 4, x
	
	jsr ft_get_sequence_address		; Duty cycle
	lda var_Temp16
	sta var_ch_SeqDutyCycle, x
	lda var_Temp16 + 1
	sta var_ch_SeqDutyCycle + 4, x
	
	; Reset positions
	jsr ft_reset_instrument
	ldy var_Temp
	rts

; Make sure the frequency doesn't exceed max or min
ft_limit_freq:
	lda var_ch_Frequency + 4, x
	bmi @LimitMin						; min
	cmp #$08							; max
	bmi @NoLimit
	lda #$07
	sta var_ch_Frequency + 4, x
	lda #$FF
	sta var_ch_Frequency, x
@NoLimit:
	rts
@LimitMin:
	lda #$00
	sta var_ch_Frequency, x
	sta var_ch_Frequency + 4, x
	rts
