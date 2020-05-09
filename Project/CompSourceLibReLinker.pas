{ CompSourceLibReLinker.pas

 from ExplicitModelSourceInLibs.pas

 1. Run on each/every SchLib that is part of Project.
 2. Run on each Sheet in SchDoc..
 3. Run on PcbDoc in project

 For each component in schLib it updates the source symbol & footprint lib names if located.
 For SchDoc (if Comp found) it undates comp link to SchLib
 For PcbDoc (if FP found) it updates source & component lib links.


 BLM

21/04/2020  DatafileLinkcount does not work in AD19
09/05/2020  0.01 from ExplicitModelSourceInLibs.pas
09/05/2020  0.02 Added PcbDoc processing. tweaked report padding/spacing.. 

DBLib:
    Component is defined in the table.
    .DesignItemId is unique component identifier
    .LibReference links to the (shared) symbol entry in a SchLib

SchLib/IntLib:
    Component is defined in SchLib "symbol"  with paras & SchImpl links (models)
    .DesignItemId is not used?  (I set same as LibRef)
    .LibReference is unique symbol name

So .LibReference always points to a symbol in SchLib.

                                           when from DBLib:                                       when from IntLib:
    Component.DesignItemId;                same as existing / last part..
    Component.LibReference;                'RES_BlueRect_2Pin'         symbol                     '0R05_0805_5%_1/4W'
    Component.LibraryIdentifier;           'Database_Libs1.DBLib/Resistor'                        'STD_Resistor.IntLib'
    Component.SourceLibraryName;           'Database_Libs1.DBLib'                                 'STD_Resistor.IntLib'
    Component.SymbolReference;             same as LibRef                                         same as LibRef



.......................................................................................}

Var
    WS        : IWorkspace;
    Prj       : IProject;
    IntLibMan : IIntegratedLibraryManager;
    Report    : TStringList;

{..............................................................................}
Procedure GenerateModelsReport (FileSuffix : WideString, SCount : Integer, FCount : Integer);
Var
    Filepath  : WideString;
    Filename  : WideString;
    ReportDoc : IServerDocument;

Begin
    WS  := GetWorkspace;
    Filepath := ExtractFilePath(WS.DM_FocusedDocument.DM_FullPath);
    Prj := WS.DM_FocusedProject;
    If Prj <> Nil Then
       Filepath := ExtractFilePath(Prj.DM_ProjectFullPath);
             
    If length(Filepath) < 5 then Filepath := 'c:\temp\';

    Filename := WS.DM_FocusedDocument.DM_FileName;
    
    Report.Insert(0, 'Script: CompSourceLibReLinker.pas ');
    Report.Insert(1, 'Sch & SchLib Components and Linked Model Report...');
    Report.Insert(2, '========================================================');
    Report.Insert(3, 'Project Name : ' + ExtractFilename(Prj.DM_ProjectFullPath));
    Report.Insert(4, 'Focused Doc  : ' + Filename);
    Report.Insert(5, ' ');
    Report.Insert(6, ' Missing Sch Symbol Link Count : ' + IntToStr(SCount));
    Report.Insert(7, ' Missing Footprint Link Count  : ' + IntToStr(FCount) + '          search for text ---->  MISSING <---- ');
    Report.Insert(8, ' ');

    Filepath := Filepath + Filename + FileSuffix;
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

{..............................................................................}
Procedure SetDocumentDirty (Dummy : Boolean);
Var
    AView           : IServerDocumentView;
    AServerDocument : IServerDocument;
Begin
    If Client = Nil Then Exit;
    AView := Client.GetCurrentView;
    AServerDocument := AView.OwnerDocument;
    AServerDocument.Modified := True;
End;
{..............................................................................}

function CheckFileInProject(Prj : IProject, FullPathName : Widestring) : boolean;
var
    I : integer;
begin
    Result := false;
    if Prj.DM_IndexOfSourceDocument(FullPathName) > -1 then Result := true;

//    for I := 0 to (Prj.DM_LogicalDocumentCount - 1) Do
//    begin
// if FullPath = Prj.DM_LogicalDocuments(I).DM_FullPath then Result := true;
//    end;
end;

Procedure LinkFPModelsToPcbLib;
var
    Doc            : ISch_Document;
    Board          : IPCB_Board;
    Component      : IPCB_Component;
    Iterator       : IPCB_BoardIterator;
    LibIdKind      : ILibIdentifierKind;
    LibType        : ILibraryType;
    FoundLocation  : WideString;
    DataFileLoc    : WideString;
    FoundLibName   : WideString;
    InIntLib       : boolean;
    Found          : boolean;
    Fix            : Boolean;
    FLinkCount     : Integer;

