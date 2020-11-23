{  B0M-ReWriter.pas


 Use in OutJob container as part of project
 Script must be part of the board project
 Outfile is setup by "Change" button unless auto-generated..

 Can be called directly or via Outjob interface.
 Direct call test method enables "open outputs".
 Has an OutJob report dump.

 Does NOT support project parameters.

 Script attempts to:-
 - create a processed txt file "copy" of BOM doc & stores at Container's predicted output.
 - find (this) script connected to a BOM output via a shared container.
 - get BOM output file & path.
 - force OutJob saved if loaded file has been changed
 - try to honour the OutJob container [fields] & paths.

 Requires:-
 - a BOM type outputer & (this) script outputer to be connected to same Output Container
 - script MUST know its own name cScriptKind.
 - script manually loads the OutJob file to fill in all the holes in API.

   Supports relative path setting
   Supports the std OutJob field variables.
   File path & names may fail for some scenarios
   NO support for project parameters in filenames.

BL Miller
14/03/2020  v0.10 POC example.
15/03/2020  v0.11 File exists tested the wrong (outfile) file & check/create new paths
18/03/2020  v0.12 Fix bug in generate (no source file parameter) if configure had never been run
                  Attempt support for relative path in Change.
23/03/2020  v0.20 Use BOM output path to get input file for script. Support? fields.
30/03/2020  v0.21 More protection for missing parameters in callback functions.
23/11/2020  v0.22 unblock Prj Releaser
}

const
    bDebugfile               = true;
    cScriptName              = 'BoM-ReWriter.pas';         // NOT possible to get active container; must find one with matching Outputer
    cScriptKind              = 'EditScript';               // cDocKind_EditScript = 'EDITSCRIPT'

// the 3 const below are used but have NO effect/influence
    cSourceFileNameParameter = 'SourceFileName';           // Parameter Name to store static data from Configure into OutJob.
    cDefaultInputFileName    = 'input.txt';                // default until you write function to pick/set another.
    cDefaultOutputFileName   = 'output.txt';               // default until hit change & setup diff filename.

// OutJob Publish section for Media/Medium/Containers
    cOJFHeadingPublish           = 'PublishSettings';
    cOJFReleaseManaged           = 'ReleaseManaged';             // =0 or =1
    cOJFOutputBasePath           = 'OutputBasePath';             // could be '.\'
    cOJFOutputFilePath           = 'OutputFilePath';             // P:\testsvn\AltiumProjects\JuanF\.\Test\
    cOJFOutputPathMedia          = 'OutputPathMedia';            // [Media Name]
    cOJFOutputPathMediaValue     = 'OutputPathMediaValue';
    cOJFOutputPathOutputer       = 'OutputPathOutputer';         // [Output Type]
    cOJFOutputPathOutputerPrefix = 'OutputPathOutputerPrefix';
    cOJFOutputPathOutputerValue  = 'OutputPathOutputerValue';    // = ''
    cOJFOutputFileName           = 'OutputFileName';             // = ''
    cOJFOutputFileNameMulti      = 'OutputFileNameMulti';        // custom_filename_output2.txt
    cOJFUseOutputNameForMulti    = 'UseOutputNameForMulti';      // =0  or ?
    cOJFOutputFileNameSpecial    = 'OutputFileNameSpecial';      // = ''

var
    Prj          : IProject;
    PrjConfig    : IConfiguration;
    Doc           : IDocument;
    ServerDoc     : IServerDocument;
    OutPutMan     : IOutputManager;
    OJDoc         : TJobManagerDocument;   // IWSM_OutputJobDocument;
    OJob          : IOutputJob;
    Output        : IOutputer;
    POutput       : IOutputer;
    OJContainer   : IOutputMedium;
    OPSettings    : TOutputSettings;
    VariantS      : TOutputJobVariantScope;
    PreDefinedOP  : TPredefinedOutput;
    OPGen         : TOutputGenerator;
    ContainerSect : TStringList;
    Rpt           : TStringList;

function ParseTheOutJobfile(Doc : IServerDocument, SectionName : WideString) : TStringList;
var
    INIFile       : TIniFile;

