{ OJS-BoardThickness
  from SimpleOJScript.pas

  Usage:
     Script (.pas file) must be part of a board project (does not need to be in same folder)
     .pas & .dfm must be in same folder.
     Add script to OutJob Reports Output/Scripts Output..
     Set Names & paths as usual: RMB Configure, Change Generate.

 Summary
     Example of OutJob script interaction.
     Supports the Configure Change & Generate functions of OutJob.

     ONLY supports use of FIXED output filenames; NO container or type or parameter names.

     Change: supports Open & Add outputs to project & custom output paths & filename
     Configure: supports passing source document static/stored parameter thru' to Generate
     Main code block can be tested outside OutJob by using DirectCall()

Notes:
    Scripts in same project then all have public fn()s & procedures.
    So can can keep this code separate (reusable) from main working script.
    The code is separated by function as much as possible?
    OutJob functions are self contained at bottom apart from one call to get SourceDocument via form UI.
    Configure form is potentially not required but there is no other source doc picking mechanism
    Can't see a simple way to display the chosen source document yet.
    Could be expanded to add other parameters
    Can test the form UI by removing (dummy : boolean) parameter & calling direct outside of OutJob.
    May or may not need the Script project to run outside of OutJob (which is in a project)

    ONLY supports use of FIXED output filenames; NO container or type or parameter names.


Author : B.L. Miller
29/05/2020  v0.10 inital POC
29/05/2020  v0.11 handle Configure() having NOT been run, test SourceFilename & set to PrimaryImplDoc in Generate but don't store in OJ.
23/11/2020  v0.12 Don't block the Project Releaser success.
..............................................................................}

Interface    // not sure this is not just ignored in delphiscript.
type
    TFormPickFromList = class(TForm)
    ButtonExit        : TButton;
    ComboBoxFiles     : TComboBox;
    procedure FormPickFromListCreate(Sender: TObject);
    procedure ButtonExitClick(Sender: TObject);
end;

Const
    cDefaultReportFileName   = 'OJS-BoardThicknessReport.txt';    //default output report name.
    cSourceFileNameParameter = 'SourceFileName';         // Parameter Name to store static data from configure
    cSourceFileName          = 'dummy.PcbDoc';
    cBoardThicknessParameter = 'BoardTotalThickness';    // Prj parameter name

Var
    WS               : IWorkspace;
    Doc              : IDocument;
    FilePath         : WideString;
    Prj              : IBoardProject;
    Board            : IPCB_Board;
    PrjReport        : TStringList;
    FormPickFromList : TFormPickFromList;

{..............................................................................}
function ParameterAddUpdateValue(Prj : IProject, const ParaName : Widestring, const ParaValue : WideString, var existingvalue : widestring) : boolean;
var
    TempPara : TParameters;   //  DMObject TParameterAdapter
    I        : integer;
begin
//  must be a parameterlist lookup method.. no.

    Result := false;
    for I := 0 to (Prj.DM_ParameterCount - 1) do
    begin
        TempPara := Prj.DM_Parameters(I);
        if TempPara.DM_Name = ParaName then
        begin
            existingvalue := TempPara.DM_Value;
            if (existingvalue <>  ParaValue) then
                TempPara.DM_SetValue(ParaValue);     // update value of existing
            Result := true;                                // found para Name
        end;
    end;
    if not Result then
    begin
        Prj.DM_BeginUpdate;
        Prj.DM_AddParameter(ParaName, ParaValue);
        Prj.DM_EndUpdate;
        ShowMessage('Added new para ' + ParaName + '  with val= ' + ParaValue);
        Result := true;
    end;
end;

function BoardThicknessInfo(Board : IPCB_Board) : TCoord;
var
    LayerStack    : IPCB_LayerStack;
    LayerObj      : IPCB_LayerObject;
    LayerClass    : TLayerClassID;
//    Layer         : TLayer;
    Dielectric  : IPCB_DielectricObject;
    Copper      : IPCB_ElectricalLayer;