begin
    Fix     := true;                  // fix refers to changing lib prefixes

    IntLibMan := IntegratedLibraryManager;
    If IntLibMan = Nil Then Exit;
    WS := GetWorkSpace;
    if WS = nil then exit;
    Prj := WS.DM_FocusedProject;
    if Prj = nil then
    begin
        ShowMessage('needs a focused project');
        exit;
    end;

    Doc := WS.DM_FocusedDocument;
    if not (Doc.DM_DocumentKind = cDocKind_Pcb) then
    begin
         ShowError('Please focus a Project PcbDoc. ');
         Exit;
    end else
    begin
        if PCBServer = Nil then Client.StartServer('PCB');
        If PCBServer = Nil Then Exit;
        Board := PCBServer.GetCurrentPCBBoard;
    end;

    Report := TStringList.Create;
    PCBserver.PreProcess;

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    Iterator.AddFilter_LayerSet(MkSet(eTopLayer,eBottomLayer));
    Iterator.AddFilter_Method(eProcessAll);

    FLinkCount := 0;

    Component := Iterator.FirstPCBObject;
    While (Component <> Nil) Do
    Begin
            FoundLocation := ''; DataFileLoc := '';
            FoundLibName := '*';
            LibIdKind := eLibIdentifierKind_Any;
            InIntLib := False;

// TLibraryType = (eLibIntegrated, eLibSource, eLibDatafile, eLibDatabase, eLibNone, eLibQuery, eLibDesignItems);
            LibType := eLibSource;  // LibraryType(FoundLocation);

//            DataFileLoc := IntLibMan.FindDatafileInStandardLibs(Component.Name, cDocKind_PcbLib, LibDoc.DM_FullPath, False {not IntLib}, FoundLocation);
            DataFileLoc := IntLibMan.FindDatafileEntitySourceDatafilePath (LibIdKind, FoundLibName, Component.Pattern, cDocKind_PcbLib, InIntLib);

            if (DataFileLoc <> '') then Found := true;
            FoundLibName := ExtractFilename(DataFileLoc);
            Found := CheckFileInProject(Prj, DataFileLoc);

            if not Found then inc(FLinkCount);

            if Fix and Found then
            begin
                Component.SourceFootprintLibrary := FoundLibName;
                Component.SourceComponentLibrary := FoundLibName;
                Report.Add('updated FP Comp : ' + PadRight(Component.Name.Text, 25) + '  FP : ' + PadRight(Component.Pattern, 25) +  '  lib : '  + FoundLibName);
            end;

        // Notify the PCB editor that the pcb object has been modified
        // PCBServer.SendMessageToRobots(Component.I_ObjectAddress, c_Broadcast, PCBM_EndModify , c_NoEventData);
        Component := Iterator.NextPCBObject;
    End;
    Board.BoardIterator_Destroy(Iterator);

    PCBServer.PostProcess;
//    PCBServer.PostProcess_Clustered;
    Client.SendMessage('PCB:Zoom', 'Action=Redraw' , 255, Client.CurrentView);

    SetDocumentDirty(true);
    GenerateModelsReport('-FPLib.Txt', 0, FLinkCount);
    Report.Free;
end;

{..............................................................................}
Procedure LinkSchCompsToSourceLibs;
Var
    CurrentLib         : ISch_Lib;
    CurrentSheet       : ISch_Document;
    Iterator           : ISch_Iterator;
    Component          : ISch_Component;
    Doc                : ISch_Document;
    ImplIterator       : ISch_Iterator;
    SchImpl            : ISch_Implementation;
    ModelDataFile      : ISch_ModelDatafileLink;

    FPModel         : IPcb_LibComponent;
    InIntLib        : Boolean;
    SourceCLibName  : WideString;
    SourceDBLibName : WideString;
    FoundLocation   : WideString;
    ModelDFileLoc   : WideString;
    DataFileLoc     : WideString;
    TopLevelLoc     : WideString;
    FoundLibName    : WideString;
    DBTableName     : WideString;
    FoundLibPath    : WideString;
    CompLoc         : WideString;
    SymbolRef       : WideString;
    DItemID         : WideString;
    CompLibRef      : WideString;
    CompLibID       : WideString;
    LibIdKind       : ILibIdentifierKind;
    LibType         : ILibraryType;
    Found           : boolean;
    Fix              : Boolean;
    J                  : Integer;
    SLinkCount       : Integer;            // missing symbol link count
    FLinkCount       : Integer;            // missing footprint model link count

Begin
    Fix     := true;                  // fix refers to changing lib prefixes

    IntLibMan := IntegratedLibraryManager;
    If IntLibMan = Nil Then Exit;

    WS := GetWorkspace;
    if WS = nil then exit;
    Prj := WS.DM_FocusedProject;
    if Prj = nil then
    begin
        ShowMessage('needs a focused project');
        exit;
    end;

    if PCBServer = Nil then Client.StartServer('PCB');
    if SchServer = Nil then Client.StartServer('SCH');
    If SchServer = Nil Then Exit;
    If PCBServer = Nil Then Exit;

    Doc := WS.DM_FocusedDocument;

    If Not ((Doc.DM_DocumentKind = cDocKind_SchLib) or (Doc.DM_DocumentKind = cDocKind_Sch)) Then
    Begin
         ShowError('Please focus a Project SchDoc or SchLib.');
         Exit;
    end
    else begin
        CurrentLib := SchServer.GetCurrentSchDocument;
        If CurrentLib = Nil Then Exit;
    end; 

    If CurrentLib.ObjectID = eSchLib Then
        Iterator := CurrentLib.SchLibIterator_Create
    Else
        Iterator := CurrentLib.SchIterator_Create;

    Report := TStringList.Create;

    Iterator.AddFilter_ObjectSet(MkSet(eSchComponent));
    Try
        Component := Iterator.FirstSchObject;
        SLinkCount := 0;
        FLinkCount := 0;

        While Component <> Nil Do
        Begin
            CompLoc       := '';
            SymbolRef     := '';
            FoundLocation := '';

            // Fix-ups:
            // this might stop SchEd "Update from Libraries" changing the IntLib link back to Schlib.
            DItemID := Component.DesignItemID;
            CompLibRef := Component.LibReference;

            If CurrentLib.ObjectID = eSchLib then
            begin
                Component.SetState_SourceLibraryName(ExtractFilename(CurrentLib.DocumentName));
                // fix components extracted from dBlib into SchLib/IntLib with problems..
                //Component.DatabaseLibraryName := '';
                Component.DatabaseTableName := '';
                Component.UseDBTableName := false;
                if DItemId <> Component.LibReference then DItemId := Component.LibReference;
                Component.DesignItemId := DItemID;
            end;

            SourceCLibName  := Component.SourceLibraryName;
            SourceDBLibName := Component.DatabaseLibraryName;
            DBTableName     := Component.DatabaseTableName;

            If CurrentLib.ObjectID = eSheet Then
                Report.Add(' Component Designator : '                 + Component.Designator.Text);
            if DItemId <> Component.DesignItemId then
                Report.Add('   DesignItemID       : ' + DItemID + ' fixed -> ' + Component.DesignItemID)
            else
                Report.Add('   DesignItemID       : ' + DItemID);
            Report.Add    ('   Source Lib Name    : ' + SourceCLibName);
            Report.Add    ('   Lib Reference      : ' + Component.LibReference);
            Report.Add    ('   Lib Symbol Ref     : ' + Component.SymbolReference);
            Report.Add    ('   Lib Identifier     : ' + Component.LibraryIdentifier);


         // think '*' causes problems placing parts in SchDoc from script.(process call without full path)
            if Component.LibraryPath = '*' then
            begin
                Component.LibraryPath := '';
                Report.Add('   LibPath was       : <*> now <blank>');
            end;

            if SourceCLibName  = '*' then Component.SetState_SourceLibraryName('');

            LibIdKind := eLibIdentifierKind_NameWithType;
            DItemID   := Component.DesignItemID;               // prim key for DB & we set same as LibRef for IntLib/SchLib.
            CompLibID := Component.LibraryIdentifier;
            LibType   := eLibSource;

         // if SchDoc check symbols have IntLib/dBLib link
            if CurrentLib.ObjectID = eSheet then
            begin
//                FoundLibName := SourceCLibName;
                FoundLibName := '*';
                Found := false;
                CompLoc := IntLibMan.GetComponentLocation(FoundLibName,  DItemID, FoundLocation);

                FoundLibName := ExtractFilename(FoundLocation);

// TLibraryType = (eLibIntegrated, eLibSource, eLibDatafile, eLibDatabase, eLibNone, eLibQuery, eLibDesignItems);
                LibType := eLibSource;  // LibraryType(FoundLocation);
                Found := CheckFileInProject(Prj, FoundLocation);

                if not Found then Inc(SLinkCount);

//                if (FoundLocation <> '') Then
                if Fix & (Found) Then
                begin
                    Report.Add    ('   Library Path    : ' + Component.LibraryPath);
                    Component.SetState_DatabaseTableName('');
                    Component.UseDBTableName := False;
                    Component.SetState_SourceLibraryName(FoundLibName);
                    Report.Add('   Fixed Source Lib : ' + FoundLibName);
                end
                else
                    Report.Add(' Component Source Lib NOT Found ! ');
            end; // is Sch Sheet

            ImplIterator := Component.SchIterator_Create;
            ImplIterator.AddFilter_ObjectSet(MkSet(eImplementation));

            Try
                SchImpl := ImplIterator.FirstSchObject;
                While SchImpl <> Nil Do
                Begin
                    Report.Add(' Implementation Model details:');
                    Report.Add('   Name : ' + SchImpl.ModelName + '   Type : ' + SchImpl.ModelType +
                                   '   Description : ' + SchImpl.Description);
                    Report.Add('   Map :  ' + SchImpl.MapAsString);

                    If SchImpl.ModelType = cModelType_PCB Then
                    begin
                        If (CurrentLib.ObjectID = eSheet) and SchImpl.IsCurrent Then
                            Report.Add(' Is Current (default) FootPrint Model:');

                        If SchImpl.DatafileLinkCount = 0 then // missing FP PcbLib link
                        begin
                            SchImpl.AddDataFileLink(SchImpl.ModelName, '', cModelType_PCB);
                        end;


                        SchImpl.DatalinksLocked := False;
                        ModelDataFile := SchImpl.DatafileLink(0);
                        FoundLibName := '*';
                        If Assigned(ModelDataFile) Then
                        begin
                            FoundLibName := ModelDataFile.Location;
                            Report.Add(' Implementation Data File Link Details:');
                            Report.Add('   File Location: ' + FoundLibName);
                            //            + ', Entity Name: '    + ModelDataFile.EntityName
                            //            + ', FileKind: '       + ModelDataFile.FileKind);
                        end;

                        // Look for a footprint models in .PCBLIB    ModelType      := 'PCBLIB';
                        // Want SchDoc to link to source Libs.
                        LibType  := eLibSource;
                        // unTick the bottom option (IntLib complib) in PCB footprint dialogue
                        SchImpl.UseComponentLibrary := false;

                        if (FoundLibName = '') or (FoundLibName = '*') then FoundLibName := Component.SourceLibraryName;


                        TopLevelLoc := '';
                        InIntLib := False;
                        LibIdKind := eLibIdentifierKind_Any;
//                        LibIdKind := eLibIdentifierKind_NameWithType;
                        FoundLibName := '*';

                        TopLevelLoc := IntLibMan.FindDatafileEntitySourceDatafilePath (LibIdKind, FoundLibName, SchImpl.ModelName, 'PCBLib', InIntLib);

                        FoundLibName := ExtractFilename(TopLevelLoc);
                        Found := CheckFileInProject(Prj, TopLevelLoc);
                        if not Found then Inc(FLinkCount);

                        if Fix and Found then
                        begin
                            ModelDataFile.Location := FoundLibName;
                            Report.Add('   Updated Model Location: ' + FoundLibName);
                            // no point trying update FP description & height in a SchDoc.
                            if CurrentLib.ObjectID = eSchLib then
                            Begin
                                //FPModel := GetDatafileInLibrary(ModelDataFile.EntityName, eLibSource, InIntLib, FoundLocation);
                                FPModel := PcbServer.LoadCompFromLibrary(SchImpl.ModelName, TopLevelLoc);
                                if FPModel <> NIL then
                                begin
                                    if SchImpl.Description <> FPModel.Description Then
                                       SchImpl.Description := FPModel.Description;
                                    SchImpl.UseComponentLibrary := False;
                                    Report.Add('Updated Component Footprint Description: '  + SchImpl.Description);
                                    Report.Add('    Footprint Height         : '  + CoordUnitToString(FPModel.Height, eMetric));
                                    FPModel := NIL;
                                end;
                            end;
                        end;

                        ModelDFileLoc := ModelDataFile.Location;
                        if trim(ModelDFileLoc) = ''  then ModelDFileLoc := '---->  MISSING <----';
                        Report.Add(' Implementation Data File Link Details : ');
                        Report.Add('   File Location : ' + ModelDFileLoc);
                        Report.Add('');

                    End;
                    SchImpl := ImplIterator.NextSchObject;
                End;

            Finally
                Component.SchIterator_Destroy(ImplIterator);
            End;

            Report.Add('');
            Report.Add('');
            // Send a system notification that component change in the library.
            If Fix Then SchServer.RobotManager.SendMessage(Component.I_ObjectAddress, c_BroadCast, SCHM_EndModify, c_NoEventData);
            Component := Iterator.NextSchObject;
        End;

    Finally
        // Refresh library.
        CurrentLib.GraphicallyInvalidate;
        If CurrentLib.ObjectID = eSchLib Then
            // CurrentLib.SchLibIterator_Destroy(Iterator)
            CurrentLib.SchIterator_Destroy(Iterator)
        Else
            CurrentLib.SchIterator_Destroy(Iterator);
    End;

    SetDocumentDirty(true);

    GenerateModelsReport('-CompModels.Txt', SLinkCount, FLinkCount);
    Report.Free;
End;

{ ..............................................................................

