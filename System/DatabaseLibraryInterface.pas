{ DatabaseLibraryInterface.pas
    operates on the fullpath to DbLib document.

05/08/2019  v0.1   POC
07/11/2020  v0.11  bit of a clean up..
14/11/2020  v0.12  Improve parameter reporting; split out system & user parameters.

  IDBSession;
  IDBScreen.Cursor;
  IDBApplication.Title;
  IDataBaseLibCommands;
  ILibModule

}
const
    MyDbLibFullPath = 'P:\DB-Libraries\Database_Libs1.DbLib';
    TargetCompNames = '0R030_OAR-1_1%_1W | 0R_0402_5%_1/16W';           // 2 known primary keys

// system parameter root.
    ParaModelType   = 'ModelType';
    ParaModelName   = 'ModelName';
    ParameterRoot   = 'Parameter';
    ParaCompName    = 'Name';
    ParaCompValue   = 'Value';
    ParaCompVisible = 'Visible';

function SetUpStringLists(const Parameters : WideString, const Tuples : boolean) : TStringList; forward;

procedure FindCompDetails;
var
    WS              : IWorkSpace;
    Prj             : IProject;
    IntLibMan       : IIntegratedLibraryManager;
    DBLib           : IDatabaseLibDocument;
    Doc             : IDocument;
    Filepath        : WideString;
    TableName       : WideString;
    TableEnabld     : boolean;
    LibRefFieldName : WideString;
    LibPathField    : WideString;
    LibSearchPath   : WideString;
    SearchSubDir    : boolean;
    TableIndex      : Integer;
    TableCount      : Integer;
    AOrcadLibrary   : boolean;
    AParameterName  : boolean;
    FieldName       : WideString;
    FieldCount      : integer;
    KeyFCount       : Integer;
    T, I, J, K      : Integer;
    SchLibPath      : WideString;
    SchLibRef       : WideString;
    CompCount       : integer;
    CompName        : WideString;
    Parameters      : WideString;
    ParaList        : TStringList;
    CompParameters  : TStringList;
    CompSysParas    : TStringList;
    ParaName        : WideString;
    ParaVal         : WideString;
    ParaVis         : WideString;
    MaxModelCount   : integer;
    ModelCount      : integer;
    ModelName       : WideString;
    ModelType       : WideString;
    DatafilePath    : WideString;

    ReportDocument  : IServerDocument;
    Report          : TStringlist;
    ItemCount       : integer;
    AResults        : TStrings;
    AResultList     : TStringList;
    Command         : WideString;
    AnError         : WideString;
    QueryRet        : WideString;

    ModelPathName : WideString;
    ModelRefName  : WideString;

