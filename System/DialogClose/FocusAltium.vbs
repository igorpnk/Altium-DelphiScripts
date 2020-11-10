Dim ObjShell
Dim testArg

Set objArgs = Wscript.Arguments

testArg = 1000

if objArgs.Count > 0 then
    testArg = objArgs(0)
end if

' Wscript.Echo now &": "& testArg

Set ObjShell = CreateObject("Wscript.Shell")
ObjShell.AppActivate("Altium")

Wscript.Sleep testArg
ObjShell.SendKeys "{ENTER}"
