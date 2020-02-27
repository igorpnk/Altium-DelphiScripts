{.............................................................................
SchDoc ChangeCompLibrary.pas
  Replaces component & model DB library name(s)for name matches..
  Can change DB Table name as well.

 ** Warning **
this script does not perform smart comp location & lib updating.

Author BL Miller
from CompRenameSch.pas Ver 1.2 & ExplicitModelSourceInLibs.pas

20/02/2020  0.10 POC     not finished..
26/02/2020  0.20 Seems to work on Comp symbol & FP models
27/02/2020  0.21 Store full vfs DBLib/Table into ModelDatafile.Location (.UseCompLib=true overrides anyway!)
27/02/2020  0.22 better ModelDataFile.ModelType test


DBLib:
    Component is defined in the table.
    .DesignItemId is unique component identifier
    .LibReference links to the (shared) symbol entry in a SchLib
    .SourceLibraryName is symbol SchLib.

SchLib/IntLib:
    Component is defined in SchLib "symbol" with paras & SchImpl links (models)
    .DesignItemId is not used?  (I set same as LibRef)
    .LibReference is unique symbol name

So .LibReference always points to a symbol in SchLib.

                                           when from DBLib:                                       when from IntLib:
    Component.DesignItemId;                same as existing / last part..
    Component.LibReference;                'RES_BlueRect_2Pin'         symbol                     '0R05_0805_5%_1/4W'
    Component.LibraryIdentifier;           'Database_Libs1.DBLib/STD_Resistor'                    'STD_Resistor.IntLib'
    Component.SourceLibraryName;           'Database_Libs1.DBLib'                                 'STD_Resistor.IntLib'
    Component.SymbolReference;             same as LibRef                                         same as LibRef
}

{..............................................................................}
Var
    ReportInfo         : TStringList;
    CurrentSheet       : ISch_Document;
    Component          : ISch_Component;
    Iterator           : ISch_Iterator;
    ImplIterator       : ISch_Iterator;
    SchImplementation  : ISch_Implementation;

    CompName           : WideString;
    CompDesignId       : WideString;
    CompLibRef         : WideString;
    CompLibID          : WideString;

{..............................................................................}
Procedure GenerateReport(Report : TStringList);
Var
    WS       : IWorkspace;
    Prj      : IProject;
    Filepath : WideString;
    Filename : WideString;
    ReportDocument : IServerDocument;

Begin
    WS  := GetWorkspace;
    Filename := 'none';

    If WS <> Nil Then
    begin
        Filepath := ExtractFilePath(SchServer.GetCurrentSchDocument.DocumentName);
        Prj := WS.DM_FocusedProject;
        If Prj <> Nil Then
        begin
            Filename := ExtractFilename(Prj.DM_ProjectFullPath);
            Filepath := ExtractFilePath(Prj.DM_ProjectFullPath);
        end;
    end;
             
    If length(Filepath) < 5 then Filepath := 'c:\temp\';

    Report.Insert(0, 'Script: ChangeCompLibrary.pas ');
    Report.Insert(1, 'SchDoc Component DB Lib rename report...');
    Report.Insert(2, '========================================================');
    Report.Insert(3, 'Project : ' + Filename);

    Filename := ExtractFilename(SchServer.GetCurrentSchDocument.DocumentName);

    Report.Insert(4, 'SchDoc  : ' + Filename);
    Report.Insert(5, ' ');

    Filepath := Filepath + Filename + '-CompDBLibReport.Txt';
    Report.SaveToFile(Filepath);

    ReportDocument := Client.OpenDocument('Text', Filepath);
    If ReportDocument <> Nil Then
    begin
        Client.ShowDocument(ReportDocument);
        if (ReportDocument.GetIsShown <> 0 ) then
            ReportDocument.DoFileLoad;
    end;
end;
{..............................................................................}

{..............................................................................}
Procedure ChangeLibraryNames;
Var
    i                  : integer;

    ModelDataFile      : ISch_ModelDatafileLink;
  
    ExCompLib          : WideString;
    ExDBTable          : WideString;
    NewCompLib         : WideString;
    NewDBTable         : WideString;
    NewLibPath         : WideString;

    ModelLibPath       : WideString;
    ModelLibName       : WideString;

    CompSymRef         : WideString;
    CompSrcLibName     : WideString;
    CompDBTable        : WideString;

Begin
    If SchServer = Nil Then Exit;
    CurrentSheet := SchServer.GetCurrentSchDocument;

    // check if the document is a schematic Doc and if not
    // exit.
    If (CurrentSheet = Nil) or (CurrentSheet.ObjectID <> eSheet) Then
    Begin
         ShowError('Please open a schematic SchDoc.');
         Exit;
    End;

//  DB library names for comp & models.
    ExCompLib  := 'Database_Libs1.DbLib';        // Existing DbLib
    NewCompLib := 'dummy_Libs1.DbLib';           // New target DbLib fullname

//    ExCompLib   := 'dummy_Libs1.DbLib';
//    NewCompLib  := 'Database_Libs1.DbLib';

// DB Table names
    ExDBTable   := 'dummy-resistor';            // has to match existing to make change
    NewDBTable  := 'STD_Resistor';              // DB table name

