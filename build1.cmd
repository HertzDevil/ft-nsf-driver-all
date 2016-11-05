@echo off
echo Creating code...
ca65 driver.s -D DRIVER_MODE -D MODE1 --listing
ld65 -C clean.cfg -o driver.bin driver.o -v -m map.txt
