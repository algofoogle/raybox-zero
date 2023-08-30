@echo off

:: This is a funky little script needed for Windows make process only that tries to output
:: a "random enough" value in the range 0..32767

:: Get subsecond part of current time in variable %RTEMP%:
for /F "tokens=2 delims=." %%a in ('w32tm /query /status /verbose ^| find "Time since" ') do set RTEMP=%%a

:: Prefix with 1 (to avoid leading 0 errors), chop off trailing 's', add %RANDOM%, and constrain to 32767:
for /F "tokens=1 delims=s" %%a in ('echo %RTEMP%') do set /a RSEED=((1%%a+%RANDOM%)%%32768)

echo %RSEED%
