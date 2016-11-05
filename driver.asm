;
; The NSF music driver for FamiTracker
; Version 1.5
; assemble with ca65
;
; Recent changes
;   - Fixed a bug that caused sequences starting at $xxFF to fail
;   - Fixed fast pitch changing note
;   - Sequence loops failed when a 256-bytes page was crossed (as I suspected), that's fixed
;   - Added channel volume support
;   - DPCM samples to note assignment added
;   - Some other changes...
;  -----
;   - Noise; play notes as in the tracker
;  -----
;   - Items after a sequence loop are executed immediately
;   - Automatic portamento is fixed, reset every channel on player start
;
; This code is not very optimized, average CPU usage is around 10%
;
; Todo:
;  Clean up (after 1.5 release)
;  Compress pattern-zeroes (there would be lot of space to save)
;  Optimize!
;

.define VERSION         "FT-NSF-drv v1.5"

; Source switches
;
SRC_MAKE_NSF			= 0			; 1 = create NSF, 0 = produce raw code

; End of header
;
; Driver constants
;
SONG_OFFSET 			= $8B00		; where the music will be

SONG_SPEED				= SONG_OFFSET
SONG_FRAME_CNT			= SONG_OFFSET + 1
SONG_PAT_LENGTH			= SONG_OFFSET + 2
SONG_INST_PTR			= SONG_OFFSET + 3
SONG_INST_DPCM_PTR		= SONG_OFFSET + 5
SONG_SEQ_PTR			= SONG_OFFSET + 7
SONG_FRAME_PTR			= SONG_OFFSET + 9
SONG_DPCM_PTR			= SONG_OFFSET + 11

; Macros
;
.macro proc_seq len, modptr
	lda len, x
	sta mdv_mod_len
	lda modptr, x
	sta mdv_mod_ptr
	lda modptr + 5, x
	sta mdv_mod_ptr + 1
	jsr md_process_sequence
	lda mdv_mod_len
	sta len, x
	lda mdv_mod_ptr
	sta modptr, x
	lda mdv_mod_ptr + 1
	sta modptr + 5, x	
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

.segment "BSS"

; Player variables, not zero-page
;
mdv_playing:			.res 1		; 1 is playing, 2 = PAL
mdv_temp:				.res 1
mdv_pattern_length:		.res 1
mdv_instrument:			.res 1
mdv_frame:				.res 1		; current frame
mdv_frame_count:		.res 1		; amount of frames before reset
mdv_patternpos:			.res 1
mdv_duration:			.res 1
mdv_mod_len:			.res 1
mdv_sequence_value:		.res 1
mdv_sequence_update:	.res 1
mdv_speed:				.res 1
mdv_jump_to:			.res 1
mdv_seek_to:			.res 1
mdv_nsf_frame:			.res 1
mdv_volume:				.res 1
mdv_sweep:				.res 1

; Channel variables
;
chan_pattern_ptr:		.res 10
chan_pattern_pos:		.res 5
chan_note:				.res 5
chan_inst:				.res 5
chan_orig_note:			.res 5
chan_freq_lo:			.res 5		; 0 - 255
chan_freq_hi:			.res 5		; 0 - 3
chan_prevfreq_hi:		.res 5		; DMC: pattern address
chan_volume:			.res 5		; DMC: pattern length
chan_damp_vol:			.res 5		; volume damping, (the volume column)
chan_dutycycle:			.res 5		; square / noise
chan_modptr1:			.res 10		; volume
chan_modptr2:			.res 10		; arpeggio
chan_modptr3:			.res 10		; pitch
chan_modptr4:			.res 10		; hi-pitch
chan_modptr5:			.res 10		; duty cycle
chan_len1:				.res 5
chan_len2:				.res 5
chan_len3:				.res 5
chan_len4:				.res 5
chan_len5:				.res 5
chan_portato_lo:		.res 5
chan_portato_hi:		.res 5
chan_portaspeed:		.res 5
chan_sweep:				.res 2		; only avaliable on the square channels

chan_dpcm_pitch:		.res 1
chan_dpcm_addr:			.res 1
chan_dpcm_length:		.res 1

; Uncomment these if you want an NSF
;
.if SRC_MAKE_NSF = 1
	.segment "HEADER"
	.incbin "header.bin"
