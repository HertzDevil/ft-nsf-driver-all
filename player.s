;
; ft_music_play
;
; The player routine
;
ft_music_play:
	lda var_PlayerFlags					; Skip if player is disabled
	bne :+
	rts									; Not playing, return
:
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
	lda var_Tempo_Accum + 1
	bmi ft_do_row_update				; Counter < 0
	ora var_Tempo_Accum
	beq ft_do_row_update				; Counter = 0
	jmp ft_skip_row_update
	; Read a row
ft_do_row_update:

.ifdef USE_DPCM
	lda #$00
	sta var_ch_DPCM_Retrig
.endif
.ifdef USE_FDS
    lda #$00
    sta var_ch_ModEffWritten
.endif

	; Switches to new frames are delayed to next row to resolve issues with delayed notes.
	; It won't work if new pattern adresses are loaded before the delayed note is played
	lda var_Load_Frame
	beq @SkipFrameLoad
	lda #$00
	sta var_Load_Frame
	lda var_Current_Frame
	jsr ft_load_frame
@SkipFrameLoad:

	lda #$00
	sta var_Jump
	sta var_Skip

	; Read one row from all patterns
	ldx #$00
ft_read_channels:
@UpdateChan:
	lda var_ch_Delay, x
	beq :+
	lda #$00
	sta var_ch_Delay, x
	jsr ft_read_pattern
:	jsr ft_read_pattern					; Get new notes
	lda var_ch_NoteCut, x
	and #$7F
	sta var_ch_NoteCut, x
	inx
	cpx #CHANNELS
	bne ft_read_channels

.ifdef USE_FDS
    lda var_ch_ModEffWritten
	and #$01
    beq :+
    ; FDS modulation depth
    lda var_ch_ModEffDepth
    sta var_ch_ModDepth
:   lda var_ch_ModEffWritten
	and #$02
    beq :+
    ; FDS modulation rate high
    lda var_ch_ModEffRateHi
    sta var_ch_ModRate + 1
:   lda var_ch_ModEffWritten
	and #$04
    beq :+
    ; FDS modulation rate low
    lda var_ch_ModEffRateLo
    sta var_ch_ModRate + 0
:
 	lda #$00
 	sta var_ch_ModEffWritten
.endif

	; Should jump?
	lda var_Jump
	beq @NoJump
	; Yes, jump
	sec
	sbc #$01
	sta var_Current_Frame
;	jsr ft_load_frame
	lda #$01
	sta var_Load_Frame

	jmp @NoPatternEnd
@NoJump:
	; Should skip?
	lda var_Skip
	beq @NoSkip
	; Yes, skip
	sec
	sbc #$01
.ifdef ENABLE_ROW_SKIP
	; Store next row number in Temp2
	sta var_SkipTo
.endif
	inc var_Current_Frame
	lda var_Current_Frame
	cmp var_Frame_Count
	beq @RestartSong
;	jsr ft_load_frame
	lda #$01
	sta var_Load_Frame

	jmp @NoPatternEnd
@RestartSong:
	lda #$00
	sta var_Current_Frame
;	jsr ft_load_frame
	lda #$01
	sta var_Load_Frame

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
	sta var_Load_Frame
	jmp @NoPatternEnd
@ResetFrame:
	ldx #$00
	stx var_Current_Frame
	inx
	stx var_Load_Frame
	
@NoPatternEnd:
	jsr ft_restore_speed				; Reset frame divider counter
ft_skip_row_update:
	; Speed division
	sec
	lda var_Tempo_Accum					; Decrement speed counter
	sbc var_Tempo_Count
	sta var_Tempo_Accum
	lda var_Tempo_Accum + 1
	sbc var_Tempo_Count + 1
	sta var_Tempo_Accum + 1

	; Note cut effect (Sxx)
	ldx #$00
:	lda var_ch_NoteCut, x
	beq :+
	sec
	sbc #$01
	sta var_ch_NoteCut, x
	bne :+
	sta var_ch_Note, x
:	inx
	cpx #CHANNELS
	bne :--

	; Update channel instruments and effects
	ldx #$00

; Loop through wave channels
ft_loop_channels:

	; Do channel effects, like portamento and vibrato
	jsr ft_run_effects

	; Instrument sequences
	lda var_ch_Note, x
	beq :+
	jsr ft_update_channel				; Update instruments	
