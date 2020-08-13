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
12/08/2020  0.25 Always tick the use Library box in components properties UI.
13/08/2020  0.30 Add DMObject methods for broken ISch_Implementation in AD19 & 20

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
    NewDBTable  = '' ;                      // 'STD_Resistor';     // DB table name

// Altium appears to be able to find (name match) comp in any table of a DBLib if Use Table name is '' & unticked.
// set the Use Tablename tickbox, state is only changed if libname matches or search for table succeeds..
    UseDBTableName = true; // true;


    cMajorVerAD19  = 19;    // this & later versions (currently) have broken iSch_Implementation.

{..............................................................................}
Var
    IntLibMan          : IIntegratedLibraryManager;
    ReportInfo         : TStringList;
    VerMajor           : WideString;
    CurrentSheet       : ISch_Document;
    Component          : ISch_Component;
    Iterator           : ISch_Iterator;
    ImplIterator       : ISch_Iterator;    

    CompName           : WideString;
    CompDesignId       : WideString;
    CompLibRef         : WideString;
    CompLibID          : WideString;

{..............................................................................}
function Version(const dummy : boolean) : TStringList;
begin
    Result               := TStringList.Create;
    Result.Delimiter     := '.';
    Result.Duplicates    := dupAccept;
    Result.DelimitedText := Client.GetProductVersion;
end;
{..............................................................................}
Procedure GenerateReport(Report : TStringList);
Var
    WS         : IWorkspace;
    Prj        : IProject;
    Filepath   : WideString;
    Filename   : WideString;
    ReportDoc  : IServerDocument;

Begin
    WS := GetWorkspace;
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

    ReportDoc := Client.OpenDocument('Text', Filepath);
    If ReportDoc <> Nil Then
    begin
        Client.ShowDocument(ReportDoc);
        if (ReportDoc.GetIsShown <> 0 ) then
            ReportDoc.DoFileLoad;
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
        LibPath := IntLibMan.InstalledLibraryPath(I);
        if DBLibName = ExtractFileName(LibPath) then
        begin
            FoundLocation := '';
//            Found := IntLibMan.FindLibraryInformation(eLibIdentifierKind_NameWithType, DBLibName, DItemID, FoundLocation, DBTable);

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
{......................................................................................................}
function GetDMComponent(Doc : IDocument, Component : ISch_Component) : IComponent;
var
    I      : integer;
    DMComp : IComponent;
    DK     : WideString;
    found  : boolean;
begin
    Result := nil;
    DK     := Doc.DM_DocumentKind;
    Doc.DM_ComponentCount;
// SchLib does NOT have UniqueId
    found := false;
    for I := 0 to (Doc.DM_UniqueComponentCount - 1) do
    begin
        DMComp := Doc.DM_UniqueComponents(I);
//        Doc.DM_UniqueComponents(I).DM_UniqueId;
        if (DK = cDocKind_Sch) and (DMComp.DM_UniqueIdName = Component.UniqueId) then
            found := true;
        if (DK = cDocKind_SchLib) and (DMComp.DM_LibraryReference = Component.LibReference) then
            found := true;
        if found then
        begin
            Result := Doc.DM_UniqueComponents(I);
            break;
        end;
    end;
end;
{......................................................................................................}
function GetDMCompImplementation(DMComp : IComponent, SchImpl : ISch_Implementation) : IComponentImplementation;
var
    I : integer;
begin
    Result := nil;
    if DMComp <> nil then
    begin
        for I := 0 to (DMComp.DM_ImplementationCount - 1) do
        begin
            if (DMComp.DM_Implementations(I).DM_ModelName = SchImpl.ModelName) and
               (DMComp.DM_Implementations(I).DM_ModelType = SchImpl.ModelType) then Result := DMComp.DM_Implementations(I);
        end;
    end;
end;

function ModelDataFileLocation(ModelDataFile : ISch_ModelDatafileLink, DMCompImpl : IComponentImplementation , UseDMOMethod : boolean) : WideString;
begin
    Result := '';
    if ModelDataFile <> nil then Result := ModelDataFile.Location;
    if (UseDMOMethod) then
        if DMCompImpl <> nil then Result := DMCompImpl.DM_DatafileLocation(0);
end;
{..............................................................................}

Procedure ChangeLibraryNames;
Var
    Doc               : IDocument;      // DMObjects
    DMComp            : IComponent;
    DMCompImpl        : IComponentImplementation;
    SchImplementation : ISch_Implementation;
    ModelDataFile     : ISch_ModelDatafileLink;

    NewLibVFSPath      : WideString;
    CompLoc            : WideString;
    CompLocTable       : WideString;
    ModelLibPath       : WideString;
    ModelLibName       : WideString;
    ModelDFEName       : WideString;
    CompSymRef         : WideString;
    CompSrcLibName     : WideString;
    CompDBTable        : WideString;
    CompUseDBT         : boolean;

    UseDMOMethod       : boolean;
    DMOFound           : boolean;
    i                  : integer;

Begin

    Doc := GetWorkSpace.DM_FocusedDocument;
    If Not (Doc.DM_DocumentKind = cDocKind_Sch) Then
    Begin
         ShowError('Please open a SchDoc. ');
         Exit;
    End;

    If SchServer = Nil Then Exit;
    CurrentSheet := SchServer.GetCurrentSchDocument;

    VerMajor := Version(true).Strings(0);
// DMObjects not available in script API until compiled once.
    if (Doc.DM_UniqueComponentCount = 0) then Doc.DM_Compile;

//    flag version  >= AD19
    UseDMOMethod := false;
    if (StrToInt(VerMajor) >= cMajorVerAD19) then UseDMOMethod := true;

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

            DMOFound := true;
            DMComp   := GetDMComponent(Doc, Component);
            if DMComp = nil then DMOFound := false;

            SchServer.RobotManager.SendMessage(Component.I_ObjectAddress, c_BroadCast, SCHM_BeginModify, c_NoEventData);

//   tick Library box in Comp Properties. UI
            Component.UseLibraryName := true;

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

            ImplIterator := Component.SchIterator_Create;
            ImplIterator.AddFilter_ObjectSet(MkSet(eImplementation));

            Try
                SchImplementation := ImplIterator.FirstSchObject;
                While SchImplementation <> Nil Do
                Begin
                    ModelDFEName := SchImplementation.ModelName;
                    ReportInfo.Add('   ModelName: '         + SchImplementation.ModelName +
                                   ' ModelType: '           + SchImplementation.ModelType +
                                   ' Description: '         + SchImplementation.Description);

                    SchImplementation.GetState_IdentifierString;
                    SchImplementation.UseComponentLibrary := False;

                    if SchImplementation.ModelType  = cModelType_PCB then
                    begin
                        DMCompImpl := GetDMCompImplementation(DMComp, SchImplementation);
                        if DMCompImpl = nil then DMOFound := false;

                        for i := 0 To (SchImplementation.DatafileLinkCount - 1) Do
                        begin
                            ModelDataFile := SchImplementation.DatafileLink[i];
                            ModelLibPath := ModelDataFileLocation(ModelDataFile, DMCompImpl, UseDMOMethod);

                            If ModelLibPath <> '' Then
                            begin
                                ModelLibName := ExtractFilename(ModelLibPath);

                                if (ansipos(ExCompLib, ModelLibName) > 1) or (ModelLibName = '') then
                                begin
                                    NewLibVFSPath := NewCompLib;
                                    if CompDBTable <> '' then
                                        NewLibVFSPath := NewCompLib + '/' + CompDBTable;

                                    if (UseDMOMethod) then
                                    begin
                                        if (DMOFound) then
                                        begin
                                            DMCompImpl.DM_SetDatafileLocation(0) := NewLibVFSPath;
                                            ModelDFEName := DMCompImpl.DM_;                                        
                                        end;
                                    end else
                                        ModelDFEName :=ModelDataFile.EntityName;

                                    if Assigned(ModelDataFile) then ModelDataFile.Location := NewLibVFSPath;

                                    ReportInfo.Add('   Existing Model Name : ' + ModelDFEName + '    Data File Location : ' + ModelLibPath +
                                                   '    New Library Loc : ' + NewLibVFSPath);

                                end;
                            end;
                        end;
                    end;
                
                // Sets/Ticks the from Component Lib in PCB footprint UI dialogue
                // but only do this for SchDoc as compiler will change the SchLib link to IntLib.
                // This setting sort off overrides the model path stuff above but the above helps show the source libs.

                    SchImplementation.UseComponentLibrary := True;

                    SchImplementation := ImplIterator.NextSchObject;
                End;

            Finally
                Component.SchIterator_Destroy(ImplIterator);
                SchServer.RobotManager.SendMessage(Component.I_ObjectAddress, c_BroadCast, SCHM_EndModify, c_NoEventData);

            End;

            ReportInfo.Add('');
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

