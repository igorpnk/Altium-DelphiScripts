{ Prj-Parameters.pas
Summary
    Export/import project parameters to/from ini file.
    Adds new paramters wuth value.
    Updates existing with new values if changed.

Added DemoAddNewParameters proc to show how to add parameters from ParameterList etc..

Author BL Miller
Date
18/09/2019 : v0.1 Initial POC .. seems to work
}

const
    cDummyTuples  = 'Area=51 | Answer=42 | Question=forgotten';
    TopLevelKey   = 'PRJParameters';   // ini file section heading
    NoVariantName = 'No Variation';

Var
    WS           : IWorkSpace;
    IniFile      : TIniFile;
    Flag         : Integer;
    VersionMajor : WideString;
    ExtParas     : IExternalParameter;

function Version(const dummy : boolean) : TStringList;
begin
    Result := TStringList.Create;
    Result.Delimiter := '.';
    Result.Duplicates := dupAccept;
    Result.DelimitedText := Client.GetProductVersion;
end;

function ParameterExistsUpdateValue(Prj : IProject, var Parameter : TParameter, var existingvalue : widestring) : boolean;
var
    TempPara : TParameters;   //  DMObject TParameterAdapter
    I        : integer;
begin
//  must be a parameterlist lookup method.. no.

    Result := false;
    for I := 0 to (Prj.DM_ParameterCount - 1) do
    begin
        TempPara := Prj.DM_Parameters(I);
        if TempPara.DM_Name = Parameter.Name then
        begin
            existingvalue := TempPara.DM_Value;
            if (existingvalue <>  Parameter.Value) then
                TempPara.DM_SetValue(Parameter.Value);     // update value of existing
            Result := true;                                // found para Name
        end;
    end;
end;

Procedure DemoAddNewParameters;
var
    Prj           : IProject;
    ParameterList : TParameterList;
    ParaSList     : TStringList;
    Parameter     : TParameter;
    PName         : WideString;
    OrigValue     : WideString;
    PVal          : WideString;
    I             : integer;
begin
   WS := GetWorkSpace;
   Prj := WS.DM_FocusedProject;
   if Prj = nil then exit;

   VersionMajor := Version(true).Strings(0);

// ParameterLists  demo
    ParameterList := TParameterList.Create;
    ParameterList.ClearAllParameters;
    ParameterList.SetState_FromString(cDummyTuples);

//  good for finding optional parameter text
    PName := 'Area';
    if ParameterList.GetState_ParameterAsString(PName, PVal) then
        ShowMessage('found in TPL:  '+ PName + ' = ' + PVal);
// or
    Parameter := ParameterList.GetState_ParameterByName(PName);      // this creates the TParameter object
    Parameter.Name; Parameter.Value;
// bad for indexing because that returns a pointer (DelphiScript is hopeless with pointers)

// StringList with delimited input & name value tuples.
    ParaSList := TStringList.Create;
    ParaSList.Delimiter := '|';
    ParaSList.Duplicates := dupAccept;       //  dupIgnore
    ParaSList.DelimitedText := cDummyTuples;

    for I := 0 to (ParaSList.Count - 1) do
    begin
        OrigValue := '';
        Parameter.Name  := ParaSList.Names(I);
        Parameter.Value := ParaSList.ValueFromIndex(I);

        if ParameterExistsUpdateValue(Prj, Parameter, OrigValue) then
            ShowMessage('Found Existing parameter ' + Parameter.Name + ' has old val= ' + OrigValue + ' & new val= ' + Parameter.Value)
        else
        begin
            Prj.DM_BeginUpdate;
            Prj.DM_AddParameter(Parameter.Name, Parameter.Value);
            Prj.DM_EndUpdate;
            ShowMessage('Added new para ' + Parameter.Name + '  with val= ' + Parameter.Value);
        end;
    end;
    ParaSList.Clear;
    ParaSList.Free;
    ParameterList.Destroy;

    Prj.DM_RefreshInWorkspaceForm;
end;

procedure ExportPrjParas(const Prj : IProject, const FileName : WideString);
var
    Parameter    : TParameter;
    Variant      : TProjectVariant;
    VariantName  : WideString;
    CurVarName   : WideString;
    VariantCount : integer;
    VersionAll   : WideString;
    I            : integer;

begin
    VersionMajor := Version(true).Strings(0);
    VersionAll   := Version(true).DelimitedText;

    VariantName := NoVariantName;
    VariantCount := Prj.DM_ProjectVariantCount;

    Variant := Prj.DM_CurrentProjectVariant;
    if Variant <> Nil then
        VariantName := Variant.Name;
     CurVarName := VariantName;

    IniFile := TIniFile.Create(FileName);
    IniFile.WriteString('ReleaseVersion', 'Altium',        VersionAll);
    IniFile.WriteString('Project', Prj.DM_ProjectFileName, Prj.DM_ObjectKindString);
    IniFile.WriteString('Project', 'VariantCount',         VariantCount);
    IniFile.WriteString('Project', 'CurrentVariant',       VariantName);
    IniFile.WriteString('Project', 'ParameterCount',       Prj.DM_ParameterCount);

    for I:= 0 to (VariantCount - 1) do
    begin
        Variant :=  IProject.DM_ProjectVariants(I);
        VariantName := Variant.Name;
        IniFile.WriteBool('ProjectVariants' +IntToStr(I), VariantName, (VariantName = CurVarName) );
    end;

    for I := 0 to (Prj.DM_ParameterCount - 1) do
    begin
        Parameter := Prj.DM_Parameters(I);
        IniFile.WriteString(TopLevelKey, Parameter.DM_Name, Parameter.DM_Value );
{
            TempPara.DM_Description;
            TempPara.DM_ConfigurationName;
            TempPara.DM_Kind;
            TempPara.DM_RawText;
            TempPara.DM_LongDescriptorString;
            TempPara.DM_OriginalOwner;
            TempPara.DM_Visible;
 }
    end;

    IniFile.Free;
end;

procedure ImportPrjParas(const Prj : IProject, const FileName : WideString);
var
    TuplesList : TStringList;
    ParameterList : TParameterList;   // need to instantiate parameter.
    Parameter  : TParameter;
    OrigValue  : WideString;
    I          : integer;
    NewParameterCount : integer;
    ChangeValueCount  : integer;

begin
    IniFile    := TIniFile.Create(FileName);
    TuplesList := TStringList.Create;
    TuplesList.Delimiter := ',';
    TuplesList.NameValueSeparator := '=';
    TuplesList.Duplicates := dupIgnore;

// required nonsense below
    ParameterList := TParameterList.Create;
    ParameterList.ClearAllParameters;
    ParameterList.SetState_FromString('dumb=dumber');
    Parameter := ParameterList.GetState_ParameterByName('dumb');

//    Tuple := IniFile.ReadString(TopLevelKey, '', '' );
//    IniFile.ReadSection(TopLevelKey, TuplesList);

    IniFile.ReadSectionValues( TopLevelKey, TuplesList);
    IniFile.Free;

    NewParameterCount := 0;
    ChangeValueCount  := 0;

    for I := 0 to (TuplesList.Count - 1) do
    begin
        OrigValue := '';
        Parameter.Name  := TuplesList.Names(I);
        Parameter.Value := TuplesList.ValueFromIndex(I);

        if ParameterExistsUpdateValue(Prj, Parameter, OrigValue) then
        begin
            if OrigValue <> Parameter.Value then
            begin
                ShowMessage('Found Existing Parameter ' + Parameter.Name + ' has old val= ' + OrigValue + ' & new val= ' + Parameter.Value);
                inc(ChangeValueCount);
            end;
        end
        else
        begin
            Prj.DM_BeginUpdate;
            Prj.DM_AddParameter(Parameter.Name, Parameter.Value);
            Prj.DM_EndUpdate;
            inc(NewParameterCount);
            ShowMessage('Added new para ' + Parameter.Name + '  with val= ' + Parameter.Value);
        end;
    end;
    ShowMessage('Existing Parameter Value Change Count : ' + PadRight(IntToStr(ChangeValueCount), 3));
    if not (NewParameterCount = 0) then
        ShowMessage('New Parameter(s) Added Count : ' + PadRight(IntToStr(NewParameterCount), 3))
    else
        ShowMessage('ZERO New Parameters Added');

    TuplesList.Clear;
    Tupleslist.Free;
    Parameter.Free;
    ParameterList.Destroy;
end;

// wrapper for direct call
procedure ExportProjectParameters;
var
    Prj         : IProject;
    SaveDialog  : TSaveDialog;
    FileName    : String;

begin
    WS := GetWorkSpace;
    Prj := WS.DM_FocusedProject;
    if Prj = nil then exit;
    FileName := Prj.DM_ProjectFullPath;

    SaveDialog        := TSaveDialog.Create(Application);
    SaveDialog.Title  := 'Export Project Parameters to *.ini file';
    SaveDialog.Filter := 'INI file (*.ini)|*.ini';
//    FileName := ExtractFilePath(Board.FileName);
    SaveDialog.FileName := ChangeFileExt(FileName, '-PrjPara.ini');

    Flag := SaveDialog.Execute;
    if (Flag = 0) then exit;
    FileName := SaveDialog.FileName;
    ExportPrjParas(Prj, FileName);
end;

// wrapper for direct call
procedure ImportProjectParameters;
var
    Prj         : IProject;
    OpenDialog  : TOpenDialog;
    FileName    : String;
begin
    WS := GetWorkSpace;
    Prj := WS.DM_FocusedProject;
    if Prj = nil then exit;
    FileName := Prj.DM_ProjectFullPath;

    OpenDialog        := TOpenDialog.Create(Application);
    OpenDialog.Title  := 'Import Project Parameters from *.ini file';
    OpenDialog.Filter := 'INI file (*.ini)|*.ini';
//    OpenDialog.InitialDir := ExtractFilePath(Board.FileName);
//  dialog uses windows internal mechanism to cache the previous use of Save or OpenDialog
    OpenDialog.FileName := '';
    Flag := OpenDialog.Execute;
    if (Flag = 0) then exit;

    FileName := OpenDialog.FileName;
    ImportPrjParas(Prj, FileName);
end;


// ExtParas := IExternalParameter.DM_GetName('OriginalDate');
{
The IExternalParameter interface defines the external parameter object.
Interface Methods
Method                                  Description
Function  DM_GetSection : WideString;   Returns the Section string of the external parameter interface.
Function  DM_GetName : WideString;  Returns the Name string of the external parameter interface.
Function  DM_GetValue : WideString;     Returns the Value string of the external parameter interface.
Procedure DM_SetValue(AValue : WideString);     Sets the new value string for this external parameter.
}