begin
    LayerStack := Board.LayerStack;
    Result := 0;

    for LayerClass := eLayerClass_All to eLayerClass_PasteMask do
    begin
        LayerObj := LayerStack.First(LayerClass);

        While (LayerObj <> Nil ) do
        begin
            case LayerClass of
                eLayerClass_Electrical :
                begin
                   Copper := LayerObj;
                   Result := Result + Copper.CopperThickness;
                end;
// this includes soldermask
                eLayerClass_Dielectric :
                begin
                    Dielectric := LayerObj;  // .Dielectric Tv6
                    Result     := Result + Dielectric.DielectricHeight;
                end;
            end;
            LayerObj := LayerStack.Next(Layerclass, LayerObj);
        end;
    end;
end;

Procedure ReportPCBStuff (SourceFileName : WideString, const ReportFileName : WideString, const AddToProject : boolean, const OpenOutputs : boolean);
var
    ReportDocument : IServerDocument;
    I              : Integer;
    FileName       : String;
    TotThickness   : TCoord;
    ParaName       : WideString;  //TParameter too hard to create instance.
    ParaValue      : WideString;
    existingvalue  : widestring;

Begin
    WS  := GetWorkspace;
    if WS = Nil Then Exit;
    Prj := WS.DM_FocusedProject;
    if Prj = Nil then exit;

//    PrimDoc := Prj.DM_PrimaryImplementationDocument;
//    if Primdoc = Nil then
//        exit
//    else
//        Board := PCBServer.GetPCBBoardByPath(PrimDoc.DM_FullPath);
//    if Board = Nil then exit;
    BeginHourGlass(crHourGlass);

    for I := 0 to (Prj.DM_LogicalDocumentCount - 1) do
    begin
        Doc := Prj.DM_LogicalDocuments(I);
        if Doc.DM_FileName = SourceFilename then
        begin
            break;
        end;
    end;

    PrjReport  := TStringList.Create;
    PrjReport.Add('Information:');
    Prjreport.Add(DateToStr(Date) + ' ' + TimeToStr(Time));
    PrjReport.Add('  Project : ' + Prj.DM_ProjectFileName);
    FilePath := ExtractFilePath(Prj.DM_ProjectFullPath);
    PrjReport.Add('  Path    : ' + FilePath);

    if (Doc.DM_FileName = SourceFileName) then
    begin
        PrjReport.Add('  SourceFileName : ' + SourceFileName);

        if (Doc.DM_DocumentKind = cDocKind_Pcb)then
        begin
            Board := PCBServer.GetPCBBoardByPath(Doc.DM_FullPath);
            if Board = Nil then
                Board := PCBServer.LoadPCBBoardByPath(Doc.DM_FullPath);

            TotThickness := BoardThicknessInfo(Board);

            existingvalue := '';
            ParaName      := cBoardThicknessParameter;
            ParaValue     := CoordUnitToString(TotThickness, eMetric);
            ParameterAddUpdateValue(Prj, ParaName, ParaValue, existingvalue);

            PrjReport.Add('  Board   : ' + Board.FileName + '  ' + ParaName + ' = ' + ParaValue);
            PrjReport.Add('');
        end;

        if (Doc.DM_DocumentKind = cDocKind_Sch)then
        begin
            PrjReport.Add('  do something SchDoc-ish');
        end;
    end
    else
    begin
        PrjReport.Add(' Source Doc NOT found');
    end;

    PrjReport.Add('===========  EOF  ==================================');

    FilePath := ExtractFilePath(ReportFileName);
    if not DirectoryExists(FilePath) then
        DirectoryCreate(FilePath);

    PrjReport.SaveToFile(ReportFileName);

    EndHourGlass;

    if AddToProject then Prj.DM_AddSourceDocument(ReportFileName);
    if OpenOutputs then
    begin
        ReportDocument := Client.OpenDocument('Text', ReportFileName);
        If ReportDocument <> Nil Then
        begin
            Client.ShowDocument(ReportDocument);
            if (ReportDocument.GetIsShown <> 0 ) then
                ReportDocument.DoFileLoad;
        end;
    end;