begin
    Result := TStringList.Create;
    Result.Delimiter := '\n';
    Result.NameValueSeparator := '=';
    Result.Duplicates := dupIgnore;

    INIFile := TIniFile.Create(Doc.FileName);
    if IniFile.SectionExists(SectionName) then
        IniFile.ReadSectionValues(SectionName, Result);

    INIFile.Free;
end;

function UnRelativePath(const RFP : WideString) : WideString;
var
    I     : integer;
    sTemp : WideString;
begin
    Result:= RFP;
    sTemp := RFP;
    I := ansipos('.\', sTemp);
    if I > 5 then
    begin
        SetLength(Result, I - 1);
        Delete(sTemp, 1, I + 1);
        Result := Result + sTemp;
    end;
end;

function EvaluateFields(OM : IOutputMedium, OP : IOutputer, const Field : WideString) : Widestring;
begin
    Result := Field;
    case Field of
    '[Container Name]' : Result := OM.Name;
    '[Container Type]' : Result := OM.TypeString;
// with multi Media Name is Outputer generatorname script of BOM etc
    '[Media Name]'     : Result := OP.DM_GeneratorName;   //   OM.Name;
    '[Output Type]'    : Result := OP.DM_GeneratorName;
    '[Output Name]'    : Result := OP.DM_GetDescription;
    end;
end;

// OutJob Output Container "Change"
Function PredictOutputFileNames(Parameter : String) : String;
// Parameter == TargetFolder=   TargetFileName=    TargetPrefix=   OpenOutputs=(boolean)   AddToProject=(boolean)
// return is just the filename
var
    ParamList    : TParameterList;
    Param        : TParameter;
    TargetFolder : WideString;
    TargetPrefix : WideString;
    TargetFN     : WideString;

    OJM           : IOutputManager;

begin
//    Param := TParameter;
    ParamList := TParameterList.Create;
    ParamList.ClearAllParameters;
//    TParameterList
    ParamList.SetState_FromString(Parameter, true);
    TargetPrefix := '';
    Param := ParamList.GetState_ParameterByName('TargetPrefix');
    if Assigned(Param) then TargetPrefix := Param.Value;
    TargetFolder := '';
    Param := ParamList.GetState_ParameterByName('TargetFolder');
    if Assigned(Param) then TargetFolder := Param.Value;
    TargetFN := '';
    Param := ParamList.GetState_ParameterByName('TargetFileName');
    if Assigned(Param) then TargetFN := Param.Value;
    Result := TargetFN;

//    OJM := GetWorkspace.DM_OutputManager;
//    OJ  := PCBServer.

    if TargetFN = '' then
    begin
        Result := cDefaultOutputFileName;
//        ParamList.SetState_AddOrReplaceParameter('TargetFileName', cDefaultOutputFileName, true);
    end;
//    Result := ParamList.GetState_ToString;
    ParamList.Destroy;
end;

// OutJob configure button
Function Configure(Parameter : String) : String;
var
    ParamList : TParameterList;
    SourceFileName : WideString;

begin
    ParamList := TParameterList.Create;
    ParamList.ClearAllParameters;
    ParamList.SetState_FromString(Parameter);

// write function to pick form list etc
//    SourceFileName := PickSourceDoc(false);
    SourceFileName := cDefaultInputFileName;

    ParamList.SetState_AddOrReplaceParameter(cSourceFileNameParameter, SourceFileName, true);

    Result := ParamList.GetState_ToString;
    ParamList.Destroy;
end;

// OutJob Generate Output Button
Function Generate(Parameter : String) : String;
// Parameter == TargetFolder=   TargetFileName=    TargetPrefix=  {cSourceFileNameParameter= } OpenOutputs=(boolean)   AddToProject=(boolean)
var
    InputFile      : TextFile;
    OutputFile     : TextFile;
    error          : Integer;
    TargetFD       : WideString;
    TargetPrefix   : WideString;
    TargetFN       : WideString;     // script output file
    OFileNameMulti : WideString;
    SourceFN       : WideString;     // script input file
    SourceFNExt    : WideString;
    SourcePath     : WideString;
    CSV_Path     : WideString;
    POS_Path     : WideString;
    tmpfile      : Widestring;
    tmpstr       : WideString;
    Document     : IDocument;
    ParamList    : TParameterList;
    Param        : IParameter;
    Line         : WideString;
    OutLine      : WideString;
    OpenOutputs  : boolean;
    I, J, K      : integer;
    bFSuccess       : boolean;
    TargetContainer : integer;
    TargetOutputerS : integer;
    TargetOutputerB : integer;
    sDummy          : WideString;
    bUseOPName      : boolean;
    OPP, OPO, OPM   : WideString;
    OPV, OPMV       : WideString;

begin
    Result := 'Success=0';

    Param := TParameter;
    ParamList := TParameterList.Create;
    ParamList.ClearAllParameters;
    ParamList.SetState_FromString(Parameter);

    TargetPrefix := '';
    Param := ParamList.GetState_ParameterByName('TargetPrefix');
    if Assigned(Param) then TargetPrefix := Param.Value;

    TargetFd := '';
    Param := ParamList.GetState_ParameterByName('TargetFolder');
    if Assigned(Param) then TargetFd := Param.Value;
    TargetFN := '';                        // output target name
    Param := ParamList.GetState_ParameterByName('TargetFileName');
    if Assigned(Param) then TargetFN := Param.Value;

    SourceFN := cDefaultInputFileName;
    Param    := ParamList.GetState_ParameterByName(cSourceFileNameParameter);    // input target name from Configure()
    if not Assigned(Param) then
        ParamList.SetState_AddOrReplaceParameter(cSourceFileNameParameter, cDefaultInputFileName, true)
    else
        SourceFN := Param.Value;                                                // in case configure was never run.
    OpenOutputs := false;
    ParamList.GetState_ParameterAsBoolean('OpenOutputs', OpenOutputs);

    ParamList.Destroy;
    Param := nil;

    Rpt := TStringList.Create;

    Prj := GetWorkspace.DM_FocusedProject;
    Doc := GetWorkSpace.DM_FocusedDocument;
    if Doc.DM_DocumentKind <> cDocKind_OutputJob then exit;
 
    if bDebugfile then
    begin
        Rpt.Add(' Generate ');
        Rpt.Add(' Running Script Prj ' + GetRunningScriptProjectName);
        Rpt.Add(' CurrentDocFN    ' + GetCurrentDocumentFileName);
        Rpt.Add(' Server          ' + GetActiveServerName);
        Rpt.Add(' TargetFolder    ' + TargetFd);
        Rpt.Add(' TargetFileName  ' + TargetFN);
        Rpt.Add(' TargetPreFix    ' + TargetPrefix);
        Rpt.Add('');
    end;

    ServerDoc := Client.GetDocumentByPath(Doc.DM_FullPath);
    if (ServerDoc.Modified = -1) then ServerDoc.DoSafeFileSave('OutJob');
    OJDoc := ServerDoc;     // GetWorkspace.DM_GetOutputJobDocumentByPath(Doc.DM_FullPath);

// Parse OutJob file directly for missing information
    ContainerSect :=  ParseTheOutJobFile(ServerDoc, cOJFHeadingPublish);
    ContainerSect.Count;

    if bDebugfile then
        Rpt.Add('OJ Containers & Outputers ');

// find the container with the target script name
    TargetContainer := -1;
    TargetOutputerS := -1;     // first script outputer in container
    TargetOutputerB := -1;     // first BOM outputer in container

    for I := 0 to (OJDoc.OutputMediumCount - 1) do
    begin
        OJContainer := OJDoc.OutputMedium(I);      // IOutputMedium
        for J := 0 to (OJDoc.MediumOutputersCount(OJContainer) - 1) do
        begin
            OutPut := OJDoc.MediumOutputer(OJContainer, J);
            sDummy := ExtractFileName(OutPut.DM_GetDocumentPath);
            if (Output.DM_GeneratorName = 'Script') and (OutPut.DM_GetDescription = 'Script Output') and (sDummy = cScriptName) then
            begin
                TargetContainer := I;
                TargetOutputerS := J;
            end;
        end; // for J
        for J := 0 to (OJDoc.MediumOutputersCount(OJContainer) - 1) do
        begin
            OutPut := OJDoc.MediumOutputer(OJContainer, J);
            sDummy := ExtractFileName(OutPut.DM_GetDocumentPath);
            if (TargetContainer = I) and (Output.DM_GeneratorName = 'BOM') then    // and (OutPut.DM_GetDescription = 'Script Output') then
            begin
                TargetOutputerB := J;
            end;
        end; // for J
    end;     // for I


    VariantS := OJDoc.VariantScope;   // TOutputJobVariantScope;

    if TargetContainer > -1 then
    begin
        OJContainer := OJDoc.OutputMedium(TargetContainer);      // IOutputMedium

        if bDebugfile then                  // Script
            Rpt.Add('Container ' + IntToStr(TargetContainer + 1) + ' ' + OJContainer.Name + ' ' + OJContainer.OutputPath + ' ' + OJContainer.TypeString);

        for I:= 0 to (OJContainer.DM_ParameterCount - 1) do
        begin
            if bDebugfile then
                Rpt.Add(' Parameter .' + IntToStr(I+1) + ' ' + OJContainer.DM_Parameters(I).DM_Name  + ' = ' +  OJContainer.DM_Parameters(I).DM_Value);
        end;
        if OJContainer.DM_ParameterCount < 1 then
            if bDebugfile then
                Rpt.Add(' no OJ container parameters');

        if bDebugfile then
            Rpt.Add('');

// if output file name is set the [Output Name]
        bUseOPName := false;
        if ContainerSect.Values(cOJFUseOutputNameForMulti  + IntToStr(TargetContainer + 1)) = '1' then bUseOPName := true;

        for I := 0 to (OJDoc.MediumOutputersCount(OJContainer) - 1) do
        begin
            OutPut := OJDoc.MediumOutputer(OJContainer, I);

            OutPut.DM_SupportsVariants;
            OutPut.VariantName;
            OutPut.DM_ShortDescriptorString;       // CamView

            if (I = TargetOutputerS) then
                if bDebugfile then Rpt.Add(' Target Outputer Script ');
            if (I = TargetOutputerB) then
                if bDebugfile then Rpt.Add(' Target Outputer BOM ');

            if bDebugfile then        // Output number       'Script BOM Reformat'        'Script'                      'Script Output'
                Rpt.Add(' Outputer .' + IntToStr(I+1) + ' ' + OutPut.DM_ViewName + ' ' + OutPut.DM_GeneratorName + ' ' + OutPut.DM_GetDescription + ' '
   // filename of calling script 'BoM-ReWriter.pas'          'EditScript'                     'CamView'
                    + OutPut.DM_GetDocumentPath + ' ' + OutPut.DM_GetDocumentKind + ' ' +  OutPut.DM_LongDescriptorString);


            OPP := EvaluateFields(OJContainer, Output, ContainerSect.Values(cOJFOutputPathOutputerPrefix  + IntToStr(TargetContainer + 1)) );
            if bDebugfile then  Rpt.Add(' OPP ' + OPP);
            OPV := EvaluateFields(OJContainer, Output, ContainerSect.Values(cOJFOutputPathOutputerValue  + IntToStr(TargetContainer + 1)) );
            if bDebugfile then  Rpt.Add(' OPV ' + OPV);
            OPM := EvaluateFields(OJContainer, Output, ContainerSect.Values(cOJFOutputPathMedia           + IntToStr(TargetContainer + 1)) );
            if bDebugfile then  Rpt.Add(' OPM ' + OPM);
            OPMV := EvaluateFields(OJContainer, Output, ContainerSect.Values(cOJFOutputPathMediaValue     + IntToStr(TargetContainer + 1)) );
            if bDebugfile then  Rpt.Add(' OPMV ' + OPMV);
            OPO := EvaluateFields(OJContainer, Output, ContainerSect.Values(cOJFOutputPathOutputer        + IntToStr(TargetContainer + 1)) );
            if bDebugfile then  Rpt.Add(' OPO ' + OPO);

// some special internal rules around file name = [Output Name]
// Outputs combine to one file if same type & name is hyphenated combination
            if bUseOPName then
            begin
                if I = TargetOutputerB then
                    if (OJDoc.MediumOutputersCount(OJContainer) > 1) then
                        OFileNameMulti := EvaluateFields(OJContainer, Output, '[Output Name]') + '-' + OJDoc.MediumOutputer(OJContainer, TargetOutputerS).DM_GeneratorName;
// somehow AD uses filename 'output'
                if (I = TargetOutputerS) then
                    OFileNameMulti := EvaluateFields(OJContainer, Output, '[Output Name]');
            end
            else
                OFileNameMulti := EvaluateFields(OJContainer, Output, ContainerSect.Values(cOJFOutputFileNameMulti    + IntToStr(TargetContainer + 1)) );

            if OPMV <> '' then sDummy := OPMV + '\';
            if OPM <> '' then sDummy := '_' + OPM + '\';
            if (OPP <> '')  and (OPO = OPM) then sDummy := '\';
        //  if OPV <> '' then sDummy := OPV;
        //  if OPO <> '' then sDummy := OPO;
            if bDebugfile then Rpt.Add(' Fullpath ' + OJContainer.OutputPath + OPO + sDummy);
            if bDebugfile then Rpt.Add(' OFN ' + OFileNameMulti);

            if I = TargetOutputerB then
            begin
                SourceFN := OFileNameMulti;
                SourcePath := OJContainer.OutputPath + OPO + sDummy;
            end;
            if I = TargetOutputerS then
            begin
                TargetFN := OFileNameMulti;
                TargetFd := OJContainer.OutputPath + OPO + sDummy;
            end;

            for J:= 0 to (OutPut.DM_ParameterCount - 1) do
            begin
                if bDebugfile then
                    Rpt.Add(' O' + IntToStr(I+1) + ' Parameter .' + IntToStr(J+1) + ' ' + OutPut.DM_Parameters(J).DM_Name  + ' = ' +  OutPut.DM_Parameters(J).DM_Value);
            end;

            if bDebugfile then
                Rpt.Add('');

        end; // for J
    end;     // if

    if bDebugfile then
        Rpt.SaveToFile('c:\temp\OJ-dump1.txt');

   Rpt.Free;
//   exit;

// if TargetFd contains '.\' then is encoded as resolved relative path.
    IsRelativePath(TargetFd);       // dnw

    TargetFd := UnRelativePath(TargetFd);
    SourcePath := UnRelativePath(SourcePath);

//  the input file (output of other outputer in container.
    CSV_Path := SourcePath + SourceFN;

// 'Path of my new POS file with the right format and extension
    POS_Path := TargetFd + TargetFN + '.txt';

    if Length(TargetFN) < 1 then
    begin
        ShowMessage('Output Filename Bad : ' + TargetFN);
        exit;
    end;

    bFSuccess := true;
    if not DirectoryExists(RemoveSlash(TargetFd, cPathSeparator), false) then
        bFSuccess := CreateDir(RemoveSlash(TargetFD, cPathSeparator) );
//    if bFSuccess and FileExists(POS_Path, false) then
//        bFSuccess := DeleteFile(POS_Path);

try
    if bFSuccess then
    begin
        AssignFile(OutputFile, POS_Path);
//        FileMode := fmOpenReadWrite;
// {$I-}
//        Reset(OutputFile);
        Rewrite(OutputFile);
// {$I+}
    end else
    begin
        ShowMessage('File/path not found : ' + POS_Path);
        exit;
    end;
except
    bFSuccess := false;
//    CloseFile(OutputFile);
    ShowMessage('File output problem, locked? : ' + POS_Path);
    Exit;
end;


    SourceFNExt := '.csv';
    if not FileExists(CSV_Path + SourceFNExt, false) then bFSuccess := false;
    if not bFSuccess then
    begin
        SourceFNExt := '.txt';
        if not FileExists(CSV_Path + SourceFNExt, false) then
        begin
            ShowMessage('File not found : ' + CSV_Path);
            exit;
        end;
    end;

    tmpfile := SpecialFolder_Temporary + IntToStr(DateTimeToFileDate(Date)) + '.tmp';
    CopyFile(CSV_Path + SourceFNExt, tmpfile, false);

    AssignFile(InputFile, tmpfile);            // CSV_Path + SourceFNExt);
    FileMode := fmOpenRead;
{$I-}
    Reset(InputFile);
    error := IOResult;
{$I+}
//    Reset(InputFile);
    if error <> 0 then
    begin
        bFSuccess := false;
        CloseFile(OutputFile);
        CloseFile(InputFile);
        ShowMessage('File input problem, locked? : ' + CSV_Path);
        Exit;
    end;


    while not EOF(InputFile) do
    begin
        Readln(InputFile, Line);
        if not VarIsNull(Line) then
        begin
//   process line changes.
            OutLine := Line;
            for I := 1 to Length(Line) Do
            begin
                if I = 1 then J := 0;
//    check for "delete" chars
                if not (Line[I] = Chr(34)) then
                begin
//    replace chars
                    inc(J);
                    OutLine[J] := Line[I];

                    if Line[I] = ',' then
                    begin
                        OutLine[J] := ';';
                    end;
                end;
            end;  // for I
            SetLength(OutLine, J);

            Writeln(Outputfile, OutLine);
        end else
            Writeln(Outputfile, '');

    end;
	
    CloseFile(InputFile);
    CloseFile(OutputFile);
    if FileExists(tmpfile, false) then
	    DeleteFile(tmpfile);
	
    Result := 'Success=1';

    if OpenOutputs then
    begin
        Document  := Client.OpenDocument('Text', POS_Path);
        If (Document <> Nil) Then
        begin
            Client.ShowDocument(Document);
            if (Document.GetIsShown <> 0 ) then
                Document.DoFileLoad;
        end;
    end;

end;

procedure DumpOutJobReport();
var
    Param        : TParameter;
    PL           : TParameterList;
    bValue       : boolean;
    I, J, K      : integer;
    sDummy         : WideString;
    bUseOPName     : boolean;
    OPP, OPO, OPM  : WideString;
    OPV, OPMV, OFN : WideString;

    OJ             : IOutputJob;

begin
    Rpt   := TStringList.Create;

// required nonsense below
    PL := TParameterList.Create;
    PL.ClearAllParameters;
    PL.SetState_FromString('dumb=dumber');
    Param := PL.GetState_ParameterByName('dumb');
//    Param := TParameter;

    Prj := GetWorkspace.DM_FocusedProject;
    Doc := GetWorkSpace.DM_FocusedDocument;
    Doc.DM_FileName;
    Doc.DM_ParameterCount;

    Prj.DM_ConfigurationCount;
    Prj.DM_Configurations(0);
    PrjConfig := Prj.DM_GetDefaultConfiguration;  // IConfiguration
    Prj.DM_GetDefaultConfigurationName;
    PrjConfig.DM_Name;
    PrjConfig.DM_ParameterCount;
    PrjConfig.DM_ConstraintGroupCount;
    PrjConfig.DM_ConstraintsFileCount;
    PrjConfig.DM_LongDescriptorString;
    PrjConfig.DM_GetTargetDeviceName;

    if Doc.DM_DocumentKind <> cDocKind_OutputJob then exit;

    Rpt.Add('Dump OutJob Report ');
    Rpt.Add(GetRunningScriptProjectName + ' ' + GetCurrentDocumentFileName + ' ' +  GetActiveServerName);

    ServerDoc := Client.GetDocumentByPath(Doc.DM_FullPath);
//    if (ServerDoc.Modified = -1) then ServerDoc.DoSafeFileSave('OutJob');

    OJDoc := ServerDoc;     // GetWorkspace.DM_GetOutputJobDocumentByPath(Doc.DM_FullPath);

//    OPGen := Client.ClientAPI.GetCurrentOutputGenerator;   // IInterface
//    OPGen.GetExplicitTargetFileName;
//    OPgen.GetParameterCount;

// Parse OutJob file directly for missing information
    ContainerSect :=  ParseTheOutJobFile(ServerDoc, cOJFHeadingPublish);
    ContainerSect.Count;

    Rpt.Add('OJ Outputers ');

    for I := 0 to (OJDoc.OutputerCount - 1) do
    begin
        OutPut := OJDoc.Outputer(I);

//        POutput := Prj.DM_Outputers(OutPut.DM_ViewName);
//        POutput.DM_ViewName ;

                                                 // Output name                 'Script'                    'Script Output'
        Rpt.Add('Outputer ' + IntToStr(I+1) + ' ' + OutPut.DM_ViewName + ' ' + OutPut.DM_GeneratorName + ' ' + OutPut.DM_GetDescription + ' '
                  // full filepath to running script                                         CamView
                + OutPut.DM_GetDocumentPath + ' ' + OutPut.DM_GetDocumentKind + ' ' +  OutPut.DM_LongDescriptorString);

        Output.DM_CurrentSheetInstanceNumber;
        Output.DM_GeneralField;
        OutPut.DM_OwnerDocumentName;
        OutPut.DM_ShortDescriptorString;       // CamView

//    IOutputJob.DM_JobName  ;

        GetCapabilityForOutputGenerator(OutPut.DM_GeneratorName);

        for J:= 0 to (OutPut.DM_ParameterCount - 1) do
        begin
            Rpt.Add('O' + IntToStr(I+1) + ' Parameter .' + IntToStr(J+1) + ' ' + OutPut.DM_Parameters(J).DM_Name  + ' = ' +  OutPut.DM_Parameters(J).DM_Value);
        end;
        Rpt.Add('');
    end;

    Rpt.Add('OJ Containers ');

    for I := 0 to (OJDoc.OutputMediumCount - 1) do
    begin
        OJContainer := OJDoc.OutputMedium(I);      // IOutputMedium

        OJContainer.DM_OwnerDocumentName;
        OJContainer.DM_CurrentSheetInstanceNumber;
        OJContainer.DM_GeneralField;
        OJContainer.DM_SheetIndex_Physical;
        OJContainer.DM_SheetIndex_Logical;

//        OPSettings.TargetFolder;
//        OPSettings.UnitName;
        Param.Name := cOJFOutputFilePath;
//        OJContainer.DM_CalculateParameterValue(Param);

        OJContainer.DM_GeneralField;
        VariantS := OJDoc.VariantScope;   // TOutputJobVariantScope;

// this seems to make stuff                                   // TOutPutCategory
//                   eOutput_Documentation     eOutput_Report        eOutput_Fabrication
//        PreDefinedOP := OutputMan.DM_GetPredefinedOutputForCategory(eOutput_Report, 1)   ;  // IPredefinedOutput
// OutPutMan.DM_GetPredefinedOutputForCategory(TOutputCategory, Index :intger) : IPredefinedOutput
//        IPredefinedOutput.DM_SetName;

        Rpt.Add('Container ' + IntToStr(I + 1) + ' ' + OJContainer.Name + ' ' + OJContainer.OutputPath + ' ' + OJContainer.TypeString);

        if (OJDoc.MediumOutputersCount(OJContainer) > 0) then
        begin
            Rpt.Add(' [' + cOJFHeadingPublish + ']' );
            Rpt.Add(' Release managed     ' + ContainerSect.Values(cOJFReleaseManaged    + IntToStr(I + 1)) );             // =0 or =1
            Rpt.Add(' OBasePath           ' + ContainerSect.Values(cOJFOutputBasePath   + IntToStr(I + 1)) );
            Rpt.Add(' OFilePath           ' + ContainerSect.Values(cOJFOutputFilePath   + IntToStr(I + 1)) );
            Rpt.Add(' OPathMedia          ' + ContainerSect.Values(cOJFOutputPathMedia  + IntToStr(I + 1)) );
            Rpt.Add(' OPathMediaValue     ' + ContainerSect.Values(cOJFOutputPathMediaValue     + IntToStr(I + 1)) );
            Rpt.Add(' OPathOutputer       ' + ContainerSect.Values(cOJFOutputPathOutputer       + IntToStr(I + 1)) );
            Rpt.Add(' OPathOutputerPrefix ' + ContainerSect.Values(cOJFOutputPathOutputerPrefix + IntToStr(I + 1)) );
            Rpt.Add(' OPathOutputerValue  ' + ContainerSect.Values(cOJFOutputPathOutputerValue  + IntToStr(I + 1)) );
            Rpt.Add(' OFileName           ' + ContainerSect.Values(cOJFOutputFileName           + IntToStr(I + 1)) );
            Rpt.Add(' OFileNameMulti        ' + ContainerSect.Values(cOJFOutputFileNameMulti    + IntToStr(I + 1)) );
            Rpt.Add(' UseOutputNameForMulti ' + ContainerSect.Values(cOJFUseOutputNameForMulti  + IntToStr(I + 1)) );
            Rpt.Add(' OFileNameSpecial      ' + ContainerSect.Values(cOJFOutputFileNameSpecial  + IntToStr(I + 1)) );
        end;

// if output file name is set the [Output Name]
        bUseOPName := false;
        if ContainerSect.Values(cOJFUseOutputNameForMulti  + IntToStr(I + 1)) = '1' then bUseOPName := true;

        for J := 0 to (OJDoc.MediumOutputersCount(OJContainer) - 1) do
        begin
            OutPut := OJDoc.MediumOutputer(OJContainer, J);

            OutPut.DM_SharedConfiguration;
            OutPut.DM_IsInferredObject;
            OutPut.DM_SupportsVariants;
            OutPut.VariantName;

            Rpt.Add('C' + IntToStr(I+1) + ' Outputer .' + IntToStr(J+1) + ' ' + OutPut.DM_ViewName + ' ' + OutPut.DM_GeneratorName + ' ' + OutPut.DM_GetDescription + ' '
                    // full filepath to running script
                    + OutPut.DM_GetDocumentPath + ' ' + OutPut.DM_GetDocumentKind + ' ' +  OutPut.DM_LongDescriptorString);

            OPP := EvaluateFields(OJContainer, Output, ContainerSect.Values(cOJFOutputPathOutputerPrefix  + IntToStr(I + 1)) );
            if bDebugfile then  Rpt.Add(' OPP ' + OPP);
            OPV := EvaluateFields(OJContainer, Output, ContainerSect.Values(cOJFOutputPathOutputerValue  + IntToStr(I + 1)) );
            if bDebugfile then  Rpt.Add(' OPV ' + OPV);
            OPM := EvaluateFields(OJContainer, Output, ContainerSect.Values(cOJFOutputPathMedia           + IntToStr(I + 1)) );
            if bDebugfile then  Rpt.Add(' OPM ' + OPM);
            OPMV := EvaluateFields(OJContainer, Output, ContainerSect.Values(cOJFOutputPathMediaValue     + IntToStr(I + 1)) );
            if bDebugfile then  Rpt.Add(' OPMV ' + OPMV);
            OPO := EvaluateFields(OJContainer, Output, ContainerSect.Values(cOJFOutputPathOutputer        + IntToStr(I + 1)) );
            if bDebugfile then  Rpt.Add(' OPO ' + OPO);


// some special internal rules around file name = [Output Name]
            if bUseOPName then
                OFN := EvaluateFields(OJContainer, Output, '[Output Name]')
            else
                OFN := EvaluateFields(OJContainer, Output, ContainerSect.Values(cOJFOutputFileNameMulti    + IntToStr(I + 1)) );
            Rpt.Add(' OFN ' + OFN);

        end;
        if (OJDoc.MediumOutputersCount(OJContainer) < 1) then
            Rpt.Add(' container has NO Outputers ');

        for J:= 0 to (OJContainer.DM_ParameterCount - 1) do
        begin
            Rpt.Add('C' + IntToStr(I+1) + ' Parameter .' + IntToStr(J+1) + ' ' + OJContainer.DM_Parameters(J).DM_Name  + ' = ' +  OJContainer.DM_Parameters(J).DM_Value);
        end;
        if OJContainer.DM_ParameterCount < 1 then
            Rpt.Add(' no OJ Container parameters');

        Rpt.Add('');
    end;

//    GetCapabilityForOutputGenerator('Ex2 Bom Converter');

    Rpt.SaveToFile('c:\temp\OJ-dump2.txt');
    Rpt.Free;
end;


// Allow testing via direct call
procedure Generate_DirectCall;
// Parameter == TargetFolder=   TargetFileName=    TargetPrefix=   OpenOutputs=(boolean)   AddToProject=(boolean)
var
    TargetFD : WideString;
    TargetFN : WideString;
    OutputFN : WideString;

begin
    TargetFD := GetWorkSpace.DM_WorkspaceFullPath;

    Prj := GetWorkspace.DM_FocusedProject;
    if Prj <> nil then
        TargetFD := GetWorkspace.DM_FocusedProject.DM_ProjectFullPath;
//    else
//        TargetFD := GetWorkSpace.DM_FocusedDocument.DM_FullPath;

    TargetFD := ExtractFilePath(TargetFD);
    TargetFN := 'input.txt';               //  cDefaultInputFileName
    OutputFN := 'direct-call-output.txt';  // generate makes its own output name.
//  pass a spoofed parameterlist
    Generate('TargetFolder=' + TargetFD + ' | TargetFilename=' + OutputFN + ' | ' + cSourceFileNameParameter + '=' + TargetFN + ' | OpenOutputs=true');
end;