begin
    WS := GetWorkSpace;
    IntLibMan := IntegratedLibraryManager;
    if IntLibMan = Nil then Exit;

    Doc := WS.DM_FocusedDocument;
    if Doc.DM_DocumentKind = cDocKind_DatabaseLib then   // 'DATABASELIB'
        DBLib := IntLibMan.GetAvailableDBLibDocAtPath(Doc.DM_FullPath)
    else
        DBLib := IntLibMan.GetAvailableDBLibDocAtPath(MyDbLibFullPath);

    GetRunningScriptProjectName;

    TableCount    := DBLib.GetTableCount;
    LibSearchPath := DBLib.GetLibrarySearchPath;
    SearchSubDir  := DBLib.GetSearchSubDirectories;

    Report := TStringList.Create;
    Report.Add(DBLib.GetFilename + '       table count : ' + IntToStr(TableCount));
    Report.Add(DBLib.GetConnectionString);
    Report.Add('');
    Report.Add('Search path : ' + LibSearchPath + ' sub dir? ' + BoolToStr(SearchSubDir, true) );
    Report.Add('');
    Report.Add('Tables (' + IntToStr(TableCount) + ')' );
    for T := 0 to (TableCount - 1) do
    begin
        TableName   := DBLib.GetTableNameAt(T);
        TableEnabld := DBLib.TableEnabled(T);
        FieldCount  := DBLib.GetFieldCount(I);
        Report.Add(PadRight(IntToStr(T+1),3) + ' Table Name : ' + PadRight(TableName, 20) + '  Enab : ' + BoolToStr(TableEnabld, true) + '  FieldCount ' + IntToStr(FieldCount));
    end;
    
    Command := 'Count(*)';  AnError := '  ';
    ItemCount := DBLib.GetItemCount(Command, AnError);

    Report.Add('');
    for T := 0 to (TableCount - 1) do
    begin
        TableName   := DBLib.GetTableNameAt(T);
        TableEnabld := DBLib.TableEnabled(T);
        FieldCount  := DBLib.GetFieldCount(I);
        KeyFCount   := DBLib.GetKeyFieldCount(T);
        TableIndex  := DBLib.GetTableIndex(TableName);

        AOrcadLibrary := false;
        LibRefFieldName := DBLib.GetLibraryRefFieldName(T, AOrcadLibrary);
        LibPathField    := DBLib.GetLibraryPathFieldName(T);

        Report.Add(IntToStr(T+1) + ' Table : ' + Tablename + '  Enab : ' + BoolToStr(TableEnabld, true) +
                   '  KeyFieldCount : ' + IntToStr(KeyFCount) + '  FieldCount ' + IntToStr(FieldCount) );
        Report.Add('  LibRefField : ' + LibRefFieldName + '  LibPathField : ' + LibPathField );

        for J := 1 to (KeyFCount) do   // Key Field 1 based index.
        begin
            AParameterName := true;
            FieldName := DBLib.GetKeyField(AParameterName, T, J);
            Report.Add(IntToStr(J) + ' KeyFieldName : ' + FieldName);
        end;

        Report.Add('SQL ');
        Command := DBLib.GetCommandString(T, '', 'Where [Pin Count] = 2');
        Command := DBLib.GetCommandString(T, FieldName, 'Where [Pin Count] = 2');
        DBLib.IsValidSQLStatementForTable (TableName, Command);
        ParaName := DBLib.ValidateSQLQuery(Command);
        Report.Add(Command + ' : ' + ParaName);

        DBLib.IsValidSQLStatementForTable (TableName, 'Select * from [' + TableName + '] Where [Pin Count] = 2');
        DBLib.IsValidSQLStatementForTable (TableName, 'Select [*] from [' + TableName + '] Count(*)');   //boolean
        ParaName := DBLib.ValidateSQLQuery ('Select [Part Number] from [' + TableName + '] Count(*)');                         // widestring

        Report.Add('Test ParameterIsKey :');
        ParaName := 'Library Ref';
        Report.Add('  Parameter Key ? : ' + ParaName + '  ' + BoolToStr(DBLib.IsParameterDatabaseKey(T, ParaName)) );
        ParaName := 'DesignItemId';
        Report.Add('  Parameter Key ? : ' + ParaName + '  ' + BoolToStr(DBLib.IsParameterDatabaseKey(T, ParaName)) );
        ParaName := 'Part Number';
        Report.Add('  Parameter Key ? : ' + ParaName + '  ' + BoolToStr(DBLib.IsParameterDatabaseKey(T, ParaName)) );

        Report.Add('');
        Report.Add('Fields (' + IntToStr(FieldCount) + ')');
        for J := 0 to (FieldCount - 1) do
        begin
            FieldName := DBLib.GetFieldNameAt    (T, J);
            ParaName  := DBLib.GetParameterNameAt(T, J);
            Report.Add(PadRight(IntToStr(J + 1), 3) + ' FieldName : ' + PadRight(FieldName, 30) + '  ParaName : ' + ParaName);
        end;

        MaxModelCount := 0;
        for J := 1 to 10 do
        begin
           // multiple models possible for each component.
            ModelPathName := ''; ModelRefName := '';
            DbLib.GetModelFieldNamesAt(J, T, 'PCBLIB', ModelPathName, ModelRefName, false);
            if ModelRefName <> '' then
            begin
                MaxModelCount := J;
                Report.Add(PadRight(IntToStr(J), 3) + ' Model : ' + Padright(ModelRefName, 30) + '  Path : ' + ModelPathName);
            end;
        end;

// count of rows ??
        Command   := DBLib.GetCommandString(T, ' ', ' ');
        CompCount := DBLib.GetItemCount(Command, AnError);
        QueryRet  := DBLib.ValidateSQLQuery(Command);

        Report.Add('Cmd: ' + Command + '   GetItemCount(Cmd)= ' + IntToStr(CompCount));

// load the primary keys from constant string.
        AResultList := SetUpStringLists(TargetCompNames, false);

//        AResultList.SetCapacity(CompCount + 1);
//        AResults.Strings(1);
//   crashy method
//   none work .GetAllComponentKeys(TI, TString) broken.
//        DBLib.GetAllComponentKeys(T, AResultList);
//        DBLib.LoadAllRecordsLimit;

        Report.Add('');
        Report.Add('Components (' + IntToStr(AResultList.Count) +')');
        for J := 0 to (AResultList.Count - 1) do
        begin
