;
; ft_music_play
;
; The player routine
;
ft_music_play:
	lda var_Flags						; Skip if player is disabled
	bne @Play
	rts
@Play:
	; Run delayed channels
	ldx #$00
@ChanLoop:
	lda var_ch_Delay, x
	beq @SkipDelay
	sec
	sbc #$01
	sta var_ch_Delay, x
	bne @SkipDelay
	jsr ft_read_pattern					; Read the delayed note
@SkipDelay:
	inx
	cpx #CHANNELS
	bne @ChanLoop
	; Speed division
	sec
	lda var_Tempo_Accum					; Decrement speed counter
	sbc var_Tempo_Count
	sta var_Tempo_Accum
	lda var_Tempo_Accum + 1
	sbc var_Tempo_Count + 1
	sta var_Tempo_Accum + 1
	bmi ft_do_row_update				; Counter has reached bottom
	ora var_Tempo_Accum
	beq ft_do_row_update				; Counter has reached bottom
	jmp ft_skip_row_update
	; Read a row
ft_do_row_update:
	lda #$00
	sta var_Jump
	sta var_Skip
	; Iterate through the channels and get pattern data
	ldx #$00
ft_read_channels:
@UpdateChan:
	lda var_ch_Delay, x
	beq @JustRead
	lda #$00
	sta var_ch_Delay, x
	jsr ft_read_pattern					; Delay duration was too long
@JustRead:
	jsr ft_read_pattern					; Get new notes
	inx
	cpx #CHANNELS
	bne ft_read_channels
	; Should jump?
	lda var_Jump
	beq @NoJump
	; Yes, jump
	sec
	sbc #$01
	sta var_Current_Frame
	jsr ft_load_frame
	jmp @NoPatternEnd
@NoJump:
	; Should skip?
	lda var_Skip
	beq @NoSkip
	; Yes, skip
	sec
	sbc #$01
	; Store next row number in Temp2
	sta var_Temp2
	inc var_Current_Frame
	lda var_Current_Frame
	cmp var_Frame_Count
	beq @RestartSong
	jsr ft_load_frame
	jmp @NoPatternEnd
@RestartSong:
	lda #$00
	sta var_Current_Frame
	jsr ft_load_frame
	jmp @NoPatternEnd
@NoSkip:
	; Current row in all channels are processed, update info
	inc var_Pattern_Pos
	lda var_Pattern_Pos					; See if end is reached
	cmp var_Pattern_Length
	bne @NoPatternEnd
	; End of current frame, load next
	inc var_Current_Frame
	lda var_Current_Frame
	cmp var_Frame_Count
	beq @ResetFrame
	jsr ft_load_frame
	jmp @NoPatternEnd
@ResetFrame:
	lda #$00
	sta var_Current_Frame
	jsr ft_load_frame
	
@NoPatternEnd:
	jsr ft_restore_speed				; Reset frame divider counter
ft_skip_row_update:
	; Update channel instruments
	ldx #$00
ft_loop_channels:
	; Instrument sequences
	lda var_ch_Note, x
	beq @SkipChannelUpdate
	jsr ft_update_channel				; Update instruments
@SkipChannelUpdate:
	; Do channel effects, like portamento and vibrato
	jsr ft_run_effects
	inx
	cpx #(CHANNELS - 1)					; Skip DPCM of course
	bne ft_loop_channels
	; Finally update APU registers
	jsr ft_update_apu
	; End of music routine, return
	rts
	
; Process a pattern row in channel X
ft_read_pattern:
	lda var_ch_NoteDelay, x				; First check if in the middle of a row delay
	beq @NoRowDelay
	dec var_ch_NoteDelay, x				; Decrease one
	rts									; And skip
@NoRowDelay:
	sta var_Sweep
	tay
	; First setup the bank
	lda var_ch_Bank, x
	beq @NoBank
	sta $5FFB							; Will always be the last bank before DPCM
@NoBank:
	; Go on
	lda #$0F
	sta var_VolTemp
	lda var_ch_Pattern_addr, x			; Load pattern address
	sta var_Temp_Pattern
	lda var_ch_Pattern_addr + 5, x
	sta var_Temp_Pattern + 1
	
ft_read_note:
	lda (var_Temp_Pattern), y
	bmi @Effect
	beq @JumpToDone
	cmp #$7F							; Note off
	beq @NoteOff
	; A real note
	sta var_ch_Note, x					; Note on
	jsr ft_translate_freq
	jsr ft_reset_instrument
	cpx #$04							; Break here if DPCM
	;beq @ReadIsDone
	bne @NotLastChan
	jmp @ReadIsDone
