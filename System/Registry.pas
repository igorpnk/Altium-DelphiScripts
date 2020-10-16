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


// Software\Altium\Altium Designer {hhhhhhhh-hhhh-hhhh-hhhh-hhhhhhhhhhhh}
//                                     vv  SpecialKey_SoftwareAltiumApp  vv
// HKEY_CURRENT_USER/Software/Altium/Altium Designer {Fxxxxxxx-xxxxxxxxxxxxx}/DesignExplorer/Preferences
//                                                                           /Forms
}

const
    cRegistrySubPath = '\DesignExplorer\Preferences\';

//    csSectKey1 = 'Text Editors\Text Preferences';
//    csItemKey1 = 'SelectFoundText';

    csSectKey1 = 'AltiumPortal\Account';
    csItemKey1 = 'SigninAtStartup';


var
    bSelectText    : boolean;
    bOldTextValue  : boolean;
    bSuccess       : boolean;

function RegistryReadBool(const SKey : WideString, const IKey : Widestring) : boolean;
var
    Registry  : TRegistry;
Begin
    Result := false;
    Registry := TRegistry.Create;
    Try
        Registry.OpenKey(SKey, true);

        if Registry.ValueExists(IKey) then
            Result := Registry.ReadBool(IKey);
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
            Result := Registry.ReadBool(IKey);
        Registry.WriteBool(IKey, SVal);
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
        Registry.OpenKey(SKey, true);

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
            Result := true; // Registry.ReadString(IKey);
        Registry.WriteString(IKey, SVal);
        Registry.CloseKey;
      
    Finally
        Registry.Free;
    End;
End;

procedure ToggleBoolean;
begin
    SpecialKey_SoftwareAltiumApp;
    SpecialKey_SoftwareAltiumAppDXP;

    bSelectText := RegistryReadBool(csSectKey1, csItemKey1);
// do stuff.

    bSelectText := not bSelectText;
    bOldTextValue := RegistryReadBool(csSectKey1, csItemKey1);
    bSuccess := RegistryWriteBool(csSectKey1, csItemKey1, bSelectText);
    bSelectText := RegistryReadBool(csSectKey1, csItemKey1);

    ShowMessage(csItemKey1 + ' set to : ' + BoolToStr(bSelectText, true) + '  success  ' + BoolToStr(bSuccess, true));

end;