End;

procedure DirectCall;      // test outside of OutJob
var
    FileName : WideString;
begin
    If PCBServer = Nil Then Exit;
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;

    FilePath := ExtractFilePath(Board.FileName) + 'Script_Direct_Output\';
    FileName := ExtractFileName(Board.FileName);
    ReportPCBStuff(FileName, FilePath + cDefaultReportFileName, true, true);
end;

procedure SetupComboBoxFromProject(ComboBox : TComboBox; Prj : IProject);
var
    i : integer;
begin
    ComboBox.Items.Clear;
    for i := 0 to (Prj.DM_LogicalDocumentCount - 1) Do
    begin
        Doc := Prj.DM_LogicalDocuments(i);
        If Doc.DM_DocumentKind = cDocKind_Pcb Then
            ComboBoxFiles.Items.Add(Doc.DM_FileName);
    end;
end;

function PickSourceDoc(const dummy : boolean) : WideString;
begin
    FormPickFromList.ShowModal;
    Result:= FormPickFromList.ComboBoxFiles.Items(ComboBoxFiles.ItemIndex);
end;

procedure testform(dummy : boolean);      // test the Form events work by removing dummy parameter
var
   FName : WideString;
begin
    FormPickFromList.ShowModal;
    FName := FormPickFromList.ComboBoxFiles.Items(ComboBoxFiles.ItemIndex);
    ShowMessage('picked ' + FName);
end;

procedure TFormPickFromList.FormPickFromListCreate(Sender: TObject);
var
    Prj : IProject; 

begin
    Prj := GetWorkSpace.DM_FocusedProject;
    SetupComboBoxFromProject(ComboBoxFiles, Prj);
end;

Procedure TFormPickFromList.ButtonExitClick(Sender: TObject);
Begin
    Close;
End;


// ------------  OutJob entry points   ----------------------------------------------
// OutJob RMB menu Configure
// seems to pass in focused PcbDoc filename.
Function Configure(Parameter : String) : String;
var
    ParamList      : TStringList;
    SourceFileName : WideString;
    I              : integer;

begin
    ParamList := TStringList.Create;
    ParamList.Clear;
    ParamList.Delimiter  := '|';
    ParamList.StrictDelimiter := true;
    ParamList.NameValueSeparator := '=';
    ParamList.DelimitedText := Parameter;

//    SourceFileName := cDefaultInputFileName;
// write function to pick form list etc
// undefined blank file name is okay..
    SourceFileName := PickSourceDoc(false);

    I := ParamList.IndexOfName(cSourceFileNameParameter);
    if I > -1 then
        ParamList.ValueFromIndex(I) := SourceFileName;

    Result := ParamList.DelimitedText;
    ParamList.Free;
end;

// OutJob Output Container "change"
Function PredictOutputFileNames(Parameter : String) : String;
// Parameter == TargetFolder=   TargetFileName=    TargetPrefix=   OpenOutputs=(boolean)   AddToProject=(boolean)
// return is just the filename
var
    ParamList    : TStringList;
    bValue       : boolean;
    TargetFolder : WideString;
    TargetFN     : WideString;
    TargetPrefix : WideString;
    I            : integer;

begin
    ParamList := TStringList.Create;
    ParamList.Clear;
    ParamList.Delimiter  := '|';
    ParamList.StrictDelimiter := true;    // extra spaces appear around value ?
    ParamList.NameValueSeparator := '=';
    ParamList.DelimitedText := Parameter;
    ParamList.Count;

    TargetPrefix := '';
    I := ParamList.IndexOfName('TargetPrefix');
    if I > -1 then TargetPrefix := Trim(ParamList.ValueFromIndex(I));
    TargetFolder := '';
    I := ParamList.IndexOfName('TargetFolder');
    if I > -1 then TargetFolder := Trim(ParamList.ValueFromIndex(I));
    TargetFN := '';
    I := ParamList.IndexOfName('TargetFileName');
    if I > -1 then TargetFN := Trim(ParamList.ValueFromIndex(I));

    Result := TargetFN;

    if SameString(TargetFN,'',True) then
    begin
        Result := cDefaultOutputFileName;
        I := ParamList.IndexOfName('TargetFileName');
        if I > -1 then
