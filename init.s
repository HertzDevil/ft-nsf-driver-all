;
; ft_sound_init
;
; Initializes the player and song number
; a = song number
; x = ntsc/pal
;
ft_music_init:
	asl a
	jsr ft_load_song
	; Kill APU registers
	lda #$00
	ldx #$0B
@LoadRegs:
	sta $4000, x
	dex
	bne @LoadRegs
	ldx #$06
@LoadRegs2:
	sta $400D, x
	dex
	bne @LoadRegs2
	lda #$30		; noise is special
	sta $400C	
	lda #$0F
	sta $4015		; APU control
	lda #$08
	sta $4001
	sta $4005
	lda #$C0
	sta $4017
	lda #$40
	sta $4017		; Disable frame IRQs	

	lda #$FF		; Enable all channels
	sta var_Channels

	sta var_ch_DPCM_EffPitch

	; Reset some variables for the wave channels
	lda #$00
	tax
:	sta var_ch_NoteCut, x
	sta var_ch_Effect, x
	sta var_ch_EffParam, x
	sta var_ch_PortaToLo, x
	sta var_ch_PortaToHi, x
	sta var_ch_TimerPeriodLo, x
	sta var_ch_TimerPeriodHi, x
	inx
	cpx #WAVE_CHANS
	bne :-

	; DPCM
	sta var_ch_NoteCut + (CHANNELS - 1)

.ifdef USE_MMC5
	lda #$03
	sta $5015		; Enable channels
.endif
		
	rts

;
; Prepare the player for a song
;
; NSF music data header:
;
; - Song list, 2 bytes
; - Instrument list, 2 bytes
; - DPCM instrument list, 2 bytes
; - DPCM sample list, 2 bytes
; - Flags, 1 byte
; - Pointer to wave tables, 2 bytes, if FDS is enabled
; - NTSC speed divider
; - PAL speed divider
;
ft_load_song:
	pha
	; Get the header
	lda ft_music_addr
	sta var_Temp_Pointer
	lda ft_music_addr + 1
	sta var_Temp_Pointer + 1
	
	; Read the header and store in RAM
	ldy #$00
@LoadAddresses:
	clc
	lda (var_Temp_Pointer), y
	adc ft_music_addr
	sta var_Song_list, y
	iny
	lda (var_Temp_Pointer), y			; Song list offset, high addr
	adc ft_music_addr + 1
	sta var_Song_list, y
	iny
	cpy #$08							; 4 items
	bne @LoadAddresses

	lda (var_Temp_Pointer), y			; Flags, 1 byte
	sta var_SongFlags
	iny

.ifdef USE_FDS
	; Load FDS wave table pointer
	lda (var_Temp_Pointer), y
	adc ft_music_addr
	sta var_Wavetables
	iny
	lda (var_Temp_Pointer), y
	adc ft_music_addr + 1
	sta var_Wavetables + 1
	iny
.endif

	cpx #$01							; PAL / NTSC flag
	beq @LoadPAL
.ifdef NTSC_PERIOD_TABLE
	; Load NTSC speed divider and frequency table
	lda (var_Temp_Pointer), y
	iny
	sta var_Tempo_Dec
	lda (var_Temp_Pointer), y
	iny
	sta var_Tempo_Dec + 1
	lda #<ft_notes_ntsc
	sta var_Note_Table
	lda #>ft_notes_ntsc
	sta var_Note_Table + 1
.endif
	jmp @LoadDone
@LoadPAL:
.ifdef PAL_PERIOD_TABLE
	; Load PAL speed divider and frequency table
	iny
	iny
	lda (var_Temp_Pointer), y
	iny
	sta var_Tempo_Dec
	lda (var_Temp_Pointer), y
	iny
	sta var_Tempo_Dec + 1
	lda #<ft_notes_pal
	sta var_Note_Table
	lda #>ft_notes_pal
	sta var_Note_Table + 1
.endif
 @LoadDone:
	pla
	tay
	; Load the song
	jsr ft_load_track
	
	; Clear variables to zero
	; Important!
	ldx #$01
	stx var_PlayerFlags				; Player flags, bit 0 = playing
	dex
@ClearChannels2:					; This clears the first four channels
	lda #$7F
	sta var_ch_VolColumn, x
	lda #$80
	sta var_ch_FinePitch, x
	lda #$00
	;
	;lda #$00
	sta var_ch_VibratoSpeed, x
	sta var_ch_TremoloSpeed, x
	sta var_ch_Effect, x
	sta var_ch_VolSlide, x
	sta var_ch_NoteDelay, x
	sta var_ch_ArpeggioCycle, x
	;
	sta var_ch_Note, x
	inx
	cpx #(CHANNELS - 1)
	bne @ClearChannels2

	ldx #$FF
	stx var_ch_PrevFreqHigh			; Set prev freq to FF for Sq1 & 2
	stx var_ch_PrevFreqHigh + 1

.ifdef USE_DPCM
    lda #$00
    sta var_ch_DPCM_Offset
.endif
.ifdef USE_MMC5
	stx var_ch_PrevFreqHighMMC5
	stx var_ch_PrevFreqHighMMC5 + 1
.endif
.ifdef USE_VRC7
	stx var_ch_vrc7_CustomPatch
.endif

	inx								; Jump to the first frame
	stx var_Current_Frame
	jsr ft_load_frame
	
	jsr ft_calculate_speed
	;jsr ft_restore_speed
	
	lda #$00
	sta var_Tempo_Accum
	sta var_Tempo_Accum + 1
	
	rts

