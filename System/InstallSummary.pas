{ List all installed AltiumDesigner ..

 HKey_Local_Machine  HKey_Current_User
 Registry.RootKey := HKEY_CURRENT_USER;


BL Miller
26/10/2020  v0.10  POC list Altium Install registry entries..

TBD:
  check in Win64 environment.

//                                            vv  SpecialKey_SoftwareAltiumApp  vv
// HKEY_LOCAL_MACHINE/Software/Altium/Builds/Altium Designer {Fxxxxxxx-xxxxxxxxxxxxx}/*items
}

const
{ Reserved Key Handles. missing in DelphiScript}
    HKEY_CLASSES_ROOT     = $80000000;
    HKEY_CURRENT_USER     = $80000001;
    HKEY_LOCAL_MACHINE    = $80000002;
    HKEY_USERS            = $80000003;
    HKEY_PERFORMANCE_DATA = $80000004;
    HKEY_CURRENT_CONFIG   = $80000005;
    HKEY_DYN_DATA         = $80000006;

    cRegistrySubPath = '\Software\Altium\Builds';

// paralist of ItemKeys to report.
    csItemKeys = 'Application|Build|Display Name|ProgramsInstallPath|FullBuild|ReleaseDate|DocumentsInstallPath|Security|UniqueID|Version|Win64';

var
    Registry         : TRegistry;
    RegDataInfo      : TRegDataInfo;
    SectKeyList      : TStringlist;
    ItemKeyList      : TStringList;
    Report           : TStringList;
    Project          : IProject;
    FilePath         : WideString;
    ReportDocument   : IServerDocument;

function RegistryReadString(const SKey : WideString, const IKey : Widestring) : WideString; forward;
function RegistryReadSectKeys(const SKey : WideString) : TStringList;                       forward;

procedure ListTheInstalls;
Var
    SectKey    : WideString;
    ItemKey    : WideSting;
    KeyValue   : WideString;
    S, I       : integer;

begin
    Report := TStringList.Create;

    Registry := TRegistry.Create;   // TRegistry.Create(KEY_WRITE OR KEY_WOW64_64KEY);  KEY_SET_VALUE

    ItemKeyList := TStringList.Create;
    ItemKeyList.Delimiter := '|';
    ItemKeyList.StrictDelimiter := true;
    ItemKeyList.DelimitedText := csItemKeys;

    Registry.RootKey := HKEY_LOCAL_MACHINE;
//    Registry.CurrentPath := HKEY_Root;           // read only

//  do NOT include the RootKey Path
    SectKey := cRegistrySubPath;
    SectKeyList := RegistryReadSectKeys(SectKey);

    for S := 0 to (SectKeyList.Count - 1) do
    begin
        SectKey := SectkeyList.Strings(S);
        Report.Add('Section : ' + SectKey);
        for I := 0 to (ItemKeyList.Count - 1) do
        begin
            ItemKey := ItemKeyList.Strings(I);
            RegDataInfo := rdString;
//   don't forget the damn separator '\'
            KeyValue := RegistryReadString(cRegistrySubPath + '\' + SectKey, ItemKey);
            Report.Add(PadRight(ItemKey,20) + ' = ' + PadRight(KeyValue,50) + ' datatype : ' +IntToStr(RegDataInfo) );
        end;
        Report.Add('');
    end;

    ItemKeyList.Free;
    SectKeyList.Delimiter := #13;
    SectKeyList.Insert(0,'List of installs : ');
//    ShowMessage(SectKeyList.DelimitedText);

    if Registry <> nil then Registry.Free;
    SectKeyList.Free;

    Project := GetWorkSpace.DM_FocusedProject;
    FilePath := ExtractFilePath(Project.DM_ProjectFullPath);
    if FilePath = 'FreeDocuments' then
        FilePath := GetCurrentDir;

    FilePath := FilePath + '\AD_Installs_Report.Txt';
    Report.Insert(0, 'Report Altium Installs in Registry');
    Report.SaveToFile(FilePath);
    Report.Free;

    //Prj.DM_AddSourceDocument(FilePath);
    ReportDocument := Client.OpenDocument('Text', FilePath);

    If ReportDocument <> Nil Then
    begin
        Client.ShowDocument(ReportDocument);
        if (ReportDocument.GetIsShown <> 0 ) then
            ReportDocument.DoFileLoad;
    end;
end;

function RegistryReadSectKeys(const SKey : WideString) : TStringList;
Begin
    Result   := TStringList.Create;
    Registry.OpenKeyReadOnly( SKey );
    Registry.GetKeyNames( Result );
//    Registry.GetValueNames( Result ) ;
//    libRegistryCKey  := Registry.CurrentKey;
//    libRegistrySPath := Registry.CurrentPath;
    Registry.HasSubKeys;
    Registry.Closekey;
end;

function RegistryReadString(const SKey : WideString, const IKey : Widestring) : WideString;
Begin
    Result := '';
    Registry.OpenKey(SKey, false);
    if Registry.ValueExists(IKey) then
    begin
        RegDataInfo := Registry.GetDataType(IKey);
        Result := Registry.ReadString(IKey);
    end;
    Registry.CloseKey;
End;