@NotLastChan:

	lda var_VolTemp
	sta var_ch_Volume, x
	lda #$00
	sta var_ch_ArpeggioCycle, x
	
	lda var_ch_DutyCycle, x
	and #$0C
	sta var_ch_DutyCycle, x
	lsr a
	lsr a
	ora var_ch_DutyCycle, x
	sta var_ch_DutyCycle, x

	cpx #$02							; Skip if not square
	bcs @ReadIsDone
	lda #$00
	sta var_ch_Sweep, x					; Reset sweep
@JumpToDone:
	jmp @ReadIsDone
@NoteOff:
	lda #$00
	sta var_ch_Note, x	
	cpx #$04							; Skip DPCM
	beq @SkipMoreOff
	sta var_ch_Volume, x
	sta var_ch_PortaTo, x
	sta var_ch_PortaTo + 4, x
	cpx #$02							; Skip all over square channels
	bcs @SkipMoreOff
	lda #$FF
	sta var_ch_PrevFreqHigh, x
@SkipMoreOff:
	jmp @ReadIsDone
@VolumeCommand:							; Handle volume
	pla
	and #$0F
	sta var_ch_VolumeOffset, x			; yeah
	iny
	jmp ft_read_note	
@InstCommand:							; Instrument change
	pla
	and #$0F
	asl a
	jsr ft_load_instrument
	iny
	jmp ft_read_note	
@Effect:
	pha
	and #$F0
	cmp #$F0							; See if volume
	beq @VolumeCommand
	cmp #$E0							; See if a quick instrument command
	beq @InstCommand
	pla
	and #$7F							; Look up the command address
	sty var_Temp						; from the command table
	tay
	lda ft_command_table, y
	sta var_Temp_Pointer
	iny
	lda ft_command_table, y
	sta var_Temp_Pointer + 1
	ldy var_Temp
	iny
	jmp (var_Temp_Pointer)				; And jump there
@LoadDefaultDelay:
	sta var_ch_NoteDelay, x				; Store default delay
	jmp @StoraPatternAddr
@ReadIsDone:
	lda var_ch_DefaultDelay, x			; See if there's a default delay
	cmp #$FF
	bne @LoadDefaultDelay				; If so then use it
	iny
	lda (var_Temp_Pattern), y			; A note is immediately followed by the amount of rows until next note
	sta var_ch_NoteDelay, x
@StoraPatternAddr:						; <--- combine these labels
ft_read_is_done:
	clc									; Store pattern address
	iny
	tya
	adc var_Temp_Pattern
	sta var_ch_Pattern_addr, x
	lda #$00
	adc var_Temp_Pattern + 1
	sta var_ch_Pattern_addr + 5, x
	lda var_Sweep						; Check sweep
	beq @EndPatternFetch
	sta var_ch_Sweep, x					; Store sweep
	lda #$00
	sta var_Sweep
	sta var_ch_PrevFreqHigh, x	
@EndPatternFetch:
	rts

; Read pattern to A and move to next byte
ft_get_pattern_byte:
	lda (var_Temp_Pattern), y			; Get the instrument number
	pha
	iny
	pla
	rts

;
; Command table
;
ft_command_table:
	.word ft_cmd_instrument
	.word ft_cmd_speed
	.word ft_cmd_jump
	.word ft_cmd_skip
	.word ft_cmd_halt
	.word ft_cmd_effvolume
	.word ft_cmd_portamento
	.word ft_cmd_porta_up
	.word ft_cmd_porta_down
	.word ft_cmd_sweep
	.word ft_cmd_arpeggio
	.word ft_cmd_vibrato
	.word ft_cmd_tremolo
	.word ft_cmd_pitch
	.word ft_cmd_delay
	.word ft_cmd_dac
	.word ft_cmd_duty
	.word ft_cmd_sample_offset
	.word ft_cmd_duration
	.word ft_cmd_noduration

;
; Command functions
;

; Change instrument
ft_cmd_instrument:
	jsr ft_get_pattern_byte
	jsr ft_load_instrument
	jmp ft_read_note
; Effect: Speed (Fxx)
ft_cmd_speed:
	jsr ft_get_pattern_byte
	cmp #21
	bcc @SpeedIsTempo
	sta var_Tempo
	bcs @StoreDone
@SpeedIsTempo:
	sta var_Speed
@StoreDone:
	jsr ft_calculate_speed
	jmp ft_read_note
