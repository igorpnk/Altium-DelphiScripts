{ DialogClose.pas

B. Miller
03/11/2020  v0.10  POC collect scripts together.
10/11/2020  v0.11  Get parameter passing to vbs script.
}


const
    CmdBatchFileFullPath = '"C:\Altium Projects\Scripts\System\DialogClose\StartAndReturn.bat"';
//    CmdBatchFileFullPath = 'P:\Altium\Scripts\System\DialogClose\StartAndReturn.bat';
    Parameters           = '5000';

procedure UnitTest;
var
    ErrorCode : integer;

begin
    ErrorCode := RunApplication('cmd /c ' + CmdBatchFileFullPath + ' ' + Parameters);           // think this waits for return value

//    ErrorcCode := RunApplicationAndWait('name', time);                     // make time = small timeout

    ShowMessage('This message will self-destruct in ' + Parameters + 'ms');
end;