:	jsr	ft_calc_freq

	inx
	;cpx #WAVE_CHANS		; Skip DPCM
	cpx #EFF_CHANS
	bne ft_loop_channels

	; Finally update APU and expansion chip registers
	jsr ft_update_apu
.ifdef USE_VRC6
	jsr	ft_update_vrc6
.endif
.ifdef USE_MMC5
	jsr	ft_update_mmc5
.endif
.ifdef USE_VRC7
	jsr ft_update_vrc7
.endif
.ifdef USE_FDS
	jsr ft_update_fds
.endif

	; End of music routine, return
	rts


; Process a pattern row in channel X
ft_read_pattern:
	ldy var_ch_NoteDelay, x				; First check if in the middle of a row delay
	beq :+
	dey
	tya
	sta var_ch_NoteDelay, x
	rts									; And skip
:	sty var_Sweep						; Y = 0
.ifdef USE_BANKSWITCH
	; First setup the bank
	lda var_ch_Bank, x
	beq :+
	sta $5FFB							; Will always be the last bank before DPCM
:	; Go on
.endif
	lda #$0F
.ifdef USE_FDS
	cpx #FDS_CHANNEL
	bne :+
	lda #$1F							; FDS max vol is 31
:
.endif
	sta var_VolTemp
	lda var_ch_PatternAddrLo, x			; Load pattern address
	sta var_Temp_Pattern
	lda var_ch_PatternAddrHi, x
	sta var_Temp_Pattern + 1
.ifdef USE_VRC7
    lda #$FF
    sta var_ch_vrc7_EffPatch
.endif

ft_read_note:
	lda (var_Temp_Pattern), y			; Read pattern command
	bpl :+
	jmp @Effect
:	beq @JumpToDone						; Rest
	cmp #$7F
;	beq @NoteOff						; Note off
	bne :+
	jmp @NoteOff
:	cmp #$7E
;	beq @NoteRelease					; Note release
	bne :+
	jmp @NoteRelease
:
	; Read a note
	sta var_ch_Note, x					; Note on
	jsr ft_translate_freq

	lda var_ch_NoteCut, x
	bmi :+
	lda #$00
	sta var_ch_NoteCut, x				; Reset note cuts
:
.ifdef USE_DPCM
	cpx #DPCM_CHANNEL					; Break here if DPCM
	bne :+
	jmp @ReadIsDone
:	; DPCM skip
.endif
.ifdef USE_VRC7
	cpx #VRC7_CHANNEL
	bcc :+								; <
	cpx #VRC7_CHANNEL + 6
	bcs :+								; >
	jsr ft_vrc7_trigger
	jmp @ReadIsDone
:	; VRC7 skip
.endif
	jsr ft_reset_instrument
	lda #$00
	sta var_ch_State, x
	lda var_VolTemp
	sta var_ch_Volume, x
	lda #$00
;	sta var_ch_ArpeggioCycle, x

	lda var_ch_DutyCycle, x
	and #$F0
	sta var_ch_DutyCycle, x
	lsr a
	lsr a
	lsr a
	lsr a
	ora var_ch_DutyCycle, x
	sta var_ch_DutyCycle, x

	; Reset sweep
	lda var_ch_Effect,x
	cmp #EFF_SLIDE_UP
	beq :+
	cmp #EFF_SLIDE_DOWN
	bne :++
:	lda #EFF_NONE
	sta var_ch_Effect,x
:

	cpx #$02							; Skip if not square
	bcc :+
	jmp @ReadIsDone
:	lda #$00
	sta var_ch_Sweep, x					; Reset sweep
@JumpToDone:
	jmp @ReadIsDone
@NoteRelease:
	lda #$01
	sta var_ch_State, x
.ifdef USE_DPCM
	cpx #DPCM_CHANNEL					; Skip if DPCM
	bne :+
	lda #$FF
	sta var_ch_Note, x
	jmp @ReadIsDone
:
.endif
.ifdef USE_VRC7
    cpx #VRC7_CHANNEL
    bcs @JumpToDone
.endif
	jsr ft_instrument_release
	jmp @ReadIsDone
@NoteOff:
	lda #$00
	sta var_ch_Note, x
.ifdef USE_DPCM
	cpx #DPCM_CHANNEL					; Skip if DPCM
	bne :+
	jmp @ReadIsDone