//    ExDBTable   := 'STD_Resistor';
//    NewDBTable  := 'dummy-resistor';

    // Create a TStringList object to store data
    ReportInfo := TStringList.Create;
    ReportInfo.Add('Existing Library : ' + ExCompLib +      '   ExistingDb Table : ' + ExDBTable );
    ReportInfo.Add('New Library      : ' + NewCompLib +     '   NewDb Table : ' + NewDBTable );
    ReportInfo.Add('');

    // get the library object for the library iterator.
    If CurrentSheet.ObjectID = eSchLib Then
        Iterator := CurrentSheet.SchLibIterator_Create
    Else
        Iterator := CurrentSheet.SchIterator_Create;

    Iterator.AddFilter_ObjectSet(MkSet(eSchComponent));

    Try
        Component := Iterator.FirstSchObject;
        While Component <> Nil Do
        Begin
            CompDesignId   := Component.DesignItemId;
            CompLibRef     := Component.LibReference;
            CompLibID      := Component.LibraryIdentifier;
            CompSrcLibName := Component.SourceLibraryName;
            CompSymRef     := Component.SymbolReference;
            CompDBTable    := Component.DatabaseTableName;

            ReportInfo.Add(Component.Designator.Text + ' DesignId : ' + CompDesignId + '  LibRef : ' + CompLibRef + '  LibId : ' + CompLibId
                                                     + ' SLN : ' + CompSrcLibName + ' SymRef : ' + CompSymRef);
                //     LibraryPath;
            If (Length(CompSrcLibName) = 0) or (CompSrcLibName = '*') Then
                CompSrcLibName := 'no specific lib';

            if (ExCompLib = CompSrcLibName) then
            begin
                Component.SetState_SourceLibraryName(NewCompLib);
                //Component.SetState_DatabaseLibraryName(NewLibID);
                ReportInfo.Add(Component.Designator.Text + '   ' + CompName + Component.LibReference + '  ExCompLib : ' + CompSrcLibName + '  NewLib: ' + NewCompLib);
            end;
            if (ExDBTable = CompDBTable) then
            begin
                // Component.UseDBTableName := False;
                Component.SetState_DatabaseTableName(NewDBTable);
                Component.UseDBTableName := True;
                ReportInfo.Add(Component.Designator.Text + '   ' + CompName + Component.LibReference + '  ExDBTable : ' + ExDBTable + '  NewDBTable : ' + NewDBTable);
                ReportInfo.Add('');
            end;

// if changed then reuse for models.
            CompDBTable    := Component.DatabaseTableName;

            SchServer.RobotManager.SendMessage(Component.I_ObjectAddress, c_BroadCast, SCHM_BeginModify, c_NoEventData);

            ImplIterator := Component.SchIterator_Create;
            ImplIterator.AddFilter_ObjectSet(MkSet(eImplementation));

            Try
                SchImplementation := ImplIterator.FirstSchObject;
                While SchImplementation <> Nil Do
                Begin
                    ReportInfo.Add('   ModelName: '         + SchImplementation.ModelName +
                                   ' ModelType: '           + SchImplementation.ModelType +
                                   ' Description: '         + SchImplementation.Description);
                    //   ReportInfo.Add('   This Current Implementation: '  + BoolToStr(SchImplementation.IsCurrent, true));
                    // ReportInfo.Add('   Component is in an IntegLib: '  + BoolToStr(SchImplementation.UseComponentLibrary, True));
  //                  ReportInfo.Add('   DatabaseModel:     '            + BoolToStr(SchImplementation.DatabaseModel,   true));
  //                  ReportInfo.Add('   IntegratedModel:   '            + BoolToStr(SchImplementation.IntegratedModel, true));
                    SchImplementation.GetState_IdentifierString;

                    SchImplementation.UseComponentLibrary := False;

                    For i := 0 To (SchImplementation.DatafileLinkCount - 1) Do
                    Begin
                        ModelDataFile := SchImplementation.DatafileLink[i];
                        If ModelDataFile <> Nil Then
                            if ModelDataFile.ModelType = cModelType_PCB then
                            Begin
                                ModelLibPath := ModelDataFile.Location;
                                ModelLibName := ExtractFilename(ModelLibPath);

                                if (ansipos(ExCompLib, ModelLibName) > 1) or (ModelLibName = '') then
                                begin
                                    ModelDataFile.Location := NewCompLib;
                                    if CompDBTable <> '' then
                                        ModelDataFile.Location := NewCompLib + '/' + CompDBTable;

                                    ReportInfo.Add('   Existing Model Name : ' + ModelDataFile.EntityName + '    Data File Location : ' + ModelLibPath +
                                                   '    New Library Loc : ' + ModelDataFile.Location);

                                end;
                            End;
                    End;

                   // sets/Ticks the bottom option (from CompLib) in PCB footprint dialogue
                    // but only for SchDoc as compiler will change the SchLib link to IntLib.
                    SchImplementation.UseComponentLibrary := True;

                    SchImplementation := ImplIterator.NextSchObject;
                End;

            Finally
                Component.SchIterator_Destroy(ImplIterator);
                SchServer.RobotManager.SendMessage(Component.I_ObjectAddress, c_BroadCast, SCHM_EndModify, c_NoEventData);

            End;

            ReportInfo.Add('');

     // obtain the next schematic symbol in the library
            Component := Iterator.NextSchObject;
        End;

    Finally
        CurrentSheet.SchIterator_Destroy(Iterator);

        CurrentSheet.GraphicallyInvalidate;
    End;

    GenerateReport(ReportInfo);
    ReportInfo.Free;
End;
{..............................................................................}

