{ common routine
}
procedure libM_AddMessage(MClass  : WideString; MText : WideString; MSource : WideString; MDoc : WideString;
                          const MCBProcess : WideString; const MCBPara : WideString;
                          IIndex : Integer);
var
    MM    : IDXPMessagesManager;
    F     : Boolean;
begin
    MM := GetWorkSpace.DM_MessagesManager;
    If MM = Nil Then Exit;
    MM.BeginUpdate;
    F := False;
    // ImageIndex := 164;
    MM.AddMessage({MessageClass             } MClass,
                  {MessageText              } MText,
                  {MessageSource            } MSource,
                  {MessageDocument          } MDoc,
                  {MessageCallBackProcess   } MCBProcess,
                  {MessageCallBackParameters} MCBPara,
                  {ImageIndex               } IIndex,
                  {ReplaceLastofSameClass   } F );
    MM.EndUpdate;
end;

procedure libM_AddMessage2(MClass : WideString; MText : WideString; MSource : WideString; MDoc :WideString;
                           const MCBProcess  : WideString; const MCBPara  : WideString, IIndex  : integer;
                           const MCBProcess2 : WideString; const MCBPara2 : WideString, Details : IDXPMessageItemDetails);
var
    MM : IDXPMessagesManager;
    F  : Boolean;
begin
    MM := GetWorkSpace.DM_MessagesManager;
    If MM = Nil Then Exit;
    MM.BeginUpdate;
    F := False;
    // ImageIndex := 164;
    MM.AddMessage2({MessageClass              } MClass,
                   {MessageText               } MText,
                   {MessageSource             } MSource,
                   {MessageDocument           } MDoc,
                   {MessageCallBackProcess    } MCBProcess,
                   {MessageCallBackParameters } MCBPara,
                   {ImageIndex                } IIndex,
                   {ReplaceLastofSameClass    } F,
                   {MessageCallBackProcess2   } MCBProcess2,
                   {MessageCallBackParameters2} MCBPara2,
                   {MessageItemDetails        } Details );
    MM.EndUpdate;
end;

procedure libM_AddError(MClass : WideString; MText : WideString);
var
    MM         : IDXPMessagesManager;
    ImageIndex : Integer;
    F          : Boolean;
begin
    MM := GetWorkSpace.DM_MessagesManager;
    If MM = Nil Then Exit;
    MM.BeginUpdate;
    F := False;
    ImageIndex := 165;

    MM.AddMessage({MessageClass             } MClass,
                      {MessageText              } MText,
                      {MessageSource            } '',
                      {MessageDocument          } '',
                      {MessageCallBackProcess   } '',
                      {MessageCallBackParameters} '',
                      ImageIndex,
                      F);
    MM.EndUpdate;
end;


procedure libM_AddMWarning(MClass : WideString; MText : WideString);
var
    MM          : IDXPMessagesManager;
    ImageIndex  : Integer;
    F           : Boolean;
begin
    MM := GetWorkSpace.DM_MessagesManager;
    If MM = Nil Then Exit;
    MM.BeginUpdate;
    F := False;
    ImageIndex := 163;

    MM.AddMessage({MessageClass             } MClass,
                      {MessageText              } MText,
                      {MessageSource            } '',
                      {MessageDocument          } '',
                      {MessageCallBackProcess   } '',
                      {MessageCallBackParameters} '',
                      ImageIndex,
                      F);
    MM.EndUpdate;
end;

{

Tick                      =  3;
Cross                     =  4;

Folder_NoError            = 6;
Folder_Warning            = 7;
Folder_Error              = 8;
Folder_Fatal              = 9;

Marker_NoError            = 107;
Marker_Warning            = 108;
Marker_Error              = 109;
Marker_Fatal              = 110;

ProjectGroup              = 54;
ProjectGroup2             = 55;
PcbLayer                  = 51;
EmptySection              =  9;
CamJob                    = 67;

BoardProject              = 56;
FpgaProject               = 57;
EmbeddedProject           = 58;
IntegratedLibrary         = 59;
FreeDocumentsProject      = 6;
}
