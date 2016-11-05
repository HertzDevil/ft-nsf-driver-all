How to compile
--------------
To compile a NSF, call CA65 with these commands

ca65 nsf_wrap.s -D INC_MUSIC
ld65 -C nsf.cfg -o music.nsf nsf_wrap.o

INC_MUSIC tells the compiler to include song data files. Make sure music.bin 
and samples.bin, or music.asm from famitracker is in the same directory. 
To enable expansion chips use one of these switches:

USE_VRC6 - enable VRC6 code
USE_VRC7 - enable VRC7 code
USE_MMC5 - enable MMC5 code
USE_FDS - enable FDS code
USE_N106 - enable N106 code

Only one expansion chip can be enabled!

A few more options are located in the top of driver.s.

Using the player is simple, just call ft_music_init with the song number in A 
and NTSC/PAL setting in X to initialize the music player. 
Then call ft_music_play in every NMI interrupt.

Average CPU usage is somewhere between 1200-2000 cycles (4-6% of a video frame) 
depending on the complexity of the song. Peak usage is higher, usually between
10-15% when switching patterns. This might be improved in future versions.


How to combine multiple songs
-----------------------------
Store the different BIN-files in the assembly file, then just move ft_music_addr 
to RAM and write the start address of the song you want to use on that location. 
This is easily achieved by adding a new init song handler that calls the 
ordinary one.