//            ParamList.Put(I, 'TargetFileName=' + cDefaultOutputFileName)
            ParamList.ValueFromIndex(I) := cDefaultOutputFileName
        else
            ParamList.Add('TargetFileName=' + cDefaultOutputFileName);
    end;

//This function should be using parameters
//    Result := ParamList.DelimitedText;
    ParamList.Free;
end;

// OutJob Generate Output Button
Function Generate(Parameter : String) : String;
// Parameter == TargetFolder=   TargetFileName=    TargetPrefix=   OpenOutputs=(boolean)   AddToProject=(boolean)
var
    ParamList      : TStringList;
    SourceFileName : WideString;
    TargetFolder   : WideString;
    TargetFN       : WideString;
    TargetPrefix   : WideString;
    tmpstr         : WideString;
    I              : integer;
    AddToProject   : boolean;
    OpenOutputs    : boolean;

begin
    Result := 'Success=0';

    ParamList := TStringList.Create;
    ParamList.Clear;
    ParamList.Delimiter  := '|';
    ParamList.StrictDelimiter := true;
    ParamList.NameValueSeparator := '=';
    ParamList.DelimitedText := Parameter;

    TargetPrefix := '';
    I := ParamList.IndexOfName('TargetPrefix');
    if I > -1 then TargetPrefix := Trim(ParamList.ValueFromIndex(I));

    TargetFolder := '';
    I := ParamList.IndexOfName('TargetFolder');
    if I > -1 then TargetFolder := Trim(ParamList.ValueFromIndex(I));

    TargetFN := '';
    I := ParamList.IndexOfName('TargetFileName');   // Prefix');
    if I > -1 then TargetFN := Trim(ParamList.ValueFromIndex(I));

    SourceFileName := '';
    I := ParamList.IndexOfName(cSourceFileNameParameter);
    if I > -1 then
        SourceFileName := Trim(ParamList.ValueFromIndex(I));

//  explicit filename target gets stored by Configure.
//  don't store PCB into OJob just let it use same primary doc logic next time.
    if SourceFileName = '' then
    begin             // in case configure was never run.
        SourceFileName := GetWorkSpace.DM_FocusedProject.DM_PrimaryImplementationDocument.DM_FileName;
        if SourceFileName = '' then
            SourceFileName := cSourceFileName;
    end;

    OpenOutputs := false;
    I := ParamList.IndexOfName('OpenOutputs');
    if I > -1 then
        Str2Bool(ParamList.ValueFromIndex(I), OpenOutputs);

    AddToProject := false;
    I := ParamList.IndexOfName('AddToProject');
    if I > -1 then
        Str2Bool(ParamList.ValueFromIndex(I), AddToProject);

    if TargetFolder = '' then
        TargetFolder := ExtractFilePath( GetWorkspace.DM_FocusedProject );
// if output filename is NOT changed from default then Parameter TargetFileName = ''  dumb yeah.
    if TargetFN = '' then
        TargetFN := cDefaultReportFileName;

// if TargetFd contains '.\' then is encoded as resolved relative path.
    tmpstr := TargetFolder;
    I := ansipos('.\', TargetFolder);
    if I > 3 then
    begin
        SetLength(tmpstr, I - 1);
        Delete(TargetFolder, 1, I + 1);
        tmpstr := tmpstr + TargetFolder;
        TargetFolder := tmpstr;
    end;

    TargetFN := TargetFolder + TargetFN;
    ReportPCBStuff(SourceFileName, TargetFN, AddToProject, OpenOutputs);

//   ParamList.Add('OutputStatus=Fail');       //Success
//   Result := ParamList.DelimitedText; // 'false';  //'simple string returned';
    ParamList.Free;

    Result := 'Success=1';
end;

