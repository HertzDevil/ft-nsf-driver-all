;
; The NSF music driver for FamiTracker
; Version 2.2
; By jsr (zxy965r@tninet.se)
; assemble with ca65
;
; Documentation is in readme.txt
; 
; Tab stop is 4
;

;
; ToDo; 
;  - Add VRC7
;  - Optimize vibrato and tremolo
;

;
; Assembler code switches
;

USE_BANKSWITCH = 1		; Enable bankswitching code
USE_DPCM = 1			; Enable DPCM channel (currently broken, leave enabled)

NTSC_PERIOD_TABLE = 1	; Enable this to include the NTSC period table
PAL_PERIOD_TABLE = 1	; Enable this to include the PAL period table

ENABLE_SKIP_ROWS = 1	; Enable this to add code for seeking to a row > 0 when using skip command

;USE_VRC6 = 1 			; Enable this to include VRC6 code
;USE_MMC5 = 1			; Enable this to include MMC5 code

;
; Constants
;
TUNE_PATTERN_LENGTH		= $00
TUNE_FRAME_LIST_POINTER	= $01

.if .defined(USE_VRC6)		; 2A03 + VRC6 channels
	CHANNELS		= 8
	DPCM_CHANNEL	= 7
	SAW_CHANNEL		= 6
.elseif .defined(USE_MMC5)	; 2A03 + MMC5 channels
	CHANNELS		= 7
	DPCM_CHANNEL	= 6
.else						; 2A03 channels
;	.ifdef USE_DPCM
		CHANNELS		= 5
		DPCM_CHANNEL	= 4
;	.else
;		CHANNELS		= 4
;	.endif
.endif

NOISE_CHANNEL			= 3
WAVE_CHANS				= CHANNELS - 1		; Number of wave channels

; Header item offsets
HEAD_SPEED				= 11
HEAD_TEMPO				= 12

SPEED_DIV_NTSC			= 60 * 60;
SPEED_DIV_PAL			= 60 * 50;

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
var_Temp:			.res 1					; Temporary 8-bit
var_Temp2:			.res 1
var_Temp16:			.res 2					; Temporary 16-bit 
var_Temp_Pointer:	.res 2					; Temporary
var_Temp_Pattern:	.res 2					; Pattern address (temporary)
var_Note_Table:		.res 2
	
ACC:				.res 2					; Used by division routine
AUX:				.res 2
EXT:				.res 2

last_zp_var:		.res 1					; Not used


.segment "BSS"

;
; Driver variables
;

; Song header (necessary to be in order)
var_Song_list:			.res 2					; Song list address
var_Instrument_list:	.res 2					; Instrument list address
.ifdef USE_DPCM
var_dpcm_inst_list:		.res 2					; DPCM instruments
var_dpcm_pointers:		.res 2					; DPCM sample pointers
.endif
var_SongFlags:			.res 1					; Song flags, bit 0 = bankswitched, bit 1 - 7 = unused
var_Channels:			.res 1					; Channel enable/disable

; Track header (necessary to be in order)
var_Frame_List:			.res 2					; Pattern list address
var_Frame_Count:		.res 1					; Number of frames
var_Pattern_Length:		.res 1					; Global pattern length
var_Speed:				.res 1					; Speed setting
var_Tempo:				.res 1					; Tempo setting
var_InitialBank:		.res 1

; General
var_PlayerFlags:		.res 1					; Player flags, bit 0 = playing, bit 1 - 7 unused
var_Pattern_Pos:		.res 1					; Global pattern row
var_Current_Frame:		.res 1					; Current frame
var_Load_Frame:			.res 1					; 1 if new frame should be loaded

var_Tempo_Accum:		.res 2					; Variables for speed division
var_Tempo_Count:		.res 2					;  (if tempo support is not needed then this can be optimized)
var_Tempo_Dec:			.res 2
var_VolTemp:			.res 1					; So the Exx command will work
var_Sweep:				.res 1					; This has to be saved

.ifdef USE_BANKSWITCH
var_Bank:				.res 1
.endif
var_Jump:				.res 1					; If a Jump should be executed
var_Skip:				.res 1					; If a Skip should be executed

var_sequence_ptr:		.res 1
var_sequence_result:	.res 1

;var_enabled_channels:	.res 1

; Channel variables

; General channel variables, used by the pattern reader (all channels)
var_ch_Pattern_addr:	.res CHANNELS * 2		; Holds current pattern address and position in it
.ifdef USE_BANKSWITCH
var_ch_Bank:			.res CHANNELS			; Pattern bank
.endif
var_ch_Note:			.res CHANNELS			; Current channel note
var_ch_NoteDelay:		.res CHANNELS			; Delay in rows until next note
var_ch_VolColumn:		.res CHANNELS			; Volume column
var_ch_DefaultDelay:	.res CHANNELS			; Default row delay, if exists
var_ch_Delay:			.res CHANNELS			; Delay command

; Following is specific to chip channels (2A03, VRC...)

var_ch_TimerPeriod:		.res CHANNELS * 2		; Current channel note period
var_ch_TimerCalculated:	.res CHANNELS * 2		; Frequency after fine pitch and vibrato has been applied
var_ch_OutVolume:		.res CHANNELS			; Volume for the APU
var_ch_VolSlide:		.res CHANNELS			; Volume slide

; --- Testing --- 
var_ch_LoopCounter:		.res CHANNELS
; --- Testing --- 

; Square 1 & 2 variables
var_ch_Sweep:			.res 2					; Hardware sweep
var_ch_PrevFreqHigh:	.res 2					; Used only by 2A03 pulse channels

.ifdef USE_MMC5
var_ch_PrevFreqHighMMC5:	.res 2				; MMC5
.endif

; Sequence variables
var_ch_SeqVolume:		.res WAVE_CHANS * 2		; Sequence 1: Volume
var_ch_SeqArpeggio:		.res WAVE_CHANS * 2		; Sequence 2: Arpeggio
var_ch_SeqPitch:		.res WAVE_CHANS * 2		; Sequence 3: Pitch bend
var_ch_SeqHiPitch:		.res WAVE_CHANS * 2		; Sequence 4: High speed pitch bend
var_ch_SeqDutyCycle:	.res WAVE_CHANS * 2		; Sequence 5: Duty cycle / Noise Mode
var_ch_Volume:			.res WAVE_CHANS			; Output volume
var_ch_DutyCycle:		.res WAVE_CHANS			; Duty cycle / Noise mode
var_ch_SequencePtr1:	.res WAVE_CHANS			; Index pointers for sequences
var_ch_SequencePtr2:	.res WAVE_CHANS
var_ch_SequencePtr3:	.res WAVE_CHANS
var_ch_SequencePtr4:	.res WAVE_CHANS
var_ch_SequencePtr5:	.res WAVE_CHANS

; Track variables (used by 4 channels)
var_ch_Effect:			.res WAVE_CHANS			; Arpeggio & portamento
var_ch_EffParam:		.res WAVE_CHANS			; Effect parameter (used by portamento and arpeggio)

var_ch_PortaTo:			.res WAVE_CHANS * 2		; Portamento frequency
var_ch_ArpeggioCycle:	.res WAVE_CHANS			; Arpeggio cycle
var_ch_FinePitch:		.res WAVE_CHANS			; Fine pitch setting
var_ch_VibratoPos:		.res WAVE_CHANS			; Vibrato
var_ch_VibratoParam:	.res WAVE_CHANS		
var_ch_VibratoSpeed:	.res WAVE_CHANS
var_ch_TremoloPos:		.res WAVE_CHANS			; Tremolo
var_ch_TremoloParam:	.res WAVE_CHANS
var_ch_TremoloSpeed:	.res WAVE_CHANS

; DPCM variables
.ifdef USE_DPCM
var_ch_SamplePtr:		.res 1					; DPCM sample pointer
var_ch_SampleLen:		.res 1					; DPCM sample length
var_ch_SamplePitch:		.res 1					; DPCM sample pitch
var_ch_DPCMDAC:			.res 1					; DPCM delta counter setting
var_ch_DPCM_Offset:		.res 1
.endif

; End of variable space
last_bss_var:			.res 1					; Not used
	

.ifdef MODE2
	.segment "CODE2"
.else
	.segment "CODE"
.endif

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
; (haven't figured out the linker yet)
.include "init.s"
.include "player.s"
.include "effects.s"
.include "instrument.s"
.include "apu.s"

.ifdef USE_VRC6
.include "vrc6.s"
.endif
.ifdef USE_MMC5
.include "mmc5.s"
.endif

.ifdef PAL_PERIOD_TABLE
ft_notes_pal:							; Note frequencies for PAL (remove this if you don't need PAL support)
	.incbin "freq_pal.bin"
.endif
.ifdef NTSC_PERIOD_TABLE
ft_notes_ntsc:							; Note frequencies for NTSC (remove this if you don't need NTSC support)
	.incbin "freq_ntsc.bin"
.endif
ft_sine:								; Sine table used by vibrato and tremolo
	.byte $00, $00, $02, $05, $0A, $0F, $16, $1D
	.byte $26, $30, $3A, $45, $51, $5D, $69, $76
	.byte $83, $8F, $9C, $A8, $B4, $BF, $CA, $D4
	.byte $DD, $E6, $ED, $F3, $F8, $FC, $FE, $FF
	.byte $FF, $FE, $FC, $F8, $F3, $ED, $E6, $DD
	.byte $D4, $CA, $C0, $B4, $A8, $9C, $8F, $83
	.byte $76, $69, $5D, $51, $45, $3A, $30, $26
	.byte $1D, $16, $0F, $0A, $05, $02, $00, $00

.ifdef USE_VRC6
ft_periods_sawtooth:
	.incbin "freq_sawtooth.bin"			; Note frequencies for VRC6 sawtooth
.endif	

;
; Example of including music follows
;

; The label that contains a pointer to the music data
ft_music_addr:
	.word * + 2					; This is the point where music data is stored, can be changed

.ifdef INC_MUSIC
	.incbin "music.bin"			; Music data
	.ifdef USE_DPCM 
		.segment "DPCM"				; DPCM samples goes here	
		.incbin "samples.bin"
	.endif
.endif