.endif

	.segment "CODE"
LOAD:
INIT:
	jmp	sound_init
PLAY:
	jmp	sound_driver
;
; Player init code
;
;  a = song number (currently thrown away, multisong tunes will come)
;  x = ntsc/pal
;
sound_init:								; NSF init
	lda SONG_SPEED						; speed
	sta mdv_speed
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
	sta chan_sweep + 1
	sta chan_sweep + 2
	sta mdv_jump_to
	lda #$01
	sta mdv_duration
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
	lda #$FF
	sta chan_prevfreq_hi, x
	lda #$00
	sta chan_portato_hi, x
	sta chan_portato_lo, x
	sta chan_freq_hi, x
	sta chan_freq_lo, x
	;lda #$0F
	;sta chan_damp_vol, x
	cpx #$03
	bne md_reset_chan
	lda #$0F
	sta $4015
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
	dec mdv_duration
	ldx #$FF
md_loop_channels:						; update all channels
	inx									; current channel is stored in x
	cpx #$05
	bne md_chan_not_done
	jmp md_end
	md_chan_not_done:
	lda mdv_duration
	beq md_process_channel
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
	lda (mdv_pointer), y				; read note/effect/command
	bmi md_note_effect					; was an effect/command		
	beq md_no_note						; no new note
		cmp #$7F							; note halt
		beq md_note_halt
			iny
			sta chan_note, x					; save note/octave
			sta chan_orig_note, x
			jsr md_trigger_note
			jsr md_reload_instrument
			lda #$0F
			sta chan_volume, x
			jmp md_note_end
	md_note_halt:
		iny
		lda #$00
		sta chan_volume, x
		sta chan_note, x
		sta chan_portato_hi, x
		sta chan_portato_lo, x
		sta chan_freq_hi, x
		sta chan_freq_lo, x
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
		
md_effects:
	.word md_instchange, md_volchange
	.word md_effect_speed
	.word md_effect_jump, md_effect_skip
	.word md_effect_halt, md_effect_volume
	.word md_effect_portaon, md_effect_portaoff
	.word md_effect_sweep

md_instchange:
	lda (mdv_pointer), y				; get instrument number
	iny
	sta chan_inst, x
	jsr md_reload_instrument			; load specific sequences
	jmp md_get_pattern_data				; see if a note is next
md_volchange:
	lda (mdv_pointer), y				; get volume
	iny
	sta chan_damp_vol, x
	jmp md_get_pattern_data

md_effect_speed:
	lda (mdv_pointer), y
	iny
	clc
	adc #$01
	sta mdv_speed
	jmp md_get_pattern_data
md_effect_jump:
	lda (mdv_pointer), y
	iny
	sta mdv_jump_to
	jmp md_get_pattern_data
md_effect_skip:
	lda (mdv_pointer), y
	iny
	clc
	adc #$01
	sta mdv_seek_to
	jmp md_get_pattern_data
md_effect_halt:
	jmp md_halt
md_effect_volume:
	lda (mdv_pointer), y
	iny
	sta chan_volume, x
	sta mdv_volume
	jmp md_get_pattern_data
md_effect_portaon:
	lda (mdv_pointer), y
	iny
	sta chan_portaspeed, x
	jmp md_get_pattern_data
md_effect_portaoff:
	lda (mdv_pointer), y
	iny
	lda #$00
	sta chan_portaspeed, x
	jmp md_get_pattern_data
md_effect_sweep:
	txa
	cmp #$02
	bpl md_sweep_nosq
	lda (mdv_pointer), y
	iny
	sta mdv_sweep
	jmp md_get_pattern_data
md_sweep_nosq:
	iny
	jmp md_get_pattern_data	
md_note_end:
	lda mdv_sweep
	beq md_no_sweep
	sta chan_sweep, x
	lda #$00
	sta chan_prevfreq_hi, x
md_no_sweep:
	lda mdv_speed
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
	lda mdv_speed
	sta mdv_duration
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
	lda mdv_speed
	sta mdv_duration
	lda #$00
	sta mdv_seek_to
	jmp md_no_refresh_duration
