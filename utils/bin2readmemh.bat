@echo off
rem Convert a raw binary file to a .hex file compatible with Verilog $readmemh()
rem NOTE: Might require GNU tools to be installed for hexdump
hexdump -v -e '16/1 "%%02X ""\n"' %1 > %2
