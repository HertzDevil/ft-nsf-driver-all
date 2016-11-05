;
; The NSF music driver for FamiTracker
; Version 1.7
; By jsr (zxy965r@tninet.se)
; assemble with cc65
;
; Recent changes
;  -- 1.7 -------------------------------------------------------------------------------------------
;   - Music data is compressed
;   - Fixed noise note-off problem
;  -- 1.6 -------------------------------------------------------------------------------------------
;   - Added track arpeggio/vibrato/tremolo
;   - Supports instruments changes
;   - Support for custom BPM speed
;  -- 1.5 -------------------------------------------------------------------------------------------
;   - Fixed a bug that caused sequences starting at $xxFF to fail
;   - Fixed fast pitch changing note
;   - Sequence loops failed when a 256-bytes page was crossed (as I suspected), that's fixed
;   - Added channel volume support
;   - DPCM samples to note assignment added
;   - Some other changes...
;  -- 1.4 -------------------------------------------------------------------------------------------
;   - Noise; notes plays as in the tracker
;  -- 1.3 -------------------------------------------------------------------------------------------
;   - Items after a sequence loop are executed immediately
;   - Automatic portamento is fixed, reset every channel on player start
;
; This code is not very optimized, average CPU usage is around 10%
;
; Todo:
;  Clean up (after 1.5 release)
;  Optimize!
;

.define VERSION         "FT-NSF-drv v1.7"

; Source switches
;
SRC_MAKE_NSF			= 0			; 1 = create NSF, 0 = produce raw code
SRC_MAKE_NES			= 0

; End of header
;
; Driver constants
;
SONG_OFFSET 			= $8E00		; where the music will be

SONG_SPEED				= SONG_OFFSET			; 8
SONG_TEMPO				= SONG_OFFSET + 1		; 8
SONG_FRAME_CNT			= SONG_OFFSET + 2		; 8
SONG_PAT_LENGTH			= SONG_OFFSET + 3		; 8
SONG_INST_PTR			= SONG_OFFSET + 4		; 16
SONG_INST_DPCM_PTR		= SONG_OFFSET + 6		; 16
SONG_SEQ_PTR			= SONG_OFFSET + 8		; 16
SONG_FRAME_PTR			= SONG_OFFSET + 10		; 16
SONG_DPCM_PTR			= SONG_OFFSET + 12		; 16
SONG_SPEED_DIV			= SONG_OFFSET + 14		; 16

SEQ_CHANNELS			= 5	; 4 channels are using the sequence-system (not really working right now)

; Macros
;
.macro proc_seq len, modptr
	lda len, x
	sta mdv_mod_len
	lda modptr, x
	sta mdv_mod_ptr
	lda modptr + SEQ_CHANNELS, x
	sta mdv_mod_ptr + 1
	jsr md_process_sequence
	lda mdv_mod_len
	sta len, x
	lda mdv_mod_ptr
	sta modptr, x
	lda mdv_mod_ptr + 1
	sta modptr + SEQ_CHANNELS, x
.endmacro


; Variables
;
.segment "ZEROPAGE"

; Zero-page
;
mdv_pointer:			.res 2
mdv_inst_ptr:			.res 2
mdv_inst_dpcm_ptr:		.res 2
mdv_seq_ptr:			.res 2
mdv_frame_ptr:			.res 2
mdv_dpcm_ptr:			.res 2
mdv_temp_ptr:			.res 2
mdv_note_lookup:		.res 2
mdv_mod_ptr:			.res 2
mdv_dpcm_inst:			.res 2		; pointer to the selected DPCM instrument
ACC:					.res 2
AUX:					.res 2
EXT:					.res 2


.segment "BSS"

; Player variables, not zero-page
;
mdv_playing:			.res 1		; :1 is playing, :2 = PAL 
mdv_temp:				.res 1
mdv_pattern_length:		.res 1
mdv_instrument:			.res 1
mdv_frame:				.res 1		; current frame
mdv_frame_count:		.res 1		; amount of frames before reset
mdv_patternpos:			.res 1
mdv_mod_len:			.res 1
mdv_sequence_value:		.res 1
mdv_sequence_update:	.res 1
mdv_jump_to:			.res 1
mdv_seek_to:			.res 1
mdv_nsf_frame:			.res 1
mdv_volume:				.res 1
mdv_sweep:				.res 1
mdv_tempo_accum:		.res 2
mdv_speed:				.res 1
mdv_tempo:				.res 2
mdv_speed_count:		.res 2
mdv_temp_index:			.res SEQ_CHANNELS

; Channel variables
;
chan_dpcm_pitch:		.res 1
chan_dpcm_addr:			.res 1
chan_dpcm_length:		.res 1

chan_pattern_ptr:		.res 10
chan_pattern_pos:		.res 5
chan_rle:				.res 5
chan_note:				.res 5
chan_inst:				.res 5
chan_orig_note:			.res 5
chan_freq_lo:			.res 5		; 0 - 255
chan_freq_hi:			.res 5		; 0 - 3
chan_prevfreq_hi:		.res 5
chan_volume:			.res 5
chan_damp_vol:			.res 5		; volume damping, (the volume column)
chan_dutycycle:			.res 5		; square / noise (3)
chan_portato_lo:		.res 5
chan_portato_hi:		.res 5
chan_portaspeed:		.res 5
chan_arp_pos:			.res 5
chan_arp_val:			.res 5
chan_vibrato_pos:		.res 5
chan_vibrato_param:		.res 5
chan_tremolo_pos:		.res 5
chan_tremolo_param:		.res 5
chan_finepitch:			.res 4
chan_sweep:				.res 2		; only avaliable on the square channels
chan_modptr1:			.res SEQ_CHANNELS * 2		; volume
chan_modptr2:			.res SEQ_CHANNELS * 2		; arpeggio
chan_modptr3:			.res SEQ_CHANNELS * 2		; pitch
chan_modptr4:			.res SEQ_CHANNELS * 2		; hi-pitch
chan_modptr5:			.res SEQ_CHANNELS * 2		; duty cycle
chan_len1:				.res SEQ_CHANNELS
chan_len2:				.res SEQ_CHANNELS
chan_len3:				.res SEQ_CHANNELS
chan_len4:				.res SEQ_CHANNELS
chan_len5:				.res SEQ_CHANNELS
chan_modindex:			.res SEQ_CHANNELS * 5

