To compile a NSF, call CA65 with these commands

ca65 nsf_wrap.s -D INC_MUSIC
ld65 -C nsf.cfg -o music.nsf nsf_wrap.o

INC_MUSIC is used to include the song data files. To create VRC6 files, define USE_VRC6. Make sure music.bin and samples.bin from famitracker is in the same directory.

Using the player is simple, just call ft_music_init with the song number in A and NTSC/PAL setting in X. Then call ft_music_play in every NMI interrupt.

Average CPU usage is somewhere between 1200-2000 cycles (4-6% of a video frame) depending on the complexity of the song. Peak usage is higher, usually between 10-15% when switching patterns. This will be improved in future versions.