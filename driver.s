;
; The NSF music driver for FamiTracker
; Version 2.4
; By jsr (zxy965r@tninet.se)
; assemble with ca65
;
; Documentation is in readme.txt
; 
; Tab stop is 4
;

;
; ToDo; 
;

;
; Assembler code switches
;

USE_BANKSWITCH = 1		; Enable bankswitching code
USE_DPCM = 1			; Enable DPCM channel (currently broken, leave enabled to avoid trouble). 
						; Leave enabled for expansion chips

NTSC_PERIOD_TABLE = 1	; Enable this to include the NTSC period table
PAL_PERIOD_TABLE = 1	; Enable this to include the PAL period table

ENABLE_ROW_SKIP = 1		; Enable this to add code for seeking to a row > 0 when using skip command

;USE_VRC6 = 1 			; Enable this to include VRC6 code
;USE_MMC5 = 1			; Enable this to include MMC5 code
;USE_VRC7 = 1			; Enable this to include VRC7 code
;USE_FDS = 1			; Enable this to include FDS code
;USE_N106 = 1			; Enable this to include N106 code
;USE_5B = 1				; Enable this to include 5B code

;ENABLE_SFX = 1			; Enable this to enable sound effect support (not yet working)



;
; Constants
;
TUNE_PATTERN_LENGTH		= $00
TUNE_FRAME_LIST_POINTER	= $01

; Setup the pattern number -> channel mapping, as exported by the tracker

.if .defined(USE_VRC6)			; 2A03 + VRC6 channels
	CHANNELS		= 8
	DPCM_CHANNEL	= 7
	VRC6_CHANNELS	= 4						; Start of VRC channels
	SAW_CHANNEL		= VRC6_CHANNELS + 2		; Saw channel
	WAVE_CHANS 		= CHANNELS - 1
.elseif .defined(USE_VRC7)		; 2A03 + VRC7 channels
	CHANNELS		= 11
	DPCM_CHANNEL	= 10
	WAVE_CHANS 		= 4
	VRC7_CHANNEL	= 4
.elseif .defined(USE_MMC5)		; 2A03 + MMC5 channels
	CHANNELS		= 7
	DPCM_CHANNEL	= 6
	WAVE_CHANS 		= CHANNELS - 1
.elseif .defined(USE_FDS)		; 2A03 + FDS
	CHANNELS		= 6
	DPCM_CHANNEL	= 5
	FDS_CHANNEL		= 4
	WAVE_CHANS		= CHANNELS - 1
.else							; 2A03 channels
	.ifdef USE_DPCM
		CHANNELS	 = 5
		DPCM_CHANNEL = 4
		WAVE_CHANS 	 = CHANNELS - 1
	.else
		CHANNELS	 = 4
		WAVE_CHANS 	 = CHANNELS
	.endif
.endif

EFF_CHANS = CHANNELS - 1		; # of channels using vibrato & arpeggio effects (not used by DPCM)

; Number of wave channels
;.ifdef USE_DPCM
;	WAVE_CHANS = CHANNELS - 1
;.else
;	WAVE_CHANS = CHANNELS
;.endif

; Noise channel
NOISE_CHANNEL = 3

;.if .defined(ENABLE_SFX)
;	SFX_CHANS		= CHANNELS * 2
;	SFX_WAVE_CHANS 	= WAVE_CHANS * 2
;.else
	SFX_CHANS		= CHANNELS
	SFX_WAVE_CHANS 	= WAVE_CHANS
;.endif

; Header item offsets
HEAD_SPEED				= 11
HEAD_TEMPO				= 12

;SPEED_DIV_NTSC			= 60 * 60;
;SPEED_DIV_PAL			= 60 * 50;

EFF_ARPEGGIO			= 1
EFF_PORTAMENTO			= 2
EFF_PORTA_UP			= 3
EFF_PORTA_DOWN			= 4
EFF_SLIDE_UP_LOAD		= 5
EFF_SLIDE_UP			= 6
EFF_SLIDE_DOWN_LOAD		= 7
EFF_SLIDE_DOWN			= 8

.segment "ZEROPAGE"

;
; Variables that must be on zero-page
;
var_Temp:				.res 1						; Temporary 8-bit
var_Temp2:				.res 1
var_Temp3:				.res 1
var_Temp16:				.res 2						; Temporary 16-bit 
var_Temp_Pointer:		.res 2						; Temporary
var_Temp_Pattern:		.res 2						; Pattern address (temporary)
var_Note_Table:			.res 2
var_Temp_Inst:			.res 1

ACC:					.res 2						; Used by division routine
AUX:					.res 2
EXT:					.res 2

.ifdef USE_FDS
var_Wave_pointer:		.res 2
.endif
.ifdef USE_VRC7
var_Period:				.res 2
.endif

last_zp_var:			.res 1						; Not used


.segment "BSS"

;
; Driver variables
;

; Song header (necessary to be in order)
var_Song_list:			.res 2						; Song list address
var_Instrument_list:	.res 2						; Instrument list address
.ifdef USE_DPCM
var_dpcm_inst_list:		.res 2						; DPCM instruments
var_dpcm_pointers:		.res 2						; DPCM sample pointers
.endif
var_SongFlags:			.res 1						; Song flags, bit 0 = bankswitched, bit 1 = old vibrato, bit 2 - 7 = unused
.ifdef USE_FDS
var_Wavetables:			.res 2						; FDS waves
.endif

var_Channels:			.res 1						; Channel enable/disable
	
; Track header (necessary to be in order)
var_Frame_List:			.res 2						; Pattern list address
var_Frame_Count:		.res 1						; Number of frames
var_Pattern_Length:		.res 1						; Global pattern length
var_Speed:				.res 1						; Speed setting
var_Tempo:				.res 1						; Tempo setting
var_InitialBank:		.res 1

; General
var_PlayerFlags:		.res 1						; Player flags, bit 0 = playing, bit 1 - 7 unused
var_Pattern_Pos:		.res 1						; Global pattern row
var_Current_Frame:		.res 1						; Current frame
var_Load_Frame:			.res 1						; 1 if new frame should be loaded

var_Tempo_Accum:		.res 2						; Variables for speed division
var_Tempo_Count:		.res 2						;  (if tempo support is not needed then this can be optimized)
var_Tempo_Dec:			.res 2
var_VolTemp:			.res 1						; So the Exx command will work
var_Sweep:				.res 1						; This has to be saved

.ifdef USE_BANKSWITCH
var_Bank:				.res 1
.endif
var_Jump:				.res 1						; If a Jump should be executed
var_Skip:				.res 1						; If a Skip should be executed
.ifdef ENABLE_ROW_SKIP
var_SkipTo:				.res 1						; Skip to row number
.endif

var_sequence_ptr:		.res 1
var_sequence_result:	.res 1

;var_enabled_channels:	.res 1

; Channel variables

; General channel variables, used by the pattern reader (all channels)
var_ch_Pattern_addr:	.res CHANNELS * 2			; Holds current pattern address and position in it
.ifdef USE_BANKSWITCH
var_ch_Bank:			.res CHANNELS				; Pattern bank
.endif
var_ch_Note:			.res CHANNELS				; Current channel note
var_ch_VolColumn:		.res CHANNELS				; Volume column
var_ch_Delay:			.res CHANNELS				; Delay command
var_ch_NoteCut:			.res CHANNELS
var_ch_State:			.res CHANNELS
var_ch_FinePitch:		.res CHANNELS				; Fine pitch setting

var_ch_NoteDelay:		.res CHANNELS				; Delay in rows until next note
var_ch_DefaultDelay:	.res CHANNELS				; Default row delay, if exists
	
; Following is specific to chip channels (2A03, VRC6...)

var_ch_TimerPeriod:		.res EFF_CHANS * 2			; Current channel note period
var_ch_TimerCalculated:	.res EFF_CHANS * 2			; Frequency after fine pitch and vibrato has been applied
var_ch_OutVolume:		.res CHANNELS				; Volume for the APU
var_ch_VolSlide:		.res CHANNELS				; Volume slide

; --- Testing --- 
;var_ch_LoopCounter:		.res CHANNELS
; --- Testing --- 

; Square 1 & 2 variables
var_ch_Sweep:			.res 2						; Hardware sweep
var_ch_PrevFreqHigh:	.res 2						; Used only by 2A03 pulse channels

; Sequence variables
var_ch_SeqVolume:		.res SFX_WAVE_CHANS * 2		; Sequence 1: Volume
var_ch_SeqArpeggio:		.res SFX_WAVE_CHANS * 2		; Sequence 2: Arpeggio
var_ch_SeqPitch:		.res SFX_WAVE_CHANS * 2		; Sequence 3: Pitch bend
var_ch_SeqHiPitch:		.res SFX_WAVE_CHANS * 2		; Sequence 4: High speed pitch bend
var_ch_SeqDutyCycle:	.res SFX_WAVE_CHANS * 2		; Sequence 5: Duty cycle / Noise Mode
var_ch_Volume:			.res SFX_WAVE_CHANS			; Output volume
var_ch_DutyCycle:		.res SFX_WAVE_CHANS			; Duty cycle / Noise mode
var_ch_SequencePtr1:	.res SFX_WAVE_CHANS			; Index pointers for sequences
var_ch_SequencePtr2:	.res SFX_WAVE_CHANS
var_ch_SequencePtr3:	.res SFX_WAVE_CHANS
var_ch_SequencePtr4:	.res SFX_WAVE_CHANS
var_ch_SequencePtr5:	.res SFX_WAVE_CHANS

; Track variables for effects
var_ch_Effect:			.res EFF_CHANS				; Arpeggio & portamento
var_ch_EffParam:		.res EFF_CHANS				; Effect parameter (used by portamento and arpeggio)

var_ch_PortaTo:			.res EFF_CHANS * 2			; Portamento
var_ch_ArpeggioCycle:	.res EFF_CHANS				; Arpeggio cycle

var_ch_VibratoPos:		.res EFF_CHANS				; Vibrato
var_ch_VibratoDepth:	.res EFF_CHANS		
var_ch_VibratoSpeed:	.res EFF_CHANS
var_ch_TremoloPos:		.res EFF_CHANS				; Tremolo
var_ch_TremoloDepth:	.res EFF_CHANS				; combine these
var_ch_TremoloSpeed:	.res EFF_CHANS

;var_ch_VibratoParam:	.res WAVE_CHANS
;var_ch_TremoloParam:	.res WAVE_CHANS

; DPCM variables
.ifdef USE_DPCM
var_ch_SamplePtr:		.res 1						; DPCM sample pointer
var_ch_SampleLen:		.res 1						; DPCM sample length
var_ch_SamplePitch:		.res 1						; DPCM sample pitch
var_ch_DPCMDAC:			.res 1						; DPCM delta counter setting
var_ch_DPCM_Offset:		.res 1	
var_ch_DPCM_Retrig:		.res 1						; DPCM retrigger
var_ch_DPCM_RetrigCntr:	.res 1
.endif

.ifdef USE_MMC5
var_ch_PrevFreqHighMMC5: 	.res 2					; MMC5
.endif

.ifdef USE_VRC7
var_ch_CustomPatch:		.res 1						; Keep track of the custom patch
var_ch_Patch:			.res 6						; VRC7 patch
var_ch_Fnum:			.res 6 * 2
var_ch_Bnum:			.res 6
var_ch_ActiveNote:		.res 6
var_ch_Command:			.res 6						; 0 = halt, 1 = trigger, 80 = update
var_ch_OldOctave:		.res 1						; Temp variable for old octave when triggering new notes
.endif

.ifdef USE_FDS
var_ch_Wave:			.res 1						; Index to wave table
var_ch_ModDelay:		.res 1
var_ch_ModDepth:		.res 1
var_ch_ModRate:			.res 2
var_ch_ModDelayTick:	.res 1
.endif

; End of variable space
last_bss_var:			.res 1						; Not used


.segment "CODE"

; NSF entry addresses

LOAD:
INIT:
	jmp	ft_music_init
PLAY:
	jmp	ft_music_play

; Disable channel in X, X = {00 : Square 1, 01 : Square 2, 02 : Triangle, 03 : Noise, 04 : DPCM}
ft_disable_channel:
	lda ft_channel_mask, x
	eor #$FF
	and var_Channels
	sta var_Channels
	rts