; Uncomment these if you want an NSF
;
.if SRC_MAKE_NSF = 1
	.segment "HEADER"
	.incbin "header.bin"
.elseif SRC_MAKE_NES = 1
	.segment "NESHEADER"
	.incbin "nesheader.bin"
.endif

	.segment "CODE"
LOAD:
INIT:
	jmp	sound_init
	;nop
PLAY:
	jmp	sound_driver
;
; Player init code
;
;  a = song number (currently thrown away, multisong tunes will come)
;  x = ntsc/pal
;
sound_init:								; NSF init
	lda #$06
	sta mdv_speed
	lda SONG_TEMPO
	sta mdv_tempo
	cpx #$01
	beq md_load_pal
	lda #<md_notes_ntsc
	sta mdv_note_lookup
	lda #>md_notes_ntsc
	sta mdv_note_lookup	+ 1
	jmp md_machine_loaded
md_load_pal:
	lda mdv_playing
	ora #$02
	sta mdv_playing
	lda #<md_notes_pal
	sta mdv_note_lookup
	lda #>md_notes_pal
	sta mdv_note_lookup	+ 1
md_machine_loaded:
	lda SONG_SPEED						; speed
	cmp #$20
	bcc md_init_was_speed
	sta mdv_tempo
	jmp md_init_after_speed
md_init_was_speed:
	sta mdv_speed
md_init_after_speed:
	lda SONG_INST_PTR
	sta mdv_inst_ptr
	lda SONG_INST_PTR + 1
	sta mdv_inst_ptr + 1
	lda SONG_INST_DPCM_PTR
	sta mdv_inst_dpcm_ptr
	lda SONG_INST_DPCM_PTR + 1
	sta mdv_inst_dpcm_ptr + 1
	lda SONG_SEQ_PTR
	sta mdv_seq_ptr
	lda SONG_SEQ_PTR + 1
	sta mdv_seq_ptr + 1
	lda SONG_FRAME_PTR
	sta mdv_frame_ptr
	lda SONG_FRAME_PTR + 1
	sta mdv_frame_ptr + 1
	lda SONG_DPCM_PTR
	sta mdv_dpcm_ptr
	lda SONG_DPCM_PTR + 1
	sta mdv_dpcm_ptr + 1
	lda #$00
	sta mdv_frame
	sta chan_sweep
	sta chan_sweep + 1
	sta mdv_jump_to
	lda #$01
	ora mdv_playing
	sta mdv_playing
	jsr md_load_frame
	lda SONG_PAT_LENGTH
	sta mdv_pattern_length
	sta mdv_patternpos
	lda SONG_FRAME_CNT
	sta mdv_frame_count
	ldx #$FF
md_reset_chan:
	inx
	lda #$00
	sta chan_damp_vol, x
	sta chan_rle, x
	sta chan_portato_hi, x
	sta chan_portato_lo, x
	sta chan_freq_hi, x
	sta chan_freq_lo, x
	lda #$FF
	sta chan_prevfreq_hi, x
	lda #$80
	sta chan_finepitch, x
	cpx #$03
	bne md_reset_chan
	lda #$00
	sta chan_dpcm_pitch
	sta chan_dpcm_addr
	sta chan_dpcm_length
	lda #$0F
	sta $4015
	lda #$40
	sta $4017	
	lda #$00
	sta $4000
	sta $4001
	sta $4002
	sta $4003
	sta $4004
	sta $4005
	sta $4006
	sta $4007
	sta $4008
	sta $4009
	sta $400A
	sta $400B
	sta $400D
	sta $400E
	sta $400F
	sta $4010
	sta $4011
	sta $4012
	sta $4013
	lda #$30		; noise is special
	sta $400C
	lda SONG_SPEED_DIV
	sta mdv_tempo_accum
	lda SONG_SPEED_DIV + 1
	sta mdv_tempo_accum + 1
	jsr md_calc_speed
	rts

md_calc_speed:
	; multiply with 24
	lda mdv_tempo
	sta ACC
	lda #$18
	sta AUX
	lda #$00
	sta ACC + 1
	sta AUX + 1
	jsr MULT	; ACC*AUX -> [ACC,EXT] (low,hi) 32 bit result	
	; divide by speed
	lda mdv_speed
	sta AUX
	lda #$00
	sta AUX + 1
	jsr DIV		; ACC/AUX -> ACC, remainder in EXT
	lda ACC
	sta mdv_speed_count
	lda ACC + 1
	sta mdv_speed_count + 1
	rts
;
; Start of player code
;
sound_driver:
	lda mdv_playing
	and #$01
	bne md_playing
	rts
md_playing:
	inc mdv_nsf_frame
	
	;Decrement speed counter
	sec
	lda mdv_tempo_accum
	sbc mdv_speed_count
	sta mdv_tempo_accum
	lda mdv_tempo_accum + 1
	sbc mdv_speed_count + 1
	sta mdv_tempo_accum + 1
	
	ldx #$FF
md_loop_channels:						; update all channels
	inx									; current channel is stored in x
	cpx #$05
	bne md_chan_not_done
	jmp md_end
md_chan_not_done:
	
	lda mdv_tempo_accum					; check if equal
	ora mdv_tempo_accum + 1
	beq md_process_channel
	lda mdv_tempo_accum + 1				; check if negative
	and #$80
	bne md_process_channel
	
	jsr md_process_instrument
	jmp md_loop_channels
md_process_channel:		
	lda chan_pattern_ptr, x				; pattern read pointer
	sta mdv_pointer
	lda chan_pattern_ptr + 5, x
	sta mdv_pointer + 1
	lda #$0F
	sta mdv_volume
	ldy #$00
	sty mdv_sweep
md_get_pattern_data:
	lda chan_rle, x
	beq @1
		dec chan_rle, x
		jmp md_note_end