md_no_seek:
	lda mdv_duration
	bne md_no_refresh_duration
	lda mdv_speed
	sta mdv_duration
	dec mdv_patternpos					; check if all entries in one pattern has been played
	lda mdv_patternpos
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
	lda (mdv_pointer), y
	bpl md_seek_no_cmd
	cmp #$80
	bne md_seek_no_inst
	iny
	lda (mdv_pointer), y
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
md_reload_instrument:					; load instruments
	cpx #$04
	bne	md_no_dmc
	;lda chan_note, x
	;beq md_no_dmc
	;jsr md_reload_dmc
	;rts
	jmp md_trigger_dpcm
md_no_dmc:
	lda mdv_volume
	sta chan_volume, x
	lda #$00
	sta chan_dutycycle, x
	sta chan_modptr1, x
	sta chan_modptr1 + 5, x
	sta chan_modptr2, x
	sta chan_modptr2 + 5, x
	sta chan_modptr3, x
	sta chan_modptr3 + 5, x
	sta chan_modptr4, x
	sta chan_modptr4 + 5, x
	sta chan_modptr5, x
	sta chan_modptr5 + 5, x
	tya									; save pattern ptr
	pha
	lda chan_inst, x
	asl a
	tay
	lda (mdv_inst_ptr), y				; get a pointer to the instrument data
	sta mdv_temp_ptr					; mdv_temp_ptr will point to the instrument
	iny
	lda (mdv_inst_ptr), y
	sta mdv_temp_ptr + 1				; effect 1, volume
	ldy #$00							; read and store
	lda (mdv_temp_ptr), y				; first sequence, volume
	beq md_skip_vol_mod
	sec
	sbc #01								; remove one to get the real sequence (a zero marks no sequence)
	asl	a								; multiply with 2
	tay
	lda (mdv_seq_ptr), y				; get the pointer and store it for the channel
	sta chan_modptr1, x
	iny
	lda (mdv_seq_ptr), y
	sta chan_modptr1 + 5, x
;	inc chan_modptr1, x					; start at the list (first value contains lenght)
md_skip_vol_mod:						; effect 2, arpeggio
	ldy #$01							; second sequence, arpeggio
	lda (mdv_temp_ptr), y				; 
	beq md_skip_arp_mod
	sec
	sbc #01								; remove one to get the real sequence (a zero marks no sequence)
	asl	a								; multiply with 2
	tay
	lda (mdv_seq_ptr), y
	sta chan_modptr2, x
	iny
	lda (mdv_seq_ptr), y
	sta chan_modptr2 + 5, x
;	inc chan_modptr2, x					; start at the list (first value contains lenght)
md_skip_arp_mod:
	ldy #$02							; third sequence, pitch
	lda (mdv_temp_ptr), y				; 
	beq md_skip_pitch_mod
	sec
	sbc #01								; remove one to get the real sequence (a zero marks no sequence)
	asl	a								; multiply with 2
	tay
	lda (mdv_seq_ptr), y
	sta chan_modptr3, x
	iny
	lda (mdv_seq_ptr), y
	sta chan_modptr3 + 5, x
;	inc chan_modptr3, x					; start at the list (first value contains lenght)
md_skip_pitch_mod:
	ldy #$03							; fourth sequence, high pitch
	lda (mdv_temp_ptr), y				; 
	beq md_skip_hipitch_mod
	sec
	sbc #01								; remove one to get the real sequence (a zero marks no sequence)
	asl	a								; multiply with 2
	tay
	lda (mdv_seq_ptr), y
	sta chan_modptr4, x
	iny
	lda (mdv_seq_ptr), y
	sta chan_modptr4 + 5, x
;	inc chan_modptr4, x					; start at the list (first value contains lenght)
md_skip_hipitch_mod:
	ldy #$04							; fifth sequence, duty cycle
	lda (mdv_temp_ptr), y				; 
	beq md_skip_dutycycle_mod
	sec
	sbc #01								; remove one to get the real sequence (a zero marks no sequence)
	asl	a								; multiply with 2
	tay
	lda (mdv_seq_ptr), y
	sta chan_modptr5, x
	iny
	lda (mdv_seq_ptr), y
	sta chan_modptr5 + 5, x
	;inc chan_modptr5, x					; start at the list (first value contains lenght)