:
.endif
.ifdef USE_VRC7
	cpx #VRC7_CHANNEL					; Skip if not VRC7 channel
	bcc :+
	cpx #VRC7_CHANNEL + 6
	bcs :+
	lda #$00							; Halt VRC7 channel
	sta var_ch_vrc7_Command - VRC7_CHANNEL, x

	jmp @ReadIsDone
:
.endif
	sta var_ch_Volume, x
	sta var_ch_PortaToLo, x
	sta var_ch_PortaToHi, x
	cpx #$02							; Skip all over square channels
	bcs :+
	lda #$FF
	sta var_ch_PrevFreqHigh, x
:	jmp @ReadIsDone
@VolumeCommand:							; Handle volume
	pla
	asl a
	asl a
	asl a
	;asl a
	and #$78
	sta var_ch_VolColumn, x
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
	jmp ft_read_is_done
@ReadIsDone:
	lda var_ch_DefaultDelay, x			; See if there's a default delay
	cmp #$FF
	bne @LoadDefaultDelay				; If so then use it
	iny
	lda (var_Temp_Pattern), y			; A note is immediately followed by the amount of rows until next note
	sta var_ch_NoteDelay, x
ft_read_is_done:
	clc									; Store pattern address
	iny
	tya
	adc var_Temp_Pattern
	sta var_ch_PatternAddrLo, x
	lda #$00
	adc var_Temp_Pattern + 1
	sta var_ch_PatternAddrHi, x

	lda var_Sweep						; Check sweep
	beq @EndPatternFetch
	sta var_ch_Sweep, x					; Store sweep, only used for square 1 and 2
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
	.word ft_cmd_slide_up
	.word ft_cmd_slide_down
	.word ft_cmd_vol_slide
	.word ft_cmd_note_cut
	.word ft_cmd_retrigger
	.word ft_cmd_dpcm_pitch
	.word ft_cmd_duration
	.word ft_cmd_noduration
.ifdef USE_FDS
	.word ft_cmd_fds_mod_depth
	.word ft_cmd_fds_mod_rate_hi
	.word ft_cmd_fds_mod_rate_lo
.endif
.ifdef USE_VRC7
    .word ft_cmd_vrc7_patch_change
.endif
;	.word ft_cmd_expand

;
; Command functions
;

.if 0
; Loop expansion
ft_cmd_expand:
	lda var_ch_LoopCounter, x	; See if already looping
	bne :+
	; Load new loop
	jsr ft_get_pattern_byte		; number of loops
	sta var_ch_LoopCounter, x
	jsr ft_get_pattern_byte		; length in bytes
	sta var_Temp
	; Calculate pattern pointer
	sec
	lda var_Temp_Pattern
	sbc var_Temp
	sta var_Temp_Pattern
	lda var_Temp_Pattern + 1
	sbc #$00
	sta var_Temp_Pattern + 1
	ldy #$00
	jmp ft_read_note
:	; Already looping
	sec
	sbc #$01
	beq :+						; Check if done
	sta var_ch_LoopCounter, x
	iny							; number of loops, ignore
	jsr ft_get_pattern_byte		; length in bytes
	sta var_Temp
	; Calculate pattern pointer
	sec
	lda var_Temp_Pattern
	sbc var_Temp
	sta var_Temp_Pattern
	lda var_Temp_Pattern + 1
	sbc #$00
	sta var_Temp_Pattern + 1
	ldy #$00
	jmp ft_read_note
:	; Loop is done
	sta var_ch_LoopCounter, x
	iny							; number of loops, ignore
	iny							; length in bytes, ignore
	jmp ft_read_note
.endif

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
	sta var_PlayerFlags
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
	sta var_ch_EffParam, x
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
.ifdef USE_FDS
	cpx #FDS_CHANNEL
	bne :+
	lda #EFF_PORTA_DOWN
:
.endif
.ifdef USE_VRC7
   	cpx	#VRC7_CHANNEL
	bcc :+
	lda #EFF_PORTA_DOWN
	:
.endif
	sta var_ch_Effect, x
	jmp ft_read_note
; Effect: Portamento down (2xx)
ft_cmd_porta_down:
	jsr ft_get_pattern_byte
	sta var_ch_EffParam, x
	beq ResetEffect
	lda #EFF_PORTA_DOWN
.ifdef USE_FDS
	cpx #FDS_CHANNEL
	bne :+
	lda #EFF_PORTA_UP
:
.endif
.ifdef USE_VRC7
   	cpx	#VRC7_CHANNEL
	bcc :+
	lda #EFF_PORTA_UP
	:
.endif
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
	sta var_ch_PortaToLo, x
	sta var_ch_PortaToHi, x
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

	lda var_ch_VibratoSpeed, x
	bne :++
	;lda var_VibratoOffset
	lda var_SongFlags
	and #$02
	beq :+
	lda #48
:
	sta var_ch_VibratoPos, x	
:	pla

	pha
	and #$F0
	sta var_ch_VibratoDepth, x
	pla
	and #$0F
	sta var_ch_VibratoSpeed, x
;	cmp #$00
;	beq @ResetVibrato
	jmp ft_read_note
;@ResetVibrato:					; Clear vibrato
;	lda var_VibratoOffset
;	sta var_ch_VibratoPos, x
;	jmp ft_read_note
; Effect: Tremolo (7xy)
ft_cmd_tremolo:
	jsr ft_get_pattern_byte
	pha
	and #$F0
	sta var_ch_TremoloDepth, x
	pla
	and #$0F
	sta var_ch_TremoloSpeed, x
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
; Effect: delta counter setting (Zxx)
ft_cmd_dac:
	jsr ft_get_pattern_byte
.ifdef USE_DPCM
	sta var_ch_DPCMDAC
.endif
	jmp ft_read_note
; Effect: Duty cycle (Vxx)
ft_cmd_duty:
	jsr ft_get_pattern_byte
	sta var_ch_DutyCycle, x	; xxxxyyyy: xxxx = default value, yyyy = current value
	clc
	asl a
	asl a
	asl a
	asl a
	ora var_ch_DutyCycle, x
	sta var_ch_DutyCycle, x
	jmp ft_read_note
; Effect: Sample offset
ft_cmd_sample_offset:
	jsr ft_get_pattern_byte
.ifdef USE_DPCM
	sta var_ch_DPCM_Offset
.endif
	jmp ft_read_note
; Effect: Slide pitch up
ft_cmd_slide_up:
	jsr ft_get_pattern_byte			; Fetch speed / note
	sta var_ch_EffParam, x
	lda #EFF_SLIDE_UP_LOAD
	sta var_ch_Effect, x
	jmp ft_read_note
; Effect: Slide pitch down
ft_cmd_slide_down:
	jsr ft_get_pattern_byte			; Fetch speed / note
	sta var_ch_EffParam, x
	lda #EFF_SLIDE_DOWN_LOAD
	sta var_ch_Effect, x
	jmp ft_read_note
; Effect: Volume slide
ft_cmd_vol_slide:
	jsr ft_get_pattern_byte			; Fetch speed / note
	sta var_ch_VolSlide, x
	jmp ft_read_note
; Effect: Note cut (Sxx)
ft_cmd_note_cut:
	jsr ft_get_pattern_byte
	ora #$80
	sta var_ch_NoteCut, x
	jmp ft_read_note
; Effect: Retrigger
ft_cmd_retrigger:
	jsr ft_get_pattern_byte
.ifdef USE_DPCM
	sta var_ch_DPCM_Retrig
	lda var_ch_DPCM_RetrigCntr
	bne :+
	lda var_ch_DPCM_Retrig
	sta var_ch_DPCM_RetrigCntr
.endif
:	jmp ft_read_note
; Effect: DPCM pitch setting
ft_cmd_dpcm_pitch:
    jsr ft_get_pattern_byte
    sta var_ch_DPCM_EffPitch
	jmp ft_read_note
; End of effect column commands
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
; FDS

.ifdef USE_FDS

ft_cmd_fds_mod_depth:
	jsr ft_get_pattern_byte
	sta var_ch_ModEffDepth
	lda var_ch_ModEffWritten
	ora #$01
	sta var_ch_ModEffWritten
	jmp ft_read_note
ft_cmd_fds_mod_rate_hi:
	jsr ft_get_pattern_byte
	sta var_ch_ModEffRateHi
	lda var_ch_ModEffWritten
	ora #$02
	sta var_ch_ModEffWritten
	jmp ft_read_note
ft_cmd_fds_mod_rate_lo:
	jsr ft_get_pattern_byte
	sta var_ch_ModEffRateLo
	lda var_ch_ModEffWritten
	ora #$04
	sta var_ch_ModEffWritten
	jmp ft_read_note

.endif

; VRC7
.ifdef USE_VRC7
ft_cmd_vrc7_patch_change:
	jsr ft_get_pattern_byte
	sta var_ch_vrc7_EffPatch
	sta var_ch_vrc7_Patch - VRC7_CHANNEL, x
	jmp ft_read_note