@1:
	lda (mdv_pointer), y
	sta mdv_temp
	cmp #$FF							; a string of zeroes
	beq md_rle
	lda mdv_temp
	bmi md_note_effect					; was an effect/command		
	beq md_no_note						; no new note
		cmp #$7F						; note halt
		beq md_note_halt
			iny
			sta chan_note, x					; save note/octave
			sta chan_orig_note, x
			jsr md_trigger_note
			jsr md_inst_seq_reload_all
			lda #$0F
			sta chan_volume, x
			jmp md_note_end
	md_note_halt:
		iny
		lda #$00
		sta chan_note, x
		sta chan_portato_hi, x
		sta chan_portato_lo, x
		sta chan_freq_hi, x
		sta chan_freq_lo, x
		jmp md_note_end
	md_rle:
		iny
		jsr md_fetch_pattern_data
		sta chan_rle, x
		jmp md_note_end
	md_no_note:
		iny
		jmp md_note_end
	md_note_effect:						; process effect/command
		sty mdv_temp					; load a jump address from the effects lookup table
		and #$7F
		asl a
		tay
		lda md_effects, y
		sta mdv_temp_ptr
		iny
		lda md_effects, y
		sta mdv_temp_ptr + 1
		ldy mdv_temp
		iny
		jmp (mdv_temp_ptr)

md_fetch_pattern_data:
	lda (mdv_pointer), y
	iny
	rts

md_effects:
	.word md_instchange, md_volchange
	; Track effects
	.word md_effect_arpeggio, 	md_effect_portaon, 	md_effect_portaoff
	.word md_effect_vibrato, 	md_effect_tremolo
	.word md_effect_speed, 		md_effect_jump, 	md_effect_skip
	.word md_effect_halt, 		md_effect_volume,	md_effect_sweep
	.word md_effect_pitch

md_instchange:
	jsr md_fetch_pattern_data
	sta chan_inst, x
	jsr md_reload_instrument			; load specific sequences
	jmp md_get_pattern_data				; see if a note is next
md_volchange:
	jsr md_fetch_pattern_data
	sta chan_damp_vol, x
	jmp md_get_pattern_data

; Track effects
md_effect_arpeggio:
	jsr md_fetch_pattern_data
	sta chan_arp_val, x
	jmp md_get_pattern_data
md_effect_vibrato:
	jsr md_fetch_pattern_data
	sta chan_vibrato_param, x
	cmp #$00
	beq md_eff_reset_vibrato
	jmp md_get_pattern_data
	md_eff_reset_vibrato:
	lda #$00
	sta chan_vibrato_pos, x
	jmp md_get_pattern_data
md_effect_tremolo:
	jsr md_fetch_pattern_data
	sta chan_tremolo_param, x
	cmp #$00
	beq md_eff_reset_tremolo
	jmp md_get_pattern_data
	md_eff_reset_tremolo:
	lda #$00
	sta chan_tremolo_pos, x
	jmp md_get_pattern_data
md_effect_speed:
	jsr md_fetch_pattern_data
	cmp #$20
	bcc @1
	sta mdv_tempo
	tya
	pha
	jsr md_calc_speed
	pla
	tay
	jmp md_get_pattern_data
@1:
	sta mdv_speed
	tya
	pha
	jsr md_calc_speed
	pla
	tay
	jmp md_get_pattern_data
md_effect_jump:
	jsr md_fetch_pattern_data
	sta mdv_jump_to
	jmp md_get_pattern_data
md_effect_skip:
	jsr md_fetch_pattern_data
	clc
	adc #$01
	sta mdv_seek_to
	jmp md_get_pattern_data
md_effect_halt:
	jmp md_halt
md_effect_volume:
	jsr md_fetch_pattern_data
	sta chan_volume, x
	sta mdv_volume
	jmp md_get_pattern_data
md_effect_portaon:
	jsr md_fetch_pattern_data
	sta chan_portaspeed, x
	jmp md_get_pattern_data
md_effect_portaoff:
	jsr md_fetch_pattern_data
	lda #$00
	sta chan_portaspeed, x
	sta chan_portato_hi, x
	sta chan_portato_lo, x
	jmp md_get_pattern_data
md_effect_sweep:
	jsr md_fetch_pattern_data
	sta mdv_sweep
	jmp md_get_pattern_data
md_effect_pitch:
	jsr md_fetch_pattern_data
	sta chan_finepitch, x
	jmp md_get_pattern_data
md_note_end:
	lda mdv_sweep
	beq md_no_sweep
	sta chan_sweep, x
	lda #$00
	sta mdv_sweep
md_no_sweep:
	clc									; store current pattern pos pointer
	tya
	adc mdv_pointer
	sta chan_pattern_ptr, x
	lda #$00
	adc mdv_pointer + 1
	sta chan_pattern_ptr + 5, x	
	jsr md_process_instrument
	jmp md_loop_channels
md_end:									; end of pattern processing
	lda mdv_jump_to
	beq md_no_jump
	sec
	sbc #$01
	sta mdv_frame
	jsr md_load_frame
	lda mdv_pattern_length				; reload pattern positions
	sta mdv_patternpos	
	jsr md_reload_speed
	lda #$00
	sta mdv_jump_to
	jmp md_no_refresh_duration
md_no_jump:
	lda mdv_seek_to
	beq md_no_seek
	sec
	sbc #$01
	sta mdv_seek_to
	jsr md_seek_to_pattern	
	jsr md_reload_speed	
	lda #$00
	sta mdv_seek_to
	jmp md_no_refresh_duration

; remove this!	
md_is_tick_done:
	lda mdv_tempo_accum
	ora mdv_tempo_accum + 1
	beq @1
	lda mdv_tempo_accum + 1
	and #$80
	bne @1
	lda #$00
	rts
@1:
	lda #$01
	rts
	
md_no_seek:
	jsr md_is_tick_done
	beq md_no_refresh_duration	
	jsr md_reload_speed	
	dec mdv_patternpos					; check if all entries in one pattern has been played
	lda mdv_patternpos
	cmp #$FF
	bne md_no_refresh_duration
	jsr md_select_next_frame
md_no_refresh_duration:
	jsr md_update_channels				; refresh APU
	rts
md_halt:
	lda #$00
	sta mdv_playing
	lda #$00
	sta $4015
	rts
md_reload_speed:
	clc
	lda mdv_tempo_accum
	adc SONG_SPEED_DIV
	sta mdv_tempo_accum
	lda mdv_tempo_accum + 1
	adc SONG_SPEED_DIV + 1
	sta mdv_tempo_accum + 1
	rts
md_select_next_frame:					; move to next frame
	lda mdv_pattern_length				; reload pattern positions
	sta mdv_patternpos
	inc mdv_frame
	lda mdv_frame						; see if all frames are played
	cmp mdv_frame_count
	bne md_no_reset_song
	lda #$00							; start over at first in case of that
	sta mdv_frame
	md_no_reset_song:
	jsr md_load_frame
	rts
md_seek_to_pattern:
	jsr md_select_next_frame
	lda mdv_seek_to
	bne md_seek_ret
	rts
	md_seek_ret:
	ldx #$00
md_seek_loop_chan:
	lda mdv_seek_to
	sta mdv_temp
md_seek_loop:
	lda chan_pattern_ptr, x				; pattern read pointer
	sta mdv_pointer
	lda chan_pattern_ptr + 5, x
	sta mdv_pointer + 1
	jsr md_increase_pat
	ldy #$00
	;lda (mdv_pointer), y
	lda chan_rle, x
	beq @1
	dec chan_rle, x
	lda #$00
	jmp @2
@1:
	lda (mdv_pointer), y
;	jsr md_fetch_pattern_data
@2:
	bpl md_seek_no_cmd
	cmp #$80
	bne md_seek_no_inst
	iny
	;lda (mdv_pointer), y
	jsr md_fetch_pattern_data
	sta chan_inst, x
md_seek_no_inst:
	jsr md_increase_pat
	jmp md_seek_loop
md_seek_no_cmd:
	dec mdv_temp
	lda mdv_temp
	bne md_seek_loop
	inx
	cpx #$05
	bne md_seek_loop_chan
	lda mdv_patternpos
	sec
	sbc mdv_seek_to
	sta mdv_patternpos
	rts
md_increase_pat:
	clc
	lda chan_pattern_ptr, x
	adc #$01
	sta chan_pattern_ptr, x
	lda chan_pattern_ptr + 5, x
	adc #$00
	sta chan_pattern_ptr + 5, x	
	rts	
md_inst_seq_reload_all:					; Executed when a note is triggered
	cpx #$04
	bne	md_no_dmc
	jmp md_trigger_dpcm
md_no_dmc:
	tya
	pha
	lda #$FF							; reset all sequences
	sta chan_modindex, x
	sta chan_modindex + 5, x
	sta chan_modindex + 10, x
	sta chan_modindex + 15, x
	sta chan_modindex + 20, x
	jsr md_load_instrument
	lda mdv_volume
	sta chan_volume, x
	lda #$00
	sta chan_dutycycle, x
	pla
	tay
	cpx #$00							; Restore sweep
	beq @1
	cpx #$01
	beq @1
	rts	
@1:
	lda #$00
	sta chan_sweep, x
	rts
md_inst_seq_reload_volume:
	ldy #$00
	lda chan_modindex + 5 * 0, x
	beq @1
	sec
	sbc #01								; remove one to get the real sequence (a zero marks no sequence)
	asl	a								; multiply with 2
	tay
	lda (mdv_seq_ptr), y				; get the pointer and store it for the channel
	sta chan_modptr1, x
	iny
	lda (mdv_seq_ptr), y
	sta chan_modptr1 + SEQ_CHANNELS, x
	lda #$01
	sta chan_len1, x	
	rts
@1:
	lda #$00
	sta chan_len1, x	
	rts

md_inst_seq_reload_arpeggio:
	ldy #$01
	lda chan_modindex + (5 * 1), x
	beq @1
	sec
	sbc #01								; remove one to get the real sequence (a zero marks no sequence)
	asl	a								; multiply with 2
	tay
	lda (mdv_seq_ptr), y				; get the pointer and store it for the channel
	sta chan_modptr2, x
	iny
	lda (mdv_seq_ptr), y
	sta chan_modptr2 + SEQ_CHANNELS, x
	lda #$01
	sta chan_len2, x
	rts
@1:
	lda #$00
	sta chan_len2, x
	rts
md_inst_seq_reload_pitch:
	ldy #$02
	lda chan_modindex + (5 * 2), x
	beq @1
	sec
	sbc #01								; remove one to get the real sequence (a zero marks no sequence)
	asl	a								; multiply with 2
	tay
	lda (mdv_seq_ptr), y				; get the pointer and store it for the channel
	sta chan_modptr3, x
	iny
	lda (mdv_seq_ptr), y
	sta chan_modptr3 + SEQ_CHANNELS, x
	lda #$01
	sta chan_len3, x	
	rts
@1:
	lda #$00
	sta chan_len3, x	
	rts
md_inst_seq_reload_hipitch:
	ldy #$03
	lda chan_modindex + (5 * 3), x
	beq @1
	sec
	sbc #01								; remove one to get the real sequence (a zero marks no sequence)
	asl	a								; multiply with 2
	tay
	lda (mdv_seq_ptr), y				; get the pointer and store it for the channel
	sta chan_modptr4, x
	iny
	lda (mdv_seq_ptr), y
	sta chan_modptr4 + SEQ_CHANNELS, x
	lda #$01
	sta chan_len4, x
	rts
@1:
	lda #$00
	sta chan_len4, x
	rts
md_inst_seq_reload_duty:
	ldy #$04
	lda chan_modindex + (5 * 4), x
	beq @1
	sec
	sbc #01								; remove one to get the real sequence (a zero marks no sequence)
	asl	a								; multiply with 2
	tay
	lda (mdv_seq_ptr), y				; get the pointer and store it for the channel
	sta chan_modptr5, x
	iny
	lda (mdv_seq_ptr), y
	sta chan_modptr5 + SEQ_CHANNELS, x
	lda #$01
	sta chan_len5, x
	rts
@1:
	lda #$00
	sta chan_len5, x
	rts
	
md_reload_instrument:					; load instruments
md_load_instrument:						; load instrument set for current channel
	; Load pattern indexes
	tya									; Save y
	pha
	lda chan_inst, x					; First, get a pointer to instrument data
	asl a
	tay
	lda (mdv_inst_ptr), y
	sta mdv_temp_ptr
	iny
	lda (mdv_inst_ptr), y
	sta mdv_temp_ptr + 1
	ldy #$00							; Now, get the indexes for the sequences
md_load_sequence_indexes:
	lda (mdv_temp_ptr), y				; Read all 5 and store them	
	sta mdv_temp_index, y
	iny
	cpy #SEQ_CHANNELS
	bne md_load_sequence_indexes	
	; Compare every sequence, reload if changed
	; First
	lda mdv_temp_index
	cmp chan_modindex, x
	beq @1
	sta chan_modindex, x
	jsr md_inst_seq_reload_volume
@1:	; Second
	lda mdv_temp_index + 1
	cmp chan_modindex + 5, x
	beq @2
	sta chan_modindex + 5, x
	jsr md_inst_seq_reload_arpeggio
@2:	; Third
	lda mdv_temp_index + 2
	cmp chan_modindex + (5 * 2), x
	beq @3
	sta chan_modindex + (5 * 2), x
	jsr md_inst_seq_reload_pitch
@3:	; Fourth
	lda mdv_temp_index + 3
	cmp chan_modindex + (5 * 3), x
	beq @4
	sta chan_modindex + (5 * 3), x
	jsr md_inst_seq_reload_hipitch
@4:	; Fifth
	lda mdv_temp_index + 4
	cmp chan_modindex + (5 * 4), x
	beq @5
	sta chan_modindex + (5 * 4), x
	jsr md_inst_seq_reload_duty
@5:	; Done
	pla									; Restore y
	tay	
	rts
;	
; Code for updating the APU below
;	
md_apply_tremolo:
	ldy chan_tremolo_pos, x
	lda md_lfo, y
	lsr a
	lsr a
	lsr a
	lsr a
	pha
	lda chan_tremolo_param, x
	and #$0F
	lsr a
	sta mdv_temp
	sec
	lda #$03
	sbc mdv_temp
	tay
	pla
	cpy #$00
	beq md_trem_no_iter
md_trem_iter:
	lsr a
	dey
	bne md_trem_iter
md_trem_no_iter:
	sta mdv_temp
	lda chan_tremolo_param, x
	and #$01
	bne md_trem_more_dec
	lda mdv_temp
	pha
	lsr a
	sta mdv_temp
	sec
	pla
	sbc mdv_temp
	sta mdv_temp
md_trem_more_dec:
	sec
	lda chan_volume, x
	sbc mdv_temp
	sta mdv_temp
	rts
md_apply_vibrato:
	ldy chan_vibrato_pos, x
	lda md_lfo, y
	pha
	lda chan_vibrato_param, x
	and #$0F
	lsr a
	sta mdv_temp
	sec
	lda #$07
	sbc mdv_temp
	tay
	pla
	cpy #$00
	beq md_vib_no_iter
md_vib_iter:
	lsr a
	dey
	bne md_vib_iter
md_vib_no_iter:
	sta mdv_temp
	lda chan_vibrato_param, x
	and #$01
	bne md_vib_more_dec
	lda mdv_temp
	pha
	lsr a
	sta mdv_temp
	sec
	pla
	sbc mdv_temp
	sta mdv_temp
md_vib_more_dec:
	sec
	lda chan_freq_lo, x
	sbc mdv_temp
	sta mdv_temp_ptr
	lda chan_freq_hi, x
	sbc #$00
	sta mdv_temp_ptr + 1
	clc
	lda mdv_temp_ptr
	adc #$80
	sta mdv_temp_ptr
	lda mdv_temp_ptr + 1
	adc #$00
	sta mdv_temp_ptr + 1
	sec
	lda mdv_temp_ptr
	sbc chan_finepitch, x
	sta mdv_temp_ptr
	lda mdv_temp_ptr + 1
	sbc #$00
	sta mdv_temp_ptr + 1
	rts
md_kill_sweep:		; Kill the sweep unit
	lda #$C0
	sta $4017
	lda #$40
	sta $4017
	rts
md_trigger_sweep:
	
	rts
	
;
; It would be nice IF this worked on the most common NSF players
; But now it doesn't and thus it's disabled
;
.if 0 = 1

md_update_square1_hack:
	lda chan_prevfreq_hi
	cmp #$FF
	beq md_update_square1_hack_complete
	cmp chan_freq_hi
	beq md_update_square1_hack_ret
	bcs md_update_square1_hack_decrease
md_update_square1_hack_increase:
; increase
	lda #$40
	sta $4017
	lda #$FF
	sta $4002
	lda #$86
	sta $4001
	lda #$C0
	sta $4017
	sta $4017
	lda #$00
	sta $4017
	inc chan_prevfreq_hi
	
	lda chan_prevfreq_hi
	cmp chan_freq_hi
	beq md_update_square1_hack_set
	bcs md_update_square1_hack_increase
	
md_update_square1_hack_decrease:
; decrease
	lda #$40
	sta $4017
	lda #$00
	sta $4002
	lda #$8F
	sta $4001
	lda #$C0
	sta $4017
	sta $4017
	lda #$00
	sta $4017
	dec chan_prevfreq_hi

	lda chan_prevfreq_hi
	cmp chan_freq_hi
	beq md_update_square1_hack_set
	bcs md_update_square1_hack_decrease	
	
md_update_square1_hack_complete:
	lda chan_freq_hi
	sta chan_prevfreq_hi
	sta $4003
md_update_square1_hack_ret:
	rts
md_update_square1_hack_set:
	lda #$08
	sta $4001
	lda #$C0
	sta $4017
	lda #$00
	sta $4017
	lda chan_freq_lo
	sta $4002
	rts

.endif
	
md_update_channels:
	; Square 1
	ldx #$00
	jsr md_apply_vibrato
	jsr md_apply_tremolo
	sec
	lda mdv_temp
	sbc chan_damp_vol	
	bpl md_upd_ch1_novres
	lda #$00
md_upd_ch1_novres:
	sta mdv_temp
	lda chan_dutycycle					; update square 1
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	ora #$30
	ora mdv_temp
	sta $4000
	lda chan_sweep

	beq md_no_sweep_update1
	and #$80
	beq md_ch1_dont_update_low
	
	lda #$08					; Turn off sweep
	sta $4001
	jsr md_kill_sweep
	
	lda chan_sweep
	sta $4001
	and #$7F
	sta chan_sweep
	lda mdv_temp_ptr
	sta $4002
	lda mdv_temp_ptr + 1
	sta $4003
	lda #$FF
	sta chan_prevfreq_hi
	jsr md_kill_sweep
	jmp md_ch1_dont_update_low

md_no_sweep_update1:
	lda #$08					; Turn off sweep
	sta $4001
	jsr md_kill_sweep
	lda mdv_temp_ptr			; Load high freq-reg
	sta $4002
	lda mdv_temp_ptr + 1		; test if high should be
	cmp chan_prevfreq_hi
	beq md_ch1_dont_update_low
	sta $4003
	sta chan_prevfreq_hi
	;jsr md_update_square1_hack
