{ Demo concept of IRegistry interface

 HKey_Local_Machine  HKey_Current_User
 Registry.RootKey := HKEY_CURRENT_USER;

 Alternatives to
 OptionsMan := Client.OptionsManager; 
 Reader := OptionsMan.GetOptionsReader(cNameOfServer,'');
 Writer := OptionsMan.GetOptionsWriter(cNameOfServer);

BL Miller
04/09/2020  v0.10  Toogle user boolean in Registry inside AD section.
16/10/2020  v0.11  Demo toogle of Altium Portal auto login
16/10/2020  v0.12  try to add ReadSectionKeys()
16/10/2020  v0.13  refactor errors.. Might help to read/write to the full correct path..


// Software\Altium\Altium Designer {hhhhhhhh-hhhh-hhhh-hhhh-hhhhhhhhhhhh}
//                                     vv  SpecialKey_SoftwareAltiumApp  vv
// HKEY_CURRENT_USER/Software/Altium/Altium Designer {Fxxxxxxx-xxxxxxxxxxxxx}/DesignExplorer/Preferences
//                                                                           /Forms
}

const
    cRegistrySubPath = '\DesignExplorer\Preferences';

//    csSectKey1 = 'Text Editors\Text Preferences';
//    csItemKey1 = 'SelectFoundText';

    csSectKey1 = '\AltiumPortal\Account';
    csItemKey1 = 'SigninAtStartup';


var
    bSelectText    : boolean;
    OldTextValue   : WideString;
    bSuccess       : boolean;
    SectKeyList    : TStringlist;

function RegistryReadBool(const SKey : WideString, const IKey : Widestring) : boolean;
var
    Registry  : TRegistry;
Begin
    Result := false;
    Registry := TRegistry.Create;
    Try
        Registry.OpenKey(SKey, false);
        if Registry.ValueExists(IKey) then
            Result := Registry.ReadBool(IKey);

        Registry.GetDataType(IKey);           //TRegDataType
        Registry.CloseKey;

    Finally
        Registry.Free;
    End;
End;

function RegistryWriteBool(const SKey : Widestring, const IKey : WideString, const SVal : boolean) : boolean;
var
    Registry: TRegistry;
Begin
    Result := false;
    Registry := TRegistry.Create;
    Try
        Registry.OpenKey(SKey, true);
        if Registry.ValueExists(IKey) then
        begin
            Registry.WriteBool(IKey, SVal);
            Result := (SVal = Registry.ReadBool(IKey) );
        end;
        Registry.CloseKey;

    Finally
        Registry.Free;
    End;
End;

function RegistryReadString(const SKey : WideString, const IKey : Widestring) : WideString;
var
    Registry  : TRegistry;
Begin
    Result := '';
    Registry := TRegistry.Create;
    Try
        Registry.OpenKey(SKey, false);
        if Registry.ValueExists(IKey) then
            Result := Registry.ReadString(IKey);
        Registry.CloseKey;
    Finally
        Registry.Free;
    End;
End;

function RegistryWriteString(const SKey : Widestring, const IKey : WideString, const SVal : WideString) : boolean;
var
    Registry: TRegistry;
Begin
    Result := false;
    Registry := TRegistry.Create;
    Try
        Registry.OpenKey(SKey, true);
        if Registry.ValueExists(IKey) then
        begin
            Result := true; // Registry.ReadString(IKey);
            Registry.WriteString(IKey, SVal);
        end;
        Registry.CloseKey;
    Finally
        Registry.Free;
    End;
End;

function RegistryReadSectKeys(const SKey : WideString) : TStringList;
var
    Registry: TRegistry;
    Keys : WideString;
Begin
    Result := TStringList.Create;
//    Result.Delimiter := '|';

    Registry := TRegistry.Create;
    Registry.RootKey;
    Registry.RootKeyName;

    Try
        Registry.OpenKeyReadOnly( SKey );
        Registry.HasSubKeys;
        Registry.GetKeyNames( Result );           // DNW !!
        Registry.Closekey;

    Finally
        Registry.Free;
    End;
end;

procedure ToggleStringBoolean;
Var
    SectKey  : WideString;
    KeyValue : WideString;
begin
    SectKey :=  '\' + SpecialKey_SoftwareAltiumApp + cRegistrySubPath + csSectKey1;

    SectKeyList := RegistryReadSectKeys(SectKey);


    OldTextValue := RegistryReadString(SectKey, csItemKey1);
    if OldTextValue = '0' then bSelectText := false;
    if OldTextValue = '1' then bSelectText := true;

// toggle
    bSelectText := not bSelectText;
    KeyValue := '0';
    if bSelectText then KeyValue := '1';

    bSuccess := RegistryWriteString(SectKey, csItemKey1, KeyValue);
    KeyValue := RegistryReadString(SectKey, csItemKey1);
    bSuccess := bSuccess and ( KeyValue <> OldTextValue);

    ShowMessage(csItemKey1 + ' set to : ' + KeyValue + '   success  ' + BoolToStr(bSuccess, true));

end;

