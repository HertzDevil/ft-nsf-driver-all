@echo off
echo Creating a NSF file...
cl65 -C nsf.cfg -o drv.nsf -v -t none nsf_wrap.s
echo Done