md_ch1_dont_update_low:
	; Square 2
	ldx #$01
	jsr md_apply_vibrato
	jsr md_apply_tremolo
	sec
	lda mdv_temp
	sbc chan_damp_vol + 1
	bpl md_upd_ch2_novres
	lda #$00
md_upd_ch2_novres:
	sta mdv_temp
	lda chan_dutycycle + 1				; update square 2
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	ora #$30
	ora mdv_temp
	sta $4004
	lda chan_sweep + 1
	beq md_no_sweep_update2
	and #$80
	beq md_ch2_dont_update_low
	lda chan_sweep + 1
	sta $4005
	and #$7F
	sta chan_sweep + 1
	lda mdv_temp_ptr
	sta $4006
	lda mdv_temp_ptr + 1
	sta $4007
	lda #$FF
	sta chan_prevfreq_hi + 1
	jsr md_kill_sweep	
	jmp md_ch2_dont_update_low
md_no_sweep_update2:
	lda #$08							; turn off sweep
	sta $4005
	jsr md_kill_sweep
	lda mdv_temp_ptr					; low freq
	sta $4006
	lda mdv_temp_ptr + 1				; high freq
	cmp chan_prevfreq_hi + 1
	beq md_ch2_dont_update_low
	sta $4007
	sta chan_prevfreq_hi + 1
md_ch2_dont_update_low:
	; Triangle
	ldx #$02
	jsr md_apply_vibrato
	lda chan_volume + 2
	beq md_ch3_silent
	lda #%11000000						; update triangle
	sta $4008
	lda #$00
	sta $4009
	lda mdv_temp_ptr
	sta $400A
	lda mdv_temp_ptr + 1
	sta $400B
	jmp md_ch3_dont_update_low
md_ch3_silent:
	lda #$00
	sta $4008
	sta $4009
	sta $400A
	sta $400B
md_ch3_dont_update_low:
	sta chan_prevfreq_hi + 2
	; Noise	
	ldx #$03
	lda chan_note + 3
	beq md_upd_ch3_novres
	jsr md_apply_vibrato
	jsr md_apply_tremolo	
	sec
	lda mdv_temp
	sbc chan_damp_vol + 3
	bpl md_upd_ch3_novres
	lda #$00
md_upd_ch3_novres:
	ora #%00110000	
	sta $400C
	lda #$00
	sta $400D
	lda mdv_temp_ptr
	and #$0F							; cut freq above $0F
	eor #$0F							; and invert
	sta mdv_temp
	lda chan_dutycycle + 3				; add noise mode
	and #$01
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	ora mdv_temp
	sta $400E
	lda #$00
	sta $400F
;
; Update the DMC channel
;	
	lda chan_note + 4					; if note = 0 (halt), reset the DMC to regain full triangle volume
	beq md_ch5_reset_dmc
	lda chan_dpcm_length
	beq md_ch5_dont_update
	lda chan_dpcm_pitch
	and #$0F
	sta $4010							; DPCM pitch
	lda chan_dpcm_addr
	sta $4012							; DPCM address
	lda chan_dpcm_length
	sta $4013							; DPCM length
	lda #$0F
	sta $4015
	lda #$1F							; fire the sample
	sta $4015
	lda #$00
	sta chan_dpcm_length
	jmp md_ch5_dont_update
md_ch5_reset_dmc:
	lda #$00
	sta $4011
	lda #$0F
	sta $4015
md_ch5_dont_update:
	rts
;
; Instrument processing routines
;
md_process_instrument:					; update instrument settings
	lda chan_note, x
	beq md_proc_inst_rts
	cpx #$04							; no update on the DMC
	bne md_do_process
md_proc_inst_rts:
	rts
md_do_process:							; Do portamento
	lda chan_portaspeed, x				; if chan_portaspeed > 0 && chan_portato > 0
	;beq md_skip_porta
	bne md_do_portamento
	jmp md_skip_porta					; out of range
md_do_portamento:
	lda chan_portato_hi, x
	ora chan_portato_lo, x
	beq md_skip_porta
	lda chan_freq_hi, x					; compare high byte (num1 < num2, load num1)
	cmp chan_portato_hi, x
	bcc md_porta_inc					; if (num1 < num2)
	bne md_porta_dec					; if (num1 > num2)
	lda chan_freq_lo, x					; compare low byte
	cmp chan_portato_lo, x
	bcc md_porta_inc					; if (num1 < num2)
	bne md_porta_dec					; if (num1 > num2)
	jmp md_skip_porta					; no portamento
md_porta_dec:							; decrease frequency
	sec
	lda chan_freq_lo, x
	sbc chan_portaspeed, x
	sta chan_freq_lo, x
	lda chan_freq_hi, x
	sbc #$00
	sta chan_freq_hi, x
	bpl md_port_remove_sign
	lda #$00
	sta chan_freq_hi, x
	sta chan_freq_lo, x
md_port_remove_sign:
	lda chan_freq_hi, x					; compare high byte (num1 < num2, load num1)
	cmp chan_portato_hi, x
	bcc md_porta_limit					; if (num1 < num2)
	bne md_skip_porta					; if (num1 > num2)
	lda chan_freq_lo, x					; compare low byte
	cmp chan_portato_lo, x
	bcc md_porta_limit					; if (num1 < num2)
	bne md_skip_porta					; if (num1 > num2)	
md_porta_inc:							; increase frequency
	clc
	lda chan_freq_lo, x
	adc chan_portaspeed, x
	sta chan_freq_lo, x
	lda chan_freq_hi, x
	adc #$00
	sta chan_freq_hi, x
	lda chan_freq_hi, x					; compare high byte (num1 < num2, load num1)
	cmp chan_portato_hi, x
	bcc md_skip_porta					; if (num1 < num2)
	bne md_porta_limit					; if (num1 > num2)
	lda chan_freq_lo, x					; compare low byte
	cmp chan_portato_lo, x
	bcc md_skip_porta					; if (num1 < num2)
	bne md_porta_limit					; if (num1 > num2)	
md_porta_limit:
	lda chan_portato_hi, x
	sta chan_freq_hi, x
	lda chan_portato_lo, x
	sta chan_freq_lo, x
md_skip_porta:							; update sequences
	
; Track arpeggio
	lda chan_arp_val, x
	beq md_no_arp
	lda chan_arp_pos, x
	cmp #$00
	beq md_load_arp_first
	cmp #$01
	beq md_load_arp_second
	cmp #$02
	beq md_load_arp_third
md_load_arp_first:
	lda chan_orig_note, x
	sta chan_note, x
	jsr md_translate_note
	inc chan_arp_pos, x
	jmp md_no_arp
md_load_arp_second:
	lda chan_arp_val, x
	lsr a
	lsr a
	lsr a
	lsr a
	clc
	adc chan_orig_note, x
	sta chan_note, x
	jsr md_translate_note
	lda chan_arp_val, x
	and #$0F
	beq md_load_arp_reset
	inc chan_arp_pos, x
	jmp md_no_arp
md_load_arp_reset:
	lda #$00
	sta chan_arp_pos, x
	jmp md_no_arp
md_load_arp_third:
	lda chan_arp_val, x
	and #$0F
	clc
	adc chan_orig_note, x
	sta chan_note, x
	jsr md_translate_note
	lda #$00
	sta chan_arp_pos, x
	jmp md_no_arp
md_no_arp:
; Track vibrato
	lda chan_vibrato_param, x
	lsr a
	lsr a
	lsr a
	lsr a
	clc
	adc chan_vibrato_pos, x
	and #$3F
	sta chan_vibrato_pos, x
md_no_vibrato:
; Track tremolo
	lda chan_tremolo_param, x
	lsr a
	lsr a
	lsr a
	lsr a
	clc
	adc chan_tremolo_pos, x
	and #$3F
	sta chan_tremolo_pos, x
md_no_tremolo:
	proc_seq chan_len1, chan_modptr1	
	lda mdv_sequence_update
	beq md_skip_volume
	lda mdv_sequence_value
	sta chan_volume, x
md_skip_volume:
	proc_seq chan_len2, chan_modptr2
	lda mdv_sequence_update
	beq md_skip_arpeggio
	clc
	lda mdv_sequence_value
	adc chan_orig_note, x
	sta chan_note, x
	jsr md_translate_note
	
md_skip_arpeggio:
	proc_seq chan_len3, chan_modptr3
	lda mdv_sequence_update
	beq md_skip_pitch
	
	clc
	lda mdv_sequence_value
	adc chan_freq_lo, x
	sta chan_freq_lo, x
	
	lda mdv_sequence_value
	bpl md_pitch_load_no_neg
	lda #$FF
	bmi md_pitch_do_low
md_pitch_load_no_neg:
	lda #$00
md_pitch_do_low:
	adc chan_freq_hi, x
	sta chan_freq_hi, x
	jsr md_limit_freq
	
md_skip_pitch:
	proc_seq chan_len4, chan_modptr4
	lda mdv_sequence_update
	beq md_skip_hipitch
	lda mdv_sequence_value
	sta mdv_temp_ptr
	rol a
	bcc md_hipitch_add
	lda #$FF
	sta mdv_temp_ptr + 1
	jmp md_hipitch_store
md_hipitch_add:
	lda #$00
	sta mdv_temp_ptr + 1
md_hipitch_store:
	clc
	rol mdv_temp_ptr 						; multiply with $10
	rol mdv_temp_ptr + 1
	clc
	rol mdv_temp_ptr
	rol mdv_temp_ptr + 1
	clc
	rol mdv_temp_ptr
	rol mdv_temp_ptr + 1
	clc
	rol mdv_temp_ptr
	rol mdv_temp_ptr + 1
	clc	
	lda mdv_temp_ptr
	adc chan_freq_lo, x
	sta chan_freq_lo, x
	lda mdv_temp_ptr + 1
	adc chan_freq_hi, x
	sta chan_freq_hi, x
	jsr md_limit_freq	
md_skip_hipitch:
	proc_seq chan_len5, chan_modptr5
	lda mdv_sequence_update
	beq md_skip_dutycycle
	lda mdv_sequence_value
	sta chan_dutycycle, x
md_skip_dutycycle:
	rts
md_process_sequence:
	lda #$00
	sta mdv_sequence_update
	dec mdv_mod_len		
	lda mdv_mod_len
	bne md_skip_mod						; not yet time
	lda mdv_mod_ptr
	sta mdv_temp_ptr
	lda mdv_mod_ptr + 1
	sta mdv_temp_ptr + 1		
	beq md_skip_mod						; if the high order byte is zero, skip
md_mod_read_item:
	ldy #$00
	lda (mdv_temp_ptr), y				; first is length		; temp_ptr
	bne md_halt_mod
	lda #$00
	sta mdv_mod_len
	sta mdv_mod_ptr + 1
	jmp md_skip_mod
md_halt_mod:
	sta mdv_mod_len
	bmi md_loop_mod						; check if it should loop
	iny
	lda (mdv_temp_ptr), y				; second the actual value	; temp_ptr
	sta mdv_sequence_value
	lda #$01
	sta mdv_sequence_update	
	iny
	tya									; uppdate sequence pointer
	clc
	adc mdv_mod_ptr
	sta mdv_mod_ptr
	lda #$00
	adc mdv_mod_ptr + 1
	sta mdv_mod_ptr + 1
	jmp md_skip_mod

;
; This one below is problematic
;

md_loop_mod:		
	lda mdv_mod_len						; Convert from negative to positive
	eor #$FF
	asl a
	sta mdv_temp
	sec									; Subtract (16 bit)
	lda mdv_mod_ptr
	sbc mdv_temp
	sta mdv_mod_ptr
	lda mdv_mod_ptr + 1
	sbc #$00
	sta mdv_mod_ptr + 1
	lda #$01
	sta mdv_mod_len
	jmp md_process_sequence				; (change) get list item after loop instead of leaving (update: don't know what I mean, I'll leav it as is)
	
md_skip_mod:
	rts	
md_limit_freq:							; make sure the frequency doesn't exceed max or min
	lda chan_freq_hi, x
	bmi md_limit_min					; min
	cmp #$08							; max
	bmi md_no_limit
	lda #$07
	sta chan_freq_hi, x
	lda #$FF
	sta chan_freq_lo, x
	jmp md_no_limit
	md_limit_min:
	lda #$00
	sta chan_freq_lo, x
	sta chan_freq_hi, x
	md_no_limit:
	rts
md_load_frame:							; load pattern pointers
	lda mdv_frame
	asl a
	tay
	lda (mdv_frame_ptr), y
	sta mdv_pointer
	iny 
	lda (mdv_frame_ptr), y
	sta mdv_pointer + 1
md_load_frame_square1:					; start with square 1
	ldy #$00
	lda (mdv_pointer), y
	sta chan_pattern_ptr
	iny
	lda (mdv_pointer), y
	sta chan_pattern_ptr + 5
md_load_frame_square2:
	ldy #$02
	lda (mdv_pointer), y
	sta chan_pattern_ptr + 1
	iny
	lda (mdv_pointer), y
	sta chan_pattern_ptr + 6
md_load_frame_triangle:
	ldy #$04
	lda (mdv_pointer), y
	sta chan_pattern_ptr + 2
	iny
	lda (mdv_pointer), y
	sta chan_pattern_ptr + 7
md_load_frame_noise:
	ldy #$06
	lda (mdv_pointer), y
	sta chan_pattern_ptr + 3
	iny
	lda (mdv_pointer), y
	sta chan_pattern_ptr + 8
md_load_frame_dmc:
	ldy #$08
	lda (mdv_pointer), y
	sta chan_pattern_ptr + 4
	iny
	lda (mdv_pointer), y
	sta chan_pattern_ptr + 9
	lda #$00
	sta chan_rle + 0
	sta chan_rle + 1
	sta chan_rle + 2
	sta chan_rle + 3
	sta chan_rle + 4
	rts
md_trigger_note:
	cpx #$04
	beq md_was_dpcm
	lda chan_portaspeed, x
	bne md_porta_to_note
	jsr md_translate_note
md_was_dpcm:
	rts
md_porta_to_note:
	lda chan_freq_lo, x
	pha
	lda chan_freq_hi, x
	pha
	jsr md_translate_note
	lda chan_freq_hi, x
	sta chan_portato_hi, x
	lda chan_freq_lo, x
	sta chan_portato_lo, x
	pla
	sta chan_freq_hi, x
	pla
	sta chan_freq_lo, x	
	lda chan_freq_lo, x
	ora chan_freq_hi, x
	beq md_trigger_load					; load frequency if previous note was a halt
	rts

md_trigger_dpcm:						; Loads a DPCM sample	
	tya
	pha
	
	lda chan_inst, x					; Get the DPCM instrument
	
	asl a
	tay
	lda (mdv_inst_dpcm_ptr), y			; Store it at the DPCM inst pointer

	sta mdv_dpcm_inst

	iny
	lda (mdv_inst_dpcm_ptr), y
	sta mdv_dpcm_inst + 1
	lda chan_note, x					; Note, actually DPCM sample index
	sec									; Assume chan_note points to a valid sample
	sbc #$02
	tay
	lda (mdv_dpcm_inst), y				; Get the DPCM note
	asl a

	pha									; Store it for later
	iny
	lda (mdv_dpcm_inst), y 				; Get the DPCM pitch
	sta chan_dpcm_pitch					; Store it in current DPCM pitch
	
	pla									; Fetch the DPCM address and length
	tay
	lda (mdv_dpcm_ptr), y				; Address
	sta chan_dpcm_addr
	iny
	lda (mdv_dpcm_ptr), y				; Length
	sta chan_dpcm_length
	
	pla
	tay
	rts
	
md_trigger_load:
	lda chan_portato_lo, x
	sta chan_freq_lo, x
	lda chan_portato_hi, x
	sta chan_freq_hi, x
	rts
md_translate_note:						; translate a note into a frequency
	cpx #$03
	beq md_translate_noise
	lda chan_note, x
	asl A
	sty mdv_temp
	tay
	lda (mdv_note_lookup), y
	sta chan_freq_lo, x
	iny
	lda (mdv_note_lookup), y
	sta chan_freq_hi, x
	ldy mdv_temp
	rts
md_translate_noise:						; do a direct note -> noise translation
	lda chan_note, x
	sta chan_freq_lo, x
	lda #$00
	sta chan_freq_hi, x
	rts
md_notes_ntsc:
	.incbin "freq_ntsc.bin"				; frequency lookup tables
md_notes_pal:
	.incbin "freq_pal.bin"
md_lfo:									; LFO, sine wave
	.byte $00, $00, $02, $05, $0A, $0F, $16, $1D
	.byte $26, $30, $3A, $45, $51, $5D, $69, $76
	.byte $83, $8F, $9C, $A8, $B4, $BF, $CA, $D4
	.byte $DD, $E6, $ED, $F3, $F8, $FC, $FE, $FF
	.byte $FF, $FE, $FC, $F8, $F3, $ED, $E6, $DD
	.byte $D4, $CA, $C0, $B4, $A8, $9C, $8F, $83
	.byte $76, $69, $5D, $51, $45, $3A, $30, $26
	.byte $1D, $16, $0F, $0A, $05, $02, $00, $00
; ACC*AUX -> [ACC,EXT] (low,hi) 32 bit result	
MULT:	  LDA #0
          STA EXT+1
          LDY #$11
	  CLC
LOOP1:    ROR EXT+1
          ROR
          ROR ACC+1
          ROR ACC
          BCC MUL2
          CLC
          ADC AUX
          PHA
          LDA AUX+1
          ADC EXT+1
          STA EXT+1
          PLA
MUL2:     DEY
          BNE LOOP1
          STA EXT
          RTS
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
	.asciiz VERSION
;
; Here shall the song data be included
;
	.segment "MUSIC"
SongData:
.if SRC_MAKE_NSF = 1
	.incbin "music.bin"
.elseif SRC_MAKE_NES = 1
	.incbin "music.bin"
.endif

	.segment "DPCM"
.if SRC_MAKE_NSF = 1
	.incbin "samples.bin"
.elseif SRC_MAKE_NES = 1
	.incbin "samples.bin"
.endif

.if SRC_MAKE_NES = 1
;
; Following code is from Nullsleep's guide since it works well
;
RESET:
	cld			; clear decimal flag
	sei			; disable interrupts
	lda #%00000000		; disable vblank interrupts by clearing
	sta $2000		; the most significant bit of $2000
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
IRQ:
	rti			; return from interrupt routine
	.segment "VECTORS"
	.word NMI, RESET, IRQ

.endif