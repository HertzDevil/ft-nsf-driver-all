;
; The NSF music driver for FamiTracker
; Version 2.0
; By jsr (zxy965r@tninet.se)
; assemble with ca65
;
; Completely rewritten from scratch since ver 1.x
; 
; Tab stop is 4
;
; No documentation more than comments are currently available
;

; Constants
TUNE_PATTERN_LENGTH			= $00
TUNE_FRAME_LIST_POINTER		= $01

; 2A03 channels
CHANNELS					= 5

; Header item offsets
HEAD_SPEED					= 11
HEAD_TEMPO					= 12

SPEED_DIV_NTSC				= 60 * 60;
SPEED_DIV_PAL				= 60 * 50;

EFF_ARPEGGIO				= 1
EFF_PORTAMENTO				= 2
EFF_PORTA_UP				= 3
EFF_PORTA_DOWN				= 4

.define VERSION "FT20"

.segment "ZEROPAGE"

; Variables that must be on zero-page
var_Temp:				.res 1		; Temporary 8-bit
var_Temp2:				.res 1
var_Temp16:				.res 2		; Temporary 16-bit 
var_Temp_Pointer:		.res 2		; Temporary
var_Temp_Pattern:		.res 2		; Pattern address (temporary)
var_Note_Table:			.res 2

ACC:					.res 2
AUX:					.res 2
EXT:					.res 2

last_zp_var:			.res 1


.segment "BSS"
; Driver variables

; Song header (necessary to be in order)
var_Song_list:			.res 2		; Song list address
var_instrument_list:	.res 2		; Instrument list address
var_dpcm_inst_list:		.res 2		; DPCM instruments
var_dpcm_pointers:		.res 2		; DPCM sample pointers

; Track header (necessary to be in order)
var_Frame_List:			.res 2		; Pattern list address
var_Frame_Count:		.res 1		; Number of frames
var_Pattern_Length:		.res 1		; Global pattern length
var_Speed:				.res 1		; Speed setting
var_Tempo:				.res 1		; Tempo setting

; General
var_Flags:				.res 1		; Flags, bit 0 = playing
var_Pattern_Pos:		.res 1		; Global pattern postion
var_Current_Frame:		.res 1		; Current frame

var_Tempo_Accum:		.res 2		; Variables for speed division (check if possible to optimize)
var_Tempo_Count:		.res 2
var_Tempo_Dec:			.res 2
var_VolTemp:			.res 1		; So the Exx command will work
var_Sweep:				.res 1		; This has to be saved

;var_Frame:				.res 1		; 
var_Bank:				.res 1
var_Jump:				.res 1		; Do a Jump 
var_Skip:				.res 1		; Do a Skip

var_sequence_ptr:		.res 1
var_sequence_result:	.res 1

; 2A03 channel variables
; General variables (all channels)
var_ch_Pattern_addr:	.res 10		; Holds current pattern address and position in it
var_ch_Bank:			.res 5		; Pattern bank
var_ch_Frequency:		.res 8		; Current channel note frequency
var_ch_FreqCalculated:	.res 8		; Frequency after fine pitch and vibrato has been applied
var_ch_Note:			.res 5		; Current channel note
var_ch_NoteDelay:		.res 5		; Delay in rows until next note
var_ch_DefaultDelay:	.res 5		; Default row delay, if exists
var_ch_VolumeOffset:	.res 5		; Volume column
var_ch_OutVolume:		.res 4		; Volume for the APU
var_ch_PrevFreqHigh:	.res 2		; Only used by square channels
var_ch_Delay:			.res 5		; Delay command

; Sequence variables (used by the first 4 channels)
var_ch_Volume:			.res 4		; Output volume
var_ch_DutyCycle:		.res 4		; Duty cycle / Noise mode
var_ch_SeqVolume:		.res 8		; Sequence 1: Volume
var_ch_SeqArpeggio:		.res 8		; Sequence 2: Arpeggio
var_ch_SeqPitch:		.res 8		; Sequence 3: Pitch bend
var_ch_SeqHiPitch:		.res 8		; Sequence 4: High speed pitch bend
var_ch_SeqDutyCycle:	.res 8		; Sequence 5: Duty cycle / Noise Mode
var_ch_SequencePtr1:	.res 4		; Index pointers for sequences
var_ch_SequencePtr2:	.res 4
var_ch_SequencePtr3:	.res 4
var_ch_SequencePtr4:	.res 4
var_ch_SequencePtr5:	.res 4

; This part above could be made smarter now that sequences are guaranteed to be lesser than 256 bytes (I think)

; Track variables (used by 4 channels)
var_ch_Effect:			.res 4		; Arpeggio & portamento
var_ch_EffParam:		.res 4		; Effect parameter (used by portamento and arpeggio)

var_ch_ArpeggioCycle:	.res 4		; Arpeggio cycle
var_ch_PortaTo:			.res 8		; Portamento frequency
var_ch_FinePitch:		.res 4		; Fine pitch setting
var_ch_VibratoPos:		.res 4		; Vibrato position
var_ch_VibratoParam:	.res 4		; Vibrato params
var_ch_VibratoSpeed:	.res 4
var_ch_TremoloPos:		.res 4		; Tremolo
var_ch_TremoloParam:	.res 4		;
var_ch_TremoloSpeed:	.res 4

; Square variables
var_ch_Sweep:			.res 2		; Hardware sweep, square only

; DPCM variables
var_ch_SamplePtr:		.res 1		; DPCM sample pointer
var_ch_SampleLen:		.res 1		; DPCM sample length
var_ch_SamplePitch:		.res 1		; DPCM sample pitch
var_ch_DPCMDAC:			.res 1		; DPCM delta counter setting
var_ch_DPCM_Offset:		.res 1

; Debugging!
var_ch_Debug:			.res 5

; VRC6 channel variables

; End of variable space
last_bss_var:			.res 1

	
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

; The rest of the code
; I haven't used CA65 before so I don't know how to make use of the linker
.include "init.s"
.include "player.s"
.include "effects.s"
.include "instrument.s"
.include "apu.s"

ft_notes_pal:							; Note frequencies for PAL
	.incbin "freq_pal.bin"
ft_notes_ntsc:							; Note frequencies for NTSC
	.incbin "freq_ntsc.bin"
ft_sine:								; Sine table used by vibrato and tremolo
	.byte $00, $00, $02, $05, $0A, $0F, $16, $1D
	.byte $26, $30, $3A, $45, $51, $5D, $69, $76
	.byte $83, $8F, $9C, $A8, $B4, $BF, $CA, $D4
	.byte $DD, $E6, $ED, $F3, $F8, $FC, $FE, $FF
	.byte $FF, $FE, $FC, $F8, $F3, $ED, $E6, $DD
	.byte $D4, $CA, $C0, $B4, $A8, $9C, $8F, $83
	.byte $76, $69, $5D, $51, $45, $3A, $30, $26
	.byte $1D, $16, $0F, $0A, $05, $02, $00, $00

; Anything after this address will be used as music data
.ifndef DRIVER_MODE
	.segment "MUSIC"
.endif

ft_music_addr:		; <- music address
	
	.word * + 2

.ifndef DRIVER_MODE
	.segment "MUSIC"
	.incbin "music.bin"		; Music data
	.segment "DPCM"			; DPCM samples goes here	
	.incbin "samples.bin"
.endif
