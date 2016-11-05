To compile a NSF, call CA65 with these commands

ca65 nsf_wrap.s -D INC_MUSIC
ld65 -C nsf.cfg -o music.nsf nsf_wrap.o

INC_MUSIC is used to include the song data files. To create VRC6 files, define 
USE_VRC6, and define USE_MMC5 for MMC5 files. Make sure music.bin and 
samples.bin from famitracker is in the same directory.

Using the player is simple, just call ft_music_init with the song number in A 
and NTSC/PAL setting in X. Then call ft_music_play in every NMI interrupt.

Average CPU usage is somewhere between 1200-2000 cycles (4-6% of a video frame) 
depending on the complexity of the song. Peak usage is higher, usually between
10-15% when switching patterns. This will be improved in future versions.

----------------------------------------------------

Two functions are provided to disable and enable sound channels in order to
allow sound effects. The channels are still playing in the background, just
doesn't update the APU.

These are:
 ft_disable_channel: - Disable channel, X = channel number (0 : Sq1, 1 : Sq2, 2: Tri...)
 ft_enable_channel:  - Enable channel, X = channel number

(Both functions uses the A register.)