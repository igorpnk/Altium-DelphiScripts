Rem ' StartAndReturn.bat
Rem ' full path may not be required (same folder)

rem ' //start /b wscript P:\Altium\Scripts\System\DialogClose\FocusAltium.vbs %1
start /b wscript "C:\Altium Projects\Scripts\System\DialogClose\FocusAltium.vbs" %1

rem echo %1 > c:\temp\cmdpara.txt