md_skip_dutycycle_mod:
	lda #$01
	sta chan_len1, x
	sta chan_len2, x
	sta chan_len3, x
	sta chan_len4, x
	sta chan_len5, x
	pla									; restore pattern ptr
	tay
	cpx #$00
	beq md_inst_sweep
	cpx #$01
	beq md_inst_sweep
	rts
md_inst_sweep:
	lda #$00
	sta chan_sweep, x
md_inst_ret:
	rts
md_reload_dmc:							; load the DMC
;	tya
;	pha
;	lda chan_inst, x
;	asl a
;	tay
;	lda (mdv_dpcm_ptr), y
;	sta chan_prevfreq_hi, x				; DMC sample pos
;	iny
;	lda (mdv_dpcm_ptr), y
;	sta chan_volume, x					; DMC sample length
;	lda chan_orig_note, x
;	and #$0F
;	sta chan_freq_lo, x
;	lda chan_orig_note, x
;	cmp #$48							; above fith octave
;	bmi md_no_dmc_loop
;	lda chan_freq_lo, x
;	ora #$40
;	sta chan_freq_lo, x
;md_no_dmc_loop:
;	pla
;	tay
	rts
md_update_channels:
	sec
	lda chan_volume
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
	beq md_ch1_update_freq
	lda chan_sweep
	sta $4001
	and #$7F
	sta chan_sweep
	lda chan_freq_lo
	sta $4002
	lda chan_freq_hi
	sta $4003
	lda #$FF
	sta chan_prevfreq_hi
	jmp md_ch1_update_freq
md_no_sweep_update1:
	lda #$08
	sta $4001
	lda chan_freq_lo
	sta $4002
md_ch1_update_freq:
	lda chan_freq_hi
	cmp chan_prevfreq_hi
	beq md_ch1_dont_update_low
	sta $4003
	sta chan_prevfreq_hi
md_ch1_dont_update_low:
	sec
	lda chan_volume + 1
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
	beq md_ch2_update_freq
	lda chan_sweep + 1
	sta $4005
	and #$7F
	sta chan_sweep + 1
	lda chan_freq_lo + 1
	sta $4006
	lda #$FF
	sta chan_prevfreq_hi + 1
	jmp md_ch2_update_freq
md_no_sweep_update2:
	lda #$08
	sta $4005
	lda chan_freq_lo + 1
	sta $4006
md_ch2_update_freq:
	lda chan_freq_hi + 1
	cmp chan_prevfreq_hi + 1
	beq md_ch2_dont_update_low
	sta $4007
	sta chan_prevfreq_hi + 1
md_ch2_dont_update_low:
	lda chan_volume + 2
	beq md_ch3_silent
	lda #%11000000						; update triangle
	sta $4008
	lda #$04
	sta $4009
	lda chan_freq_lo + 2
	sta $400A
	lda chan_freq_hi + 2
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
	lda #%00110000						; update noise
	ora chan_volume + 3
	sta $400C
	lda #$00
	sta $400D
	lda chan_freq_lo + 3
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
	lda chan_dpcm_length	
	beq md_ch5_dont_update
	lda chan_note + 4					; if note = 0 (halt), reset the DMC to regain full triangle volume
	beq md_ch5_reset_dmc
	lda chan_dpcm_pitch
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
md_ch5_dont_update:
	rts
	
md_process_instrument:					; update instrument settings
	lda chan_note, x
	beq md_proc_inst_rts
	cpx #$04							; no update on the DMC
	bne md_do_process
md_proc_inst_rts:
	rts
md_do_process:							; Do portamento
	lda chan_portaspeed, x				; if chan_portaspeed > 0 && chan_portato > 0
	beq md_skip_porta
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
	rts
md_trigger_note:
	cpx #$04
	bne md_not_dpcm
	;jmp md_trigger_dpcm
md_not_dpcm:
	lda chan_portaspeed, x
	bne md_porta_to_note
	jsr md_translate_note
	;lda #$00
	;sta chan_dutycycle, x
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
	lda chan_note,x						; Note, actually DPCM sample index
	sec									; Assume chan_note points to a valid sample
	sbc #$02
	sta $1300
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
	.asciiz VERSION
;
; Here shall the song data be included
;
	.segment "MUSIC"
SongData:
	.include "musicdata.asm"
