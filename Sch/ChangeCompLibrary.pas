{.............................................................................
SchDoc ChangeCompLibrary.pas
  Replaces component & model DB library name(s)for name matches..
  Can search/find/change DB Table name as well.
  Can change lib from IntLib to DBLib.

  Can use blank target "NewDBTable" lib table name : then tries to locate table in DBLib
  Can use blank existing lib to match all existing components:
     - then tries to find all components in the DBlib & any table..
     - if found it updates the lib locations.

  Can change existing table to another table without search
  Can change existing DBlib to another without search

 ** Warning **
this script does not perform smart comp & model location updating.
except for component search with dblib & tablename = ''

DBlib linked components have their models connected to same DBLib & table.

Author BL Miller
from CompRenameSch.pas Ver 1.2 & ExplicitModelSourceInLibs.pas

20/02/2020  0.10 POC     not finished..
26/02/2020  0.20 Seems to work on Comp symbol & FP models
27/02/2020  0.21 Store full vfs DBLib/Table into ModelDatafile.Location (.UseCompLib=true overrides anyway!)
27/02/2020  0.22 better ModelDataFile.FileKind SchImp-ModelType test
14/0502020  0.23 added database lib table search
17/05/2020  0.24 added const option to un/tick the useDatabaseTable name.

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

const
//  DB library names for comp & models.
//  word IntLib must be spelt & typed exactly !!

// existing library name, any lib type, can be blank to match ALL
    ExCompLib  = '';                         //'Resistor.IntLib';
    NewCompLib = 'Database_Libs1.DbLib';     // New target DbLib fullname

// DB Table names
// for IntLib the table name must be ''

    ExDBTable   = '';                       // used if want to change from one named table to another
    NewDBTable  = '' ;                      // 'RakonSTD_Resistor';     // DB table name

// Altium appears to be able to find (name match) comp in any table of a DBLib if Use Table name is '' & unticked.
// set the Use Tablename tickbox, state is only changed if libname matches or search for table succeeds..
    UseDBTableName = false; // true;

{..............................................................................}
Var
    IntLibMan          : IIntegratedLibraryManager;
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

function FindDBLibTableInfo (DBLibName : WideString, DItemID : WideString, var DBTable : WideString) : Widestring;
var
    I, J          : Integer;
    DBLib         : IDatabaseLibDocument;
    SourcePath    : WideString;
    LibPath       : WideString;
    FoundLocation : WideString;
    Found         : boolean;
    LibCount      : Integer;
    InsLibType    : ILibraryType;

begin

    Result := '';     // CompLoc
    SourcePath := '';
    Found  := false;
    IntLibMan := IntegratedLibraryManager;
    LibCount  := IntLibMan.InstalledLibraryCount;   // zero based totals !

    I := 0;
    While (Result = '') and (I < LibCount) Do           //.Available...  <--> .Installed...
    Begin
        LibPath    := IntLibMan.InstalledLibraryPath(I);

        if DBLibName =  ExtractFileName(LibPath) then
        begin
            FoundLocation := '';

            if DBTable = '' then
            begin
                DBLib := IntLibMan.GetAvailableDBLibDocAtPath(LibPath);

                J := 0;
                While (Result = '') and (J < DBLib.GetTableCount) do
                begin
                    DBTable := DBLib.GetTableNameAt(J);
                    SourcePath := IntLibMan.GetComponentLocationFromDatabase(DBLibName, DBTable, DItemID, FoundLocation);
                    Result := FoundLocation;
                    inc(J);
                end;

                DBLib := Nil;
            end else
            begin
                SourcePath := IntLibMan.GetComponentLocationFromDatabase(DBLibName, DBTable,  DItemID, FoundLocation);
                Result := FoundLocation;
            end;

        end;
        inc(I);
    end;
End;

{..............................................................................}
Procedure ChangeLibraryNames;
Var
    i                  : integer;

    ModelDataFile      : ISch_ModelDatafileLink;

    NewLibPath         : WideString;
    CompLoc            : WideString;
    CompLocTable       : WideString;

    ModelLibPath       : WideString;
    ModelLibName       : WideString;

    CompSymRef         : WideString;
    CompSrcLibName     : WideString;
    CompDBTable        : WideString;
    CompUseDBT         : boolean;

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
            CompUseDBT     := Component.UseDBTableName;

            ReportInfo.Add(Component.Designator.Text + ' DesignId : ' + CompDesignId + '  LibRef : ' + CompLibRef + '  LibId : ' + CompLibId
                           + ' SLN : ' + CompSrcLibName + ' SymRef : ' + CompSymRef + ' tablename : ' + CompDBTable + ' use name : ' + BoolToStr(CompUseDBT, true) );
                //     LibraryPath;
            If (Length(CompSrcLibName) = 0) or (CompSrcLibName = '*') Then
                CompSrcLibName := 'no specific lib';

            if (ExCompLib = CompSrcLibName) then
            begin
                Component.SetState_SourceLibraryName(NewCompLib);
                //Component.SetState_DatabaseLibraryName(NewLibID);
                ReportInfo.Add(Component.Designator.Text + '   ' + CompName + Component.LibReference + ' matched ExCompLib : ' + CompSrcLibName + ' set NewLib: ' + NewCompLib);
            end;

// special case blank tablename & search for table
            if  NewDBTable = '' then
            begin
                if (ExCompLib = '') or (ansipos('IntLib', ExCompLib) > -1) then       // IntLibs use LibRef for unique name.
                    CompDesignId  := CompLibRef;

                CompLoc := ''; CompLocTable := '';
                CompLoc := FindDBLibTableInfo (NewCompLib, CompDesignId, CompLocTable);
                if CompLoc <> '' then
                begin
                    Component.SetState_SourceLibraryName(NewCompLib);
                    Component.SetState_DatabaseTableName(CompLocTable);
                    if UseDBTableName then
                        Component.UseDBTableName := True
                    else
                        Component.UseDBTableName := False;

                    ReportInfo.Add(Component.Designator.Text + '   ' + CompName + Component.LibReference + '  OldDBTable : ' + PadRight(CompDBTable,15) + ' located NewDBTable : ' + CompLocTable);
                    ReportInfo.Add('');
                end

            end;
            CompDBTable := Component.DatabaseTableName;

// special case match old table & comp table
            if (ExDBTable = CompDBTable) then
            begin
                // Component.UseDBTableName := False;
                Component.SetState_DatabaseTableName(NewDBTable);
                if UseDBTableName then
                    Component.UseDBTableName := True
                else
                    Component.UseDBTableName := False;

                ReportInfo.Add(Component.Designator.Text + '   ' + CompName + Component.LibReference + ' DBTable matches ' + ExDBTable + ' set NewDBTable : ' + NewDBTable);
                ReportInfo.Add('');
            end;

// if changed then reuse for models.
            CompDBTable := Component.DatabaseTableName;

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

                    SchImplementation.GetState_IdentifierString;
                    SchImplementation.UseComponentLibrary := False;

                    For i := 0 To (SchImplementation.DatafileLinkCount - 1) Do
                    Begin
                        ModelDataFile := SchImplementation.DatafileLink[i];
                        If ModelDataFile <> Nil Then
                            if ModelDataFile.FileKind  = cModelType_PCB then
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

                // Sets/Ticks the bottom option (from CompLib) in PCB footprint dialogue
                // but only for SchDoc as compiler will change the SchLib link to IntLib.
                // This setting sort off overrides the model path stuff above but the above helps show the source libs.

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

