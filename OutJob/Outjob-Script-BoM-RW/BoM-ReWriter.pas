{  B0M-ReWriter.pas

BL Miller
14/03/2020  v0.10 POC example.
15/03/2020  v0.11 File exists tested the wrong (outfile) file & check/create new paths
18/03/2020  v0.12 Fix bug in generate (no source file parameter) if configure had never been run
                  Attempt support for relative path in Change.

use in OutJob container as part of project
script must be part of the board project
Can be called directly or via Outjob interface.

Outfile is setup by "Change" button
Infile could be setup from "Configure" (pop up a form)
Infile is using the SAME path as the outputfile. This WILL FAIL when a new output path is defined!!

Direct call test method enables "open outputs".
}

const
    cSourceFileNameParameter = 'SourceFileName';         // Parameter Name to store static data from Configure into OutJob.
    cDefaultInputFileName  = 'input.txt';                // default until you write function to pick/set another.
    cDefaultOutputFileName = 'output.txt';               // default until hit change & setup diff filename.

// OutJob Output Container "Change"
Function PredictOutputFileNames(Parameter : String) : String;
var
    ParamList    : TParameterList;
    Param        : IParameter;
    bValue       : boolean;
    TargetFolder : WideString;
    TargetFN     : WideString;

begin
    // Parameter == TargetFolder=   TargetFileName=    TargetPrefix=   OpenOutputs=(boolean)   AddToProject=(boolean)
    ParamList := TParameterList.Create;
    ParamList.ClearAllParameters;
    ParamList.SetState_FromString(Parameter);
    Param := ParamList.GetState_ParameterByName('TargetFolder');
    TargetFolder := Param.Value;
    Param := ParamList.GetState_ParameterByName('TargetFileName');
    TargetFN := Param.Value;
    ParamList.Destroy;

    if TargetFN = '' then TargetFN := cDefaultOutputFileName;
    Result := TargetFN;
end;

// OutJob configure button
Function Configure(Parameter : String) : String;
var
    ParamList : TParameterList;
    SourceFileName : WideString;

begin
    ParamList := TParameterList.Create;
    ParamList.ClearAllParameters;
//    ParamList.SetState_FromString(Parameter);

    SourceFileName := cDefaultInputFileName;

// write function to pick form list etc
//    SourceFileName := PickSourceDoc(false);
    ParamList.SetState_AddOrReplaceParameter(cSourceFileNameParameter, SourceFileName, true);

    Result := ParamList.GetState_ToString;
    ParamList.Destroy;
end;

// OutJob Generate Output Button
Function Generate(Parameter : String) : String;
// Parameter == TargetFolder=   TargetFileName=    TargetPrefix=   OpenOutputs=(boolean)   AddToProject=(boolean)
var
    InputFile  : TextFile;
    OutputFile : TextFile;
    TargetFD   : WideString;
    TargetFN   : WideString;
    SourceFN   : WideString;
    CSV_Path   : WideString;
    POS_Path   : WideString;
    tmpstr     : WideString;
    Document   : IDocument;
    ParamList   : TParameterList;
    Param       : IParameter;
    Line        : WideString;
    OutLine     : WideString;
    OpenOutputs : boolean;
    I, J        : integer;
    bFSuccess   : boolean;

begin
    Param := TParameter;
    ParamList := TParameterList.Create;
    ParamList.ClearAllParameters;
    ParamList.SetState_FromString(Parameter);

    Param := ParamList.GetState_ParameterByName('TargetFolder');
    TargetFd := Param.Value;

    Param := ParamList.GetState_ParameterByName('TargetFileName');     // output target name
    TargetFN := Param.Value;

    Param := ParamList.GetState_ParameterByName('TargetPrefix');
//    TargetPrefix := Param.Value;

    SourceFN := cDefaultInputFileName;
    Param    := ParamList.GetState_ParameterByName(cSourceFileNameParameter);    // input target name from Configure()
    if Param = nil then
        ParamList.SetState_AddOrReplaceParameter(cSourceFileNameParameter, cDefaultInputFileName, true)
    else
        SourceFN := Param.Value;                                                // in case configure was never run.

    OpenOutputs := false;
    ParamList.GetState_ParameterAsBoolean('OpenOutputs', OpenOutputs);

    ParamList.Destroy;
    Param := nil;

// if TargetFd contains '.\' then is encoded as resolved relative path.
    tmpstr := TargetFd;
    I := ansipos('.\', TargetFd);
    if I > 5 then
    begin
        SetLength(tmpstr, I - 1);
        Delete(TargetFd, 1, I + 1);
        tmpstr := tmpstr + TargetFd;
        TargetFd := tmpstr;
    end;
// very bad idea to link the input file to the same path as output (dynamic)
// better to make this a project path.
    CSV_Path := TargetFd + SourceFN;

// 'Path of my new POS file with the right format and extension
    POS_Path := TargetFd + TargetFN;

    bFSuccess := true;
    if not DirectoryExists(RemoveSlash(TargetFd, '\'), false) then
        bFSuccess := CreateDir(RemoveSlash(TargetFD, '\') );

    if bFSuccess then
    begin
        AssignFile(OutputFile, POS_Path);
        Rewrite(OutputFile);
    end else
    begin
        ShowMessage('File/path not found : ' + TargetFD);
        exit;
    end;
    if not FileExists(CSV_Path, false) then
    begin
        ShowMessage('File not found : ' + CSV_Path);
        exit;
    end;
    AssignFile(InputFile, CSV_Path);
    Reset(InputFile);

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

    Result := 'done';

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

// Allow testing via direct call
procedure Generate_DirectCall;
// Parameter == TargetFolder=   TargetFileName=    TargetPrefix=   OpenOutputs=(boolean)   AddToProject=(boolean)
var
    TargetFD : WideString;
    TargetFN : WideString;
    OutputFN : WideString;
    Prj      : IBoardProject;

begin
    TargetFD := GetWorkSpace.DM_WorkspaceFullPath;

    Prj := GetWorkspace.DM_FocusedProject;
    if Prj <> nil then
        TargetFD := GetWorkspace.DM_FocusedProject.DM_ProjectFullPath;
//    else
//        TargetFD := GetWorkSpace.DM_FocusedDocument.DM_FullPath;

    TargetFD := ExtractFilePath(TargetFD);
    TargetFN := 'input.txt';             //  cDefaultInputFileName
    OutputFN := 'direct-call-output.txt';
//  pass a spoofed parameterlist
    Generate('TargetFolder=' + TargetFD + ' | TargetFilename=' + OutputFN + ' | ' + cSourceFileNameParameter + '=' + TargetFN + ' | OpenOutputs=true');
end;