; Enable channel in X
ft_enable_channel:
	lda ft_channel_mask, x
	ora var_Channels
	sta var_Channels
	lda #$FF
	cpx #$00
	beq :+
	cpx #$01
	beq :++
	rts
:	sta var_ch_PrevFreqHigh
	rts
:	sta var_ch_PrevFreqHigh + 1
	rts

ft_channel_mask:
	.byte $01, $02, $04, $08, $10

; The rest of the code
	.include "init.s"
	.include "player.s"
	.include "effects.s"
	.include "instrument.s"
	.include "apu.s"

.ifdef USE_VRC6
	.include "vrc6.s"
.endif
.ifdef USE_VRC7
	.include "vrc7.s"	
.endif
.ifdef USE_MMC5
	.include "mmc5.s"
.endif
.ifdef USE_FDS
	.include "fds.s"
.endif
.ifdef USE_N106
	.include "n106.s"
.endif

.ifdef PAL_PERIOD_TABLE
ft_notes_pal:							; Note periods for PAL (remove this if you don't need PAL support)
	.incbin "freq_pal.bin"
.endif

.ifdef NTSC_PERIOD_TABLE
ft_notes_ntsc:							; Note periods for NTSC (remove this if you don't need NTSC support)
	.incbin "freq_ntsc.bin"
.endif

.ifdef USE_VRC6
ft_periods_sawtooth:
	.incbin "freq_sawtooth.bin"			; Note periods for VRC6 sawtooth
.endif

.ifdef USE_FDS
ft_periods_fds:
	.incbin "freq_fds.bin"				; Note periods for FDS
.endif

; Vibrato table (256 bytes)
ft_vibrato_table:
	.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte $00, $00, $00, $00, $01, $01, $01, $01, $02, $02, $02, $02, $02, $02, $02, $02
	.byte $00, $00, $00, $01, $01, $01, $02, $02, $02, $03, $03, $03, $03, $03, $03, $03
	.byte $00, $00, $00, $01, $01, $02, $02, $03, $03, $03, $04, $04, $04, $04, $04, $04
	.byte $00, $00, $01, $02, $02, $03, $03, $04, $04, $05, $05, $06, $06, $06, $06, $06
	.byte $00, $00, $01, $02, $03, $04, $05, $06, $07, $07, $08, $08, $09, $09, $09, $09
	.byte $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $09, $0A, $0B, $0B, $0B, $0B
	.byte $00, $01, $02, $04, $05, $06, $07, $08, $09, $0A, $0B, $0C, $0C, $0D, $0D, $0D
	.byte $00, $01, $03, $04, $06, $08, $09, $0A, $0C, $0D, $0E, $0E, $0F, $10, $10, $10
	.byte $00, $02, $04, $06, $08, $0A, $0C, $0D, $0F, $11, $12, $13, $14, $15, $15, $15
	.byte $00, $02, $05, $08, $0B, $0E, $10, $13, $15, $17, $18, $1A, $1B, $1C, $1D, $1D
	.byte $00, $04, $08, $0C, $10, $14, $18, $1B, $1F, $22, $24, $26, $28, $2A, $2B, $2B
	.byte $00, $06, $0C, $12, $18, $1E, $23, $28, $2D, $31, $35, $38, $3B, $3D, $3E, $3F
	.byte $00, $09, $12, $1B, $24, $2D, $35, $3C, $43, $4A, $4F, $54, $58, $5B, $5E, $5F
	.byte $00, $0C, $18, $25, $30, $3C, $47, $51, $5A, $62, $6A, $70, $76, $7A, $7D, $7F 

;
; An example of including music follows
;

; The label that contains a pointer to the music data
;  A simple way to handle multiple songs is to move this
;  to RAM and setup a table of pointers to music data
ft_music_addr:
	.word * + 2					; This is the point where music data is stored

.ifdef INC_MUSIC
	.incbin "music.bin"			; Music data
.ifdef USE_DPCM
	.segment "DPCM"				; DPCM samples goes here
	.incbin "samples.bin"
.endif
.endif