; Effect: Jump (Bxx)
ft_cmd_jump:
	jsr ft_get_pattern_byte
	sta var_Jump
	jmp ft_read_note
; Effect: Skip (Dxx)
ft_cmd_skip: 
	jsr ft_get_pattern_byte
	sta var_Skip
	jmp ft_read_note
; Effect: Halt (Cxx)
ft_cmd_halt:
	jsr ft_get_pattern_byte
	lda #$00
	sta var_Flags
	jmp ft_read_note
; Effect: Volume (Exx)
ft_cmd_effvolume:
	jsr ft_get_pattern_byte
	sta var_VolTemp
	sta var_ch_Volume, x
	jmp ft_read_note
; Effect: Portamento (3xx)
ft_cmd_portamento:
	jsr ft_get_pattern_byte
	;sta var_ch_PortaSpeed, x
	sta var_ch_EffParam, x
	;lda #$00
	beq ResetEffect
	lda #EFF_PORTAMENTO
	sta var_ch_Effect, x
	jmp ft_read_note
; Effect: Portamento up (1xx)
ft_cmd_porta_up:
	jsr ft_get_pattern_byte
	sta var_ch_EffParam, x
	beq ResetEffect
	lda #EFF_PORTA_UP
	sta var_ch_Effect, x
	jmp ft_read_note
; Effect: Portamento down (2xx)
ft_cmd_porta_down:
	jsr ft_get_pattern_byte
	sta var_ch_EffParam, x
	beq ResetEffect
	lda #EFF_PORTA_DOWN
	sta var_ch_Effect, x	
	jmp ft_read_note
; Effect: Arpeggio (0xy)
ft_cmd_arpeggio:
	jsr ft_get_pattern_byte
	sta var_ch_EffParam, x
	beq ResetEffect
	lda #EFF_ARPEGGIO
	sta var_ch_Effect, x
	jmp ft_read_note
ResetEffect:					; Shared by 0, 1, 2, 3
	sta var_ch_Effect, x
	sta var_ch_PortaTo, x
	sta var_ch_PortaTo + 4, x
	jmp ft_read_note	
; Effect: Hardware sweep (Hxy / Ixy)
ft_cmd_sweep:
	jsr ft_get_pattern_byte
	sta var_Sweep
	jmp ft_read_note
; Effect: Vibrato (4xy)
ft_cmd_vibrato:
	jsr ft_get_pattern_byte
	pha
	lsr a						; Get vibrato speed, found in the high nybble
	lsr a
	lsr a
	lsr a
	sta var_ch_VibratoSpeed, x
	pla
	sta var_ch_VibratoParam, x
	cmp #$00
	beq @ResetVibrato
	jmp ft_read_note
@ResetVibrato:					; Clear vibrato
	sta var_ch_VibratoPos, x
	jmp ft_read_note
; Effect: Tremolo (7xy)
ft_cmd_tremolo:
	jsr ft_get_pattern_byte
	pha
	lsr a						; Get tremolo speed, found in the high nybble
	lsr a
	lsr a
	lsr a
	sta var_ch_TremoloSpeed, x
	pla
	sta var_ch_TremoloParam, x
	cmp #$00
	beq @ResetTremolo
	jmp ft_read_note
@ResetTremolo:					; Clear tremolo
	sta var_ch_TremoloPos, x
	jmp ft_read_note
; Effect: Pitch (Pxx)
ft_cmd_pitch:
	jsr ft_get_pattern_byte
	sta var_ch_FinePitch, x
	jmp ft_read_note
; Effect: Delay (Gxx)
ft_cmd_delay:
	jsr ft_get_pattern_byte
	sta var_ch_Delay, x
	dey
	jmp ft_read_is_done
; Effect: DAC setting (Zxx)
ft_cmd_dac:
	jsr ft_get_pattern_byte
	sta var_ch_DPCMDAC
	jmp ft_read_note
; Effect: Duty cycle
ft_cmd_duty:
	jsr ft_get_pattern_byte
	sta var_ch_DutyCycle, x
	clc
	asl a
	asl a
	ora var_ch_DutyCycle, x
	sta var_ch_DutyCycle, x
	jmp ft_read_note
; Effect: Sample offset
ft_cmd_sample_offset:
	jsr ft_get_pattern_byte
	sta var_ch_DPCM_Offset
	jmp ft_read_note
; Set default note duration
ft_cmd_duration:
	jsr ft_get_pattern_byte
	sta var_ch_DefaultDelay, x
	jmp ft_read_note
; No default note duration
ft_cmd_noduration:
	lda #$FF
	sta var_ch_DefaultDelay, x
	jmp ft_read_note

;
; End of commands
;

ft_translate_freq_only:
	cpx #03							; Check if noise
	beq StoreNoise
	asl a
	sty var_Temp
	tay
LoadFrequency:
	lda (var_Note_Table), y
	sta var_ch_Frequency, x
	iny
	lda (var_Note_Table), y
	sta var_ch_Frequency + 4, x
	ldy var_Temp
	rts
	
; Translate the note in A to a frequency and stores in current channel
ft_translate_freq:
	cpx #03							; Check if noise
	beq StoreNoise
	cpx #04							; Check if DPCM
	beq StoreDPCM
	asl a
	sty var_Temp
	tay
	; Check portamento
	;lda var_ch_PortaSpeed, x
	lda var_ch_Effect, x
	cmp #EFF_PORTAMENTO
	bne @NoPorta
	; Load portamento
	lda (var_Note_Table), y
	sta var_ch_PortaTo, x
	iny
	lda (var_Note_Table), y
	sta var_ch_PortaTo + 4, x
	ldy var_Temp
	lda var_ch_Frequency, x
	ora var_ch_Frequency + 4, x
	bne @Return
	lda var_ch_PortaTo, x
	sta var_ch_Frequency, x
	lda var_ch_PortaTo + 4, x
	sta var_ch_Frequency + 4, x
@Return:
	rts
@NoPorta:
	; Load the frequency
;	lda (var_Note_Table), y
;	sta var_ch_Frequency, x
;	iny
;	lda (var_Note_Table), y
;	sta var_ch_Frequency + 4, x
;	ldy var_Temp
	jmp LoadFrequency
	rts
StoreNoise:							; Special case for noise
	sta var_ch_Frequency, x
	rts
StoreDPCM:							; Special case for DPCM
	pha
	lda var_dpcm_inst_list			; Optimize this maybe?
	sta var_Temp16
	lda var_dpcm_inst_list + 1
	sta var_Temp16 + 1
	pla
	
	sty var_Temp
	tay
	lda (var_Temp16), y				; Read pitch
	sta var_ch_SamplePitch
	iny 
	lda (var_Temp16), y				; Read sample
	tay
	
	lda var_dpcm_pointers			; Load sample pointer list
	sta var_Temp16
	lda var_dpcm_pointers + 1
	sta var_Temp16 + 1
	
	lda (var_Temp16), y				; Get sample position
	sta var_ch_SamplePtr
	iny
	lda (var_Temp16), y				; And size
	sta var_ch_SampleLen
	
	ldy var_Temp
	rts

; Reload speed division counter
ft_restore_speed:
	clc
	lda var_Tempo_Accum
	adc var_Tempo_Dec
	sta var_Tempo_Accum
	lda var_Tempo_Accum + 1
	adc var_Tempo_Dec + 1
	sta var_Tempo_Accum + 1
	rts

; Calculate frame division from the speed and tempo settings
ft_calculate_speed:
	tya
	pha
	
	; Multiply by 24
	lda var_Tempo
	sta AUX
	lda #$00
	sta AUX + 1
	ldy #$03
@rotate:
	asl AUX
	rol AUX	+ 1
	dey
	bne @rotate
	lda AUX
	sta ACC
	lda AUX + 1
	tay
	asl AUX	
	rol AUX	+ 1
	clc
	lda ACC
	adc AUX
	sta ACC
	tya
	adc AUX + 1
	sta ACC + 1
		
	; divide by speed
	lda var_Speed
	sta AUX
	lda #$00
	sta AUX + 1
	jsr DIV		; ACC/AUX -> ACC, remainder in EXT
	lda ACC
	sta var_Tempo_Count
	lda ACC + 1
	sta var_Tempo_Count + 1
	pla
	tay
	rts

; If anyone knows a way to calculate speed without using
; multiplication or division, please contact me	

; ACC/AUX -> ACC, remainder in EXT
DIV:      LDA #0
          STA EXT+1
          LDY #$10
LOOP2:    ASL ACC
          ROL ACC+1
          ROL
          ROL EXT+1
          PHA
          CMP AUX
          LDA EXT+1
          SBC AUX+1
          BCC DIV2
          STA EXT+1
          PLA
          SBC AUX
          PHA
          INC ACC
DIV2:     PLA
          DEY
          BNE LOOP2
          STA EXT
          RTS