//  primary key
            CompName := AResultList.Strings(J);
            CompName := Trim(CompName);                // in case the const has spaces on any end.

            Command := DBLib.GetCommandString(T, ' ', 'Where ROW()=' + IntToStr(J));
            QueryRet := DBLib.ValidateSQLQuery(Command);

            Parameters := DBLib.GetParametersForComponent(T, CompName);
            SchLibPath := DBLib.GetSchLibPathForComponent(T, CompName);
            SchLibRef  := DBLib.GetSchLibRefForComponent (T, CompName);
            Report.Add(PadRight(IntToStr(J+1), 3) + ' Comp : ' + Padright(CompName, 30) + + ' SymRef : ' +SchLibRef + '  SchLib : ' + SchLibPath);

            ParaList       := SetUpStringLists(Parameters, true);
            CompParameters := SetUpStringLists('', true);
            CompSysParas   := SetUpStringLists('', true);

            Report.Add('Parameters (' + IntToStr(ParaList.Count)+')');
            for K := 0 to (ParaList.Count - 1) do
            begin
                ParaName := ParaList.Names(K);
                ParaVal  := ParaList.ValueFromIndex(K);
                if ansipos(ParameterRoot, ParaName) = 1 then
                    CompParameters.Add(ParaName + '=' + ParaVal)
                else
                    CompSysParas.Add(ParaName + '=' + ParaVal);
            end;
            ParaList.Clear;

            for K := 0 to (CompSysParas.Count - 1) do
            begin
                ParaName := CompSysParas.Names(K);
                ParaVal  := CompSysParas.ValueFromIndex(K);
                if ParaVal = '' then ParaVal := '<blank>';
                Report.Add('S' + PadRight(IntToStr(K+1), 3) + Padright(ParaName, 30) + ' = ' + ParaVal);
            end;

            for K := 0 to (CompParameters.Count / 3 - 1) do      // 3 entries per parameter
            begin
                I := CompParameters.IndexOfName(ParameterRoot + ParaCompName + trim(IntToStr(K)));
                ParaName  := CompParameters.ValueFromIndex(I);
                if ParaName <> '' then
                begin
                    I := CompParameters.IndexOfName(ParameterRoot + ParaCompValue + trim(IntToStr(K)));
                    ParaVal := CompParameters.ValueFromIndex(I);
                    if ParaVal = '' then ParaVal := '<blank>';
                    I := CompParameters.IndexOfName(ParameterRoot + ParaCompVisible + trim(IntToStr(K)));
                    ParaVis := CompParameters.ValueFromIndex(I);
                    Report.Add('U' + PadRight(IntToStr(K+1), 3) + Padright(ParaName, 30) + ' = ' + PadRight(ParaVal, 40) + '  visible : ' + ParaVis);
                end;
            end;
            CompParameters.Clear;

            Report.Add('  FP Model ');
            for K := 0 to (MaxModelCount - 1) do
            begin
                ParaName := ParaModelName + IntToStr(K);
                I := CompSysParas.IndexOfName(ParaName);
                if I > -1 then
                begin
                    ModelType := CompSysParas.ValueFromIndex( CompSysParas.IndexOfName( ParaModelType + IntToStr(K)) );
                    ModelName := CompSysParas.ValueFromIndex(I);
//                                                                   cDocKind_PcbLib
                    DatafilePath := DBLib.GetDatafilePath(ModelName, ModelType, TableName, CompName);
                    Report.Add(PadRight(' M' + IntToStr(K+1), 3) + ' Model : ' + PadRight(ModelName, 30) + ' ' + PadRight(ModelType, 10) + DatafilePath);
                end;
            end;
            Report.Add('');
            CompSysParas.Clear;
        end;
        Report.Add('');
        AResultList.Free;
    end;

    ParaList.Free;
    FilePath := ExtractFilePath(Doc.DM_FullPath);
    FilePath := FilePath + ExtractFileName(Doc.DM_FileName) + '_DBLibFields.Txt';
    Report.SaveToFile(FilePath);

    EndHourGlass;

    ReportDocument := Client.OpenDocument('Text', FilePath);
    If ReportDocument <> Nil Then
    begin
        Client.ShowDocument(ReportDocument);
        if (ReportDocument.GetIsShown <> 0 ) then
            ReportDocument.DoFileLoad;
    end;
end;

function SetUpStringLists(const Parameters : WideString, const Tuples : boolean) : TStringList;
begin
    Result := TStringList.Create;
    Result.Delimiter := '|';
    Result.StrictDelimiter := true;
    if (Tuples) then Result.NameValueSeparator := '=';
    Result.DelimitedText := Parameters;
end;