.endif

;
; End of commands
;

.ifdef USE_VRC6
ft_load_vrc6_saw_table:
	cpx #SAW_CHANNEL
	bne :+
	pha						; Load VRC6 sawtooth table
	lda #<ft_periods_sawtooth
	sta var_Note_Table
	lda #>ft_periods_sawtooth
	sta var_Note_Table + 1
	pla
	rts
:	pha						; Load 2A03 table
	lda #<ft_notes_ntsc
	sta var_Note_Table
	lda #>ft_notes_ntsc
	sta var_Note_Table + 1
	pla
	rts
.endif

.ifdef USE_FDS
ft_load_fds_table:
	cpx #FDS_CHANNEL
	bne :+
	pha
	lda #<ft_periods_fds		; Load FDS table
	sta var_Note_Table
	lda #>ft_periods_fds
	sta var_Note_Table + 1
	pla
	rts
:	pha
	lda	#<ft_notes_ntsc			; Load 2A03 table
	sta var_Note_Table
	lda #>ft_notes_ntsc
	sta var_Note_Table + 1
	pla
	rts
.endif

ft_translate_freq_only:

	sec
	sbc #$01

.ifdef USE_VRC7
	cpx	#VRC7_CHANNEL
	bcc :+
	sta var_ch_vrc7_ActiveNote - VRC7_CHANNEL, x
	jsr ft_vrc7_get_freq_only
	rts
:
.endif


	cpx #NOISE_CHANNEL							; Check if noise
	beq StoreNoise2

.ifdef USE_VRC6
	jsr	ft_load_vrc6_saw_table
.endif
.ifdef USE_FDS
	jsr ft_load_fds_table
.endif

	asl a
	sty var_Temp
	tay
LoadFrequency:
	lda (var_Note_Table), y
	sta var_ch_TimerPeriodLo, x
	iny
	lda (var_Note_Table), y
	sta var_ch_TimerPeriodHi, x
	ldy var_Temp
	rts

StoreNoise2:
	sta var_ch_TimerPeriodLo, x
	lda #$00
	sta var_ch_TimerPeriodHi, x
    rts

; Translate the note in A to a frequency and stores in current channel
; If portamento is enabled, store in PortaTo
ft_translate_freq:

	sec
	sbc #$01

.ifdef USE_DPCM
	cpx #DPCM_CHANNEL				; Check if DPCM
	beq StoreDPCM
.endif

.ifdef USE_VRC7
	cpx #VRC7_CHANNEL
	bcc :+
;	clc
;	adc #$01						; todo: remove this eventually
	sta var_ch_vrc7_ActiveNote - VRC7_CHANNEL, x
	jsr ft_vrc7_get_freq
	rts
:
.endif

	cpx #NOISE_CHANNEL				; Check if noise
	beq StoreNoise

.ifdef USE_VRC6
	jsr	ft_load_vrc6_saw_table
.endif
.ifdef USE_FDS
	jsr ft_load_fds_table
.endif

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
	sta var_ch_PortaToLo, x
	iny
	lda (var_Note_Table), y
	sta var_ch_PortaToHi, x
	ldy var_Temp
	lda var_ch_TimerPeriodLo, x
	ora var_ch_TimerPeriodHi, x
	bne @Return
	lda var_ch_PortaToLo, x
	sta var_ch_TimerPeriodLo, x
	lda var_ch_PortaToHi, x
	sta var_ch_TimerPeriodHi, x
@Return:
	rts
@NoPorta:
	jmp LoadFrequency
	rts
StoreNoise:							; Special case for noise

    pha
	lda var_ch_Effect, x
	cmp #EFF_PORTAMENTO
	bne @NoPorta
	pla
	sta var_ch_PortaToLo, x
	lda #$00
	sta var_ch_PortaToHi, x
	lda var_ch_TimerPeriodLo, x
	ora var_ch_TimerPeriodHi, x
	bne @Return
	lda var_ch_PortaToLo, x
	sta var_ch_TimerPeriodLo, x
	lda var_ch_PortaToHi, x
	sta var_ch_TimerPeriodHi, x
@Return:
	rts
@NoPorta:
    pla
	sta var_ch_TimerPeriodLo, x
	lda #$00
	sta var_ch_TimerPeriodHi, x
	rts

.ifdef USE_DPCM
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
.endif

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