;
; Load the track number in A
;
; Track headers:
;
;	- Frame list address, 2 bytes
;	- Number of frames, 1 byte
;	- Pattern length, 1 byte
;	- Speed, 1 byte
;	- Tempo, 1 byte
;
ft_load_track:
	; Load track header address	
	lda var_Song_list
	sta var_Temp16
	lda var_Song_list + 1
	sta var_Temp16 + 1
	
	; Get the real address, song number * 2 will be in Y here
	clc
	lda (var_Temp16), y
	adc ft_music_addr
	sta var_Temp_Pointer
	iny
	lda (var_Temp16), y
	adc ft_music_addr + 1
	sta var_Temp_Pointer + 1
	
	; Read header
	lda #$00
	tax
	tay
	clc
	lda (var_Temp_Pointer), y			; Frame offset, low addr
	adc ft_music_addr
	sta var_Frame_List
	iny
	lda (var_Temp_Pointer), y			; Frame offset, high addr
	adc ft_music_addr + 1
	sta var_Frame_List + 1
	iny
@ReadLoop:
	lda (var_Temp_Pointer), y			; Frame count
	sta var_Frame_Count, x
	iny
	inx
	cpx #$06
	bne @ReadLoop

	rts

;
; Load the frame in A for all channels
;
ft_load_frame:
.ifdef USE_BANKSWITCH
	pha
	lda var_InitialBank
	beq :+
	sta $5FFB
:	pla
.endif

	; Get the entry in the frame list
	asl A					; Multiply by two
	clc						; And add the frame list addr to get 
	adc var_Frame_List		; the pattern list addr
	sta var_Temp16
	lda #$00
	tay
	tax
	adc var_Frame_List + 1
	sta var_Temp16 + 1
	; Get the entry in the pattern list
	lda (var_Temp16), y
	adc ft_music_addr
	sta var_Temp_Pointer
	iny
	lda (var_Temp16), y
	adc ft_music_addr + 1
	sta var_Temp_Pointer + 1
	; Iterate through the channels, x = channel
	ldy #$00							; Y = address
	stx var_Pattern_Pos	
@LoadPatternAddr:
	clc
	lda (var_Temp_Pointer), y			; Load the pattern address for the channel
	adc ft_music_addr
	sta var_ch_PatternAddrLo, x
	iny
	lda (var_Temp_Pointer), y			; Pattern address, high byte
	adc ft_music_addr + 1
	sta var_ch_PatternAddrHi, x
	iny
	lda #$00
	sta var_ch_NoteDelay, x
	sta var_ch_Delay, x
;	sta var_ch_LoopCounter, x
	lda #$FF
	sta var_ch_DefaultDelay, x
	inx
	cpx #CHANNELS
	bne @LoadPatternAddr
; Bankswitch values
.ifdef USE_BANKSWITCH
	lda var_SongFlags					; Check bankswitch flag
	and #$01
	beq @SkipBankValues					; Skip if no bankswitch info is stored
	ldx #$00
@LoadBankValues:
	lda (var_Temp_Pointer), y			; Pattern bank number 
	sta var_ch_Bank, x
	iny
	inx
	cpx #CHANNELS
	bne @LoadBankValues
@SkipBankValues:
.endif

.ifdef ENABLE_ROW_SKIP
	
	lda var_SkipTo
	beq @FirstRow
	jmp ft_SkipToRow
@FirstRow:
	rts
	
; Skip to a certain row, this is NOT recommended in songs when CPU time is critical!!
;
ft_SkipToRow:
	pha									; Save row count
	ldx #$00							; x = channel
@ChannelLoop:

	pla	
	sta var_Temp2						; Restore row count
	pha

	lda #$00
	sta var_ch_NoteDelay, x
	
@RowLoop:
	ldy #$00
	lda var_ch_PatternAddrLo, x
	sta var_Temp_Pointer
	lda var_ch_PatternAddrHi, x
	sta var_Temp_Pointer + 1

@ReadNote:
	lda var_ch_NoteDelay, x				; First check if in the middle of a row delay
	beq @NoRowDelay
	dec var_ch_NoteDelay, x				; Decrease one
	jmp @RowIsDone

@NoRowDelay:
	; Read a row
	lda (var_Temp_Pointer), y
	bmi @Effect
	
	lda var_ch_DefaultDelay, x
	cmp #$FF
	bne @LoadDefaultDelay
	iny
	lda (var_Temp_Pointer), y
	iny	
	
	sta var_ch_NoteDelay, x
	jmp @RowIsDone
@LoadDefaultDelay:
	iny
	sta var_ch_NoteDelay, x				; Store default delay
@RowIsDone:
	; Save the new address
	clc
	tya
	adc var_Temp_Pointer
	sta var_ch_PatternAddrLo, x
	lda #$00
	adc var_Temp_Pointer + 1
	sta var_ch_PatternAddrHi, x
	
	dec var_Temp2						; Next row
	bne @RowLoop
	
	inx									; Next channel
	cpx #CHANNELS
	bne @ChannelLoop
	
	pla									; fix the stack	
	clc
	adc var_Pattern_Pos
	sta var_Pattern_Pos
	rts
	
@Effect:
	cmp #$9E
	beq @EffectDuration
	cmp #$A0
	beq @EffectNoDuration
	pha
	cmp #$8E							; remove pitch slide
	beq @OneByteCommand
	and #$F0
	cmp #$F0							; See if volume
	beq @OneByteCommand
	cmp #$E0							; See if a quick instrument command
	beq @OneByteCommand
	iny									; Command takes two bytes
@OneByteCommand:						; Command takes one byte
	iny
	pla
	jmp @ReadNote						; A new command or note is immediately following
@EffectDuration:
	iny
	lda (var_Temp_Pointer), y
	iny
	sta var_ch_DefaultDelay, x
	jmp @ReadNote
@EffectNoDuration:
	iny
	lda #$FF
	sta var_ch_DefaultDelay, x
	jmp @ReadNote

.else
	rts	
.endif