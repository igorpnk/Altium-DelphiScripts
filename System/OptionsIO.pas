{ OptionIO.pas

 Experimental script to explore various Server preferences etc.

 Export a set of preference's sections (defined export list) to ini-file
 Import from an ini-file (defined import list) to the server preferences.

 can use IOptionsreader/Writer or IRegistry interfaces to R/W the registry.
 Both work, both appear to do same thing.
 IRegistry interface not fully utilised.

Note:
 Import loading is currently pointless as servers can not be made to refresh.


B.L Miller
28/03/2020  v0.1  LibPanelColumns.pas
03/09/2020  v1.0  Add registry interface method for writing..
06/09/2020  v1.1  Tidy up some comments.
11/09/2020  v1.2  cleaned up ver for release

IOptionsWriter methods              IOptionsWriter properties
   EraseSection
   WriteBoolean
   WriteDouble
   WriteInteger
   WriteString

IOptionsReader methods              IOptionsReader properties
   ReadBoolean
   ReadDouble
   ReadInteger
   ReadString
   ReadSection
   SectionExists
   ValueExists

IOptionsManager methods             IOptionsManager properties
   GetOptionsReader
   GetOptionsWriter
   OptionsExist

IRegistry              // many parallel functions to OptionReader/Writer but more flexible.
IDocumentOptionsSet    // interesting, but does not seem useful.
}

// Registry paths & special keys.
//                                     vv  SpecialKey_SoftwareAltiumApp  vv
// HKEY_CURRENT_USER/Software/Altium/Altium Designer {FB13163A-xxxxxxxxxxxxx}/DesignExplorer/Preferences
//                                                                           /Forms

const
    cRegistrySubPath = '\DesignExplorer\Preferences\';            // registry path to prefs from AD-install root.
 
{    cNameOfServer = 'Client';               // untested  
    cSectionNamesExport = 'Access|Client Preferences|Options Pages|Custom Colors';         // "Option Pages" should be useful
    cSectionNamesImport = 'Custom Colors';
}

{
    cNameOfServer = 'UnifiedComponent';      // all working
    cSectionNamesExport = 'Favorite UnifiedComponent Filter Expressions|Recent UnifiedComponent Filter Expressions';
    cSectionNamesImport = 'Favorite UnifiedComponent Filter Expressions|Recent UnifiedComponent Filter Expressions';
}

// IServerModule.ModuleName = 'Altium.Edp.ComponentSearch.Plugin'
// Components Panel ComponentSearch 
{
    cNameOfServer = 'ComponentSearch';     // all working
    cSectionNamesExport = 'BaseMarkupView|ComponentDetails|FavoriteFilterResult|FilterResult|SearchHistoryService|SearchResult|Settings';
    cSectionNamesImport = 'ComponentDetails|SearchResult';
}

//  IServerModule.ModuleName = 'Altium.Edp.PartSearch.Plugin'
{
    cNameOfServer = 'PartSearch';
    cSectionNamesExport = 'BaseMarkupView|SearchHistoryService';
    cSectionNamesImport = 'BaseMarkupView';

}

{
    cNameOfServer = 'ImportManager';
    cSectionNamesExport = 'Project|Layer|Layers';    // dnw 'Layers' 'Layer[s] Mapp[ing|ings|ed]' 'Used Layers' 'Layers Used'
    cSectionNamesImport = '';
                                   // dnw 'Layer Map'
}

//    cNameOfServer = 'LibraryInterface';

// LibraryBrowser.INI
{
    cNameOfServer = 'IntegratedLibrary';            //  TLibraryBrowserServerModule
    cSectionName  = 'Browser Settings';             // all working
    cSectionNamesExport = 'Browser Settings|Component Browser|Loaded Libraries|General';
    cSectionNamesImport = 'Browser Settings';
}
// WSM VersionControl

    cNameOfServer = 'VersionControl';
    cSectionNamesExport = 'DesignVaults|LocalHistory|Providers|StorageManager|SVN|SVNDbLib';
    cSectionNamesImport = '';

// WorkSpace
{
    cNameOfServer = 'WorkSpaceManager';
    cSectionNamesExport  = 'Favorite WorkspaceManager Filter Expressions|Recent WorkspaceManager Filter Expressions|Project Panel|General|View|Default Locations|WorkSpace Preferences|Client|Included Files|Search Result|Settings';
    cSectionNamesImport  = 'General';
// working : WorkSpace Preferences      // SectKeys required Trim()
}


var
    SectionNames : TStringList;
    SectKeys     : TStringList;

    Report       : TStringList;
    ReportDoc    : IServerDocument;
    AValue       : WideString;
    Flag         : Integer;
    INIFile      : TMemIniFile;            // do NOT use TIniFile as strips quotes at each end!
    Filename     : WideString;
    ViewState    : WideString;

function RegistryWriteString(const SKey : Widestring, const IKey : WideString, const IVal : WideString) : boolean;
var
    Registry : TRegistry;
Begin
    Result := false;
    Registry := TRegistry.Create;
    Try
        Registry.OpenKey(SKey, true);
        if Registry.ValueExists(IKey) then
            Result := true;   // Registry.ReadString(IKey);
        Registry.WriteString(IKey, IVal);
        Registry.CloseKey;

    Finally
        Registry.Free;
    End;
End;

procedure ImportServerOptionSection;
Var
    OpenDialog : TOpenDialog;
    Reader     : IoptionsReader;
    Writer     : IOptionsWriter;
    IniFile    : TMemIniFile;            // do NOT use TIniFile for READING as strips quotes at each end!
    ASModule   : IServerModule;
    AView      : IServerView;
    NView      : IServerView;
    PanelInfo  : IServerPanelInfo;
    I, J       : integer;
    DSOptions      : IDocumentOptionsSet;
    OptionsMan     : IOptionsManager;
    OptionsStorage : IOptionsStorage;
    OptionsPage    : IOptionsPage;
    SectName       : WideString;
    KeyName        : WideString;
    KeyValue       : WideString;
    RegSectKey     : WideString;
    RegItemKey     : WideString;
    bSuccess       : boolean;

Begin
    OptionsMan := Client.OptionsManager;

    Writer := OptionsMan.GetOptionsWriter(cNameOfServer);
    Reader := OptionsMan.GetOptionsReader(cNameOfServer,'');

    If (Writer = nil) or (Reader = nil) Then
    begin
//        ShowMessage('no options found ');
        Exit;
    end;

    OpenDialog        := TOpenDialog.Create(Application);
    OpenDialog.Title  := 'Import ' + cNameOfServer + ' Options *.ini file';
    OpenDialog.Filter := 'INI file (*.ini)|*.ini';
//    OpenDialog.InitialDir := ExtractFilePath(Board.FileName);
    OpenDialog.FileName := cNameOfServer + '*.ini';
    Flag := OpenDialog.Execute;
    if (Flag = 0) then exit;
    FileName := OpenDialog.FileName;
    IniFile := TMemIniFile.Create(FileName);


    SectionNames := TStringList.Create;
    SectionNames.Delimiter := '|';
    SectionNames.StrictDelimiter := true;
    SectionNames.DelimitedText := cSectionNamesImport;     // load from const

    SectKeys := TStringList.Create;
    SectKeys.Delimiter := '=';
    SectKeys.StrictDelimiter := true;
//    SectKeys.NameValueSeparator := '=';

    if OptionsMan.OptionsExist(cNameOfServer,'') then
    begin

        for J := 0 to (SectionNames.Count - 1) do
        begin
            SectName := SectionNames.Strings(J);
//            Client.ArePreferencesReadOnly(cNameOfserver, SectName);

            if IniFile.SectionExists(SectName) then
            if Reader.SectionExists(SectName) then
            begin
                IniFile.ReadSectionValues(SectName, SectKeys);

//            Writer.EraseSection(SectName);

                for I := 0 to (SectKeys.Count - 1) do
                begin
                    KeyName := SectKeys.Names(I);
                    KeyValue := SectKeys.ValueFromIndex(I);
                    Writer.WriteString(SectName, KeyName, KeyValue);

                    RegSectKey := SpecialKey_SoftwareAltiumApp + cRegistrySubPath + SectName;
                    bSuccess := RegistryWriteString(RegSectKey, KeyName, KeyValue);

                end;
            end
            else
                ShowMessage('server does not have this section ' + SectName);

            SectKeys.Clear;
        end;
    end;
    Reader := nil;
    Writer := nil;

//    Client.SetPreferencesChanged(true);
//    Client.GUIManager.UpdateInterfaceState;

    IniFile.Free;
End;

procedure ExportServerOptionSection;
Var
//    FileName   : String;
    SaveDialog : TSaveDialog;
    Reader     : IOptionsReader;      // TRegistryReader
    Reader2    : IOptionsReader;
    IniFile    : TIniFile;            // do NOT use TIniFile for READING as strips quotes at each end!
    SectName   : WideString;
    I, J       : integer;
    DSOptions : IDocumentOptionsSet;

Begin
    Reader := Client.OptionsManager.GetOptionsReader(cNameOfServer,'');
//    Reader2 := Client.OptionsManager.GetOptionsReader_FromIniFile(SpecialFolder_ExportPreferences+IniFileName);

    If Reader = Nil Then
    begin
        ShowMessage('no options found ');
        Exit;
    end;

    SaveDialog        := TSaveDialog.Create(Application);
    SaveDialog.Title  := 'Export ' + cNameOfServer + ' Options *.ini file';
    SaveDialog.Filter := 'INI file (*.ini)|*.ini';
    FileName := cNameOfServer + '_Options.ini';  // ExtractFilePath(Board.FileName);
    SaveDialog.FileName := FileName;            // ChangeFileExt(FileName, '');

    Flag := SaveDialog.Execute;
    if (Flag = 0) then exit;

    // Get file & set extension
    FileName := SaveDialog.FileName;
    FileName := ChangeFileExt(FileName, '.ini');
    IniFile := TIniFile.Create(FileName);

    SectionNames := TStringList.Create;
    SectionNames.Delimiter := '|';
    SectionNames.StrictDelimiter := true;
    SectionNames.DelimitedText := cSectionNamesExport;     // load from const

    Report   := TStringList.Create;
    SectKeys := TStringList.Create;
    SectKeys.Delimiter := #13;
    SectKeys.StrictDelimiter := true;
//    SectKeys.NameValueSeparator := '=';

    Filename := '';
    ReportDoc := nil;
    Report.Add(SpecialKey_SoftwareAltiumApp);
    Report.Add(cNameOfServer);

    for J:= 0 to (SectionNames.Count - 1) do
    begin
        SectName := SectionNames.Strings(J);

        if Reader.SectionExists(SectName) then
        begin
            AValue := Reader.ReadSection(SectName);
            SectKeys.DelimitedText := Trim(AValue);
            Report.Add(SectName + '  option count : ' + IntToStr(SectKeys.Count));
//            Report.Add(AValue);

            for I := 0 to (SectKeys.Count - 1) do
            begin
                SectKeys.Strings(I) := Trim(SectKeys.Strings(I));
                AValue := Reader.ReadString(SectName,SectKeys.Strings(I), ' ');
                AValue := Trim(AValue);
                IniFile.WriteString(SectName, SectKeys.Strings(I), AValue);
                Report.Add(IntToStr(I) + ' ' + PadRight(SectKeys.Strings(I), 45) + ' = ' + AValue);
            end;
            Report.Add('');
        end else
            ShowMessage('section ' + SectName + ' not found');

    end;

    Filename := SpecialFolder_TemporarySlash + cNameOfServer + '-Options-Report.txt';
    Report.SaveToFile(Filename);

    SectKeys.Free;
    SectionNames.Free;
    Report.Free;
    IniFile.Free;

    if FileName <> '' then
        ReportDoc := Client.OpenDocument('Text', FileName);
    If ReportDoc <> Nil Then
    begin
        Client.ShowDocument(ReportDoc);
        if (ReportDoc.GetIsShown <> 0 ) then
            ReportDoc.DoFileLoad;
    end;
end;


function ServerOptionReadBool(const NOS : WideString, const SettingName : WideString;) : boolean;
Var
    Reader : IOptionsReader;
    DefaultValue : boolean;
Begin
    DefaultValue := false;
    Reader := Client.OptionsManager.GetOptionsReader(NOS,'');
    If Reader = Nil Then Exit;
    Result := Reader.ReadBoolean(NameOfServerPreferences,SettingName,DefaultValue);
End;

// special exported Prefs file IncludedFiles.ini has list of all othe ini files & sections & key values..
// is there a Reader Options that can get same info?

// from registry
{ ComponentSearch (Panel)  
    BaseMarkupView
    ComponentDetails
    FavoriteFilterResult
    FilterResult
    SearchHistoryService
    SearchResult
    Settings
}
{ Section names for IntegratedLibrary:
 Add Remove
 Add Supplier Links
 Browser Settings
 Ciiva
 Component Browser
 Edit Supplier Links Form
 Favorite IntegratedLibrary Filter Expressions
 General
 Import Parameters
 Loaded Libraries
 Models
 Recent IntegratedLibrary Filter Expressions
 Repository Browser
 Search
 Supplier Inspector Panel
 Supplier Search Panel
 Suppliers
}
// exported Prefs inifiles for IntegratedLibrary server
{
    IniFileName = 'IntLib_Installed.ini';
    SectionName = 'IntLib_Installed';
}
{
// Exported-Prefs:IntLib_Installed.ini & IntegratedLibrary::Loaded Libraries server
[IntLib_Installed]
InstalledRelativePath=C:\Altium\AD16\Library\
Library0=C:\Altium\AD16\Library\Miscellaneous Devices.IntLib
LibraryRelativePath0=Miscellaneous Devices.IntLib
LibraryActivated0=1
Library1=C:\Altium\AD16\Library\Miscellaneous Connectors.IntLib
LibraryRelativePath1=Miscellaneous Connectors.IntLib
LibraryActivated1=1
}

// wrong value for section const cGraphicalPreferences
{    cNameOfServer = 'CGraphicViewer';
    cSectionNamesExport = 'cGraphicPreferences|ScaleImage|FScaleImage|KeepAspectRatio';
    cSectionNamesImport = 'ScaleImage';
}
{
    DSOptions : IDocumentOptionsSet;
    Client.GetInternalOptionsManager.GetPageName;      // ''Snippets Folder'
    Client.GetOptionsSetCount;                         // = 2
    DSOptions := Client.GetOptionsSetByName('EmbeddedOptions');   // works.
    DSOptions := Client.GetOptionsSet(0);

//                                    Set(0)               Set(1)
    DSOptions.GetSetName ;         // EmbeddedOptions      IntegratedLibrary_Options
    DSOptions.GetSortName;         // '000'                '055'
    DSOptions.GetHostServer;       // 'WorkSpaceManager'   'IntegratedLibrary'
    DSOptions.IsAllDocuments;      //                 'False'
    DSOptions.IsAllProjects;       //                 'False'
    DSOptions.IsForDocumentKind(cDocKind_IntegratedLibrary);   // 'false'  'true'
}
