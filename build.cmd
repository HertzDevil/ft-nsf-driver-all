@echo off
ca65 driver.asm
ld65 -C nsf.cfg -o driver.bin driver.o -v
