{..............................................................................
 Summary 
         Project focused comparison of FP model names & paths
         Uses Component iterators etc to be able to set symbol lib links      
         Footprints should be in same IntLib as symbols.

         This code does check (untested!) footprint source matches FPcomponent source !!
         System like parameters in SchDoc/Prj component are ignored.
         Extra parameters in PCB FP component are ignored

B. Miller
21/08/2018  v0.1  intial
15/12/2018  v0.2  added message panel stuff
07/02/2020  v0.3  report cleanup: report differences of model names, libraries & parameters
08/02/2020  v0.31 Fix check all parameters & go back to old PCB iterator method for library checks.
                  CompImpl.DM_DatafileLibraryIdentifier(0) does not work for all comps.


..............................................................................}

Const
    InIntLib = True;
  //Constants used in the messages panel
    IMG_Wire       = 1;
    IMG_Component  = 2;
    IMG_Tick       = 3;
    cIconOk        = 3;
    IMG_Cross      = 4;
    IMG_IntegLib   = 59;
    IMG_OutputToFile = 67;
    IMG_OpenDocument = 68;
    IMG_GreenSquare  = 71;
    IMG_YellowSquare = 72;
    cIconInfo        = 107;

Var
    IntLibMan  : IIntegratedLibraryManager;
    MMPanel    : IMessagesManager;
    MMessage   : WideString;
    MSource    : WideString;
    MMObjAddr  : Integer;

    WS         : IWorkspace;
    Doc        : IDocument;
    Prj        : IBoardProject;
    PrjMapping : IComponentMappings;
    Board      : IPCB_Board;
    PrjReport  : TStringList;
    PCBList    : TStringList;
    FilePath   : WideString;
    FileName   : WideString;

Function BooleanToString (Value : LongBool) : String;
Begin
    Result := 'True';

    If Value = True Then Result := 'True'
                    Else Result := 'False';
End;
{..............................................................................}

{ some of SchDoc/Prj component paramters are not same in PCb footprint comp }
function CheckIgnoreParameter(PName : WideString) : boolean;
begin
    Result := false;
    PName := Trim(PName);
    case PName of
    'Component Kind'    :
        Result := true;
    'Component Type'    :
        Result := true;
    'Description'       :
        Result := true;
    'Designator'        :
        Result := true;
    'Footprint'         :
        Result := true;
    'Library Name'      :
        Result := true;
    'Library Reference' :
        Result := true;
    'Pin Count'         :
        Result := true;
    'PCB3D'             :
        Result := true;
    'Ibis Model'        :
        Result := true;
    'Signal Integrity'  :
        Result := true;
    'Simulation'        :
        Result := true;
    end;
end;

function FindParameterValue(Comp : IComponent, PName : WideString) : WideString;
var
    I       : integer;
    Param   : IParameter;
    bFound  : boolean;

begin
    Result := '';
    I := 0;
    bFound := false;

    while (not bFound) and (I < (Comp.DM_ParameterCount) ) do
    begin
        Param := Comp.DM_Parameters(I);
        if SameString(Param.DM_Name, PName, False) then
        begin
            bFound := true;
            Result := Param.DM_Value;
        end;
        Inc(I);
    end;
end;

function FindPCBComponent(Comp : IComponent) : IPCB_Component;
var
    PCBComp        : IPCB_Component;
    Iterator       : IPCB_BoardIterator;
    bFound         : boolean;
begin
    Result := nil;
    If Board = Nil Then Exit;

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    Iterator.AddFilter_IPCB_LayerSet(MkSet(eTopLayer,eBottomLayer));
    Iterator.AddFilter_Method(eProcessAll);

    bFound := false;

    PCBComp := Iterator.FirstPCBObject;

    while (not bFound) and (PCBComp <> Nil) Do
    begin
        if Comp.DM_UniqueId = PCBComp.SourceUniqueID then
        begin
            Result := PCBComp;
            bFound := true;
        end;
        PCBComp := Iterator.NextPCBObject;
    End;
    Board.BoardIterator_Destroy(Iterator);
end;

Procedure ReportCompMappings;
var
    ReportDocument : IServerDocument;
    PrimDoc        : IDocument;

    Comp           : IComponent;
    TargetComp     : IComponent;
    PCBComp        : IPCB_Component;
    CompImpl       : IComponentImplementation;
    TargetImpl     : IComponentImplementation;
    SchImplLib     : WideString;
    PcbFPLib       : WideString;
    Param          : IParameter;
    FPParam        : IParameter;
    CurrentSch     : ISch_Document;
    I, J, K, L, M  : Integer;
    TotLLinkCount  : Integer;            // Total mismatched library link count
    TotFLinkCount  : Integer;            // Total mismatched footprint model link count
    LLinkCount     : Integer;
    FLinkCount     : Integer;
    SMess          : WideString;
    bFound         : boolean;
    bSkip          : boolean;

Begin
    WS  := GetWorkspace;
    If WS = Nil Then Exit;

    Prj := WS.DM_FocusedProject;
    If Prj = Nil Then Exit;

    Prj.DM_Compile;

    IntLibMan := IntegratedLibraryManager;
    If IntLibMan = Nil Then Exit;

    Board := PCBServer.GetCurrentPCBBoard;
    PrimDoc := Prj.DM_PrimaryImplementationDocument;
    if PrimDoc = nil then exit;
    If Board = nil then
        Board := PcbServer.GetPcbBoardByPath(PrimDoc.DM_FullPath);
    if Board = Nil then
        Board := PcbServer.LoadPcbBoardByPath(PrimDoc.DM_FullPath);
    If Board = Nil Then Exit;

// for the DMObject Componentmapping interface
    PrjMapping := Prj.DM_ComponentMappings(PrimDoc.DM_FullPath);   //Board.FileName);

// required for the Board interface iterating eCompObject
{    If PCBServer = Nil then Client.StartServer('PCB');
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then
    Board := PCBServer.GetPCBBoardByPath(PrimDoc.DM_FullPath);
    If Board = Nil Then
        Board := PCBServer.LoadPCBBoardByPath(PrimDoc.DM_FullPath);
    if Board = Nil then Exit;
}
    MMPanel := WS.DM_MessagesManager;
    MMPanel.ClearMessages;
    WS.DM_ShowMessageView;

    MSource := 'CheckPrjCompFPMappings (CPCFM) script';
    MMessage := 'Check-Project-Component-FootPrint-Mappings script started';
    AddMessage(MMPanel,'[Info]',MMessage ,MSource , Prj.DM_ProjectFileName, '', '', cIconInfo);
    WS.DM_ShowMessageView;

    BeginHourGlass(crHourGlass);

    // Get current schematic document.
    // Doc := WS.DM_FocusedDocument;
    // If (CurrentLib.ObjectID <> eSchLib) And (CurrentLib.ObjectId <> eSheet) Then
    //     CurrentSch := SchServer.GetSchDocumentByPath(Doc.DM_FullPath);

    PrjReport  := TStringList.Create;

    PrjReport.Add('Project Footprint Model information:');
    PrjReport.Add('  Project: ' + Prj.DM_ProjectFileName);
    PrjReport.Add('');
    PrjReport.Add('Usable Libraries installed :-');

    for I := 0 to (IntLibMan.InstalledLibraryCount - 1) Do
    begin
        case LibraryType(IntLibMan.InstalledLibraryPath(I)) of     // fn from common libIntLibMan.pas
            eLibIntegrated : SMess := 'Integrated Lib : ';
            eLibDatabase   : SMess := 'dBase Library  : ';
// TLibraryType = (eLibIntegrated, eLibSource, eLibDatafile, eLibDatabase, eLibNone, eLibQuery, eLibDesignItems);
            else
                SMess              := 'Unusable Lib   : ';
        end;
        PrjReport.Add(PadRight(SMess, 20) + IntLibMan.InstalledLibraryPath(I));
    end;

    TotLLinkCount :=0;
    TotFLinkCount :=0;

    PrjReport.Add('');

    if (PrjMapping.DM_UnmatchedSourceComponentCount <> 0) or     //     Returns the number of unmatched source components.
       (PrjMapping.DM_UnmatchedTargetComponentCount <> 0) then   //     Returns the number of unmatched target components.
    begin
        PrjReport.Add('**** Warning ****');
        PrjReport.Add('Unmatched components in SchDoc : ' + IntToStr(PrjMapping.DM_UnmatchedSourceComponentCount)
                      + '  | in PcbDoc : ' + IntToStr(PrjMapping.DM_UnmatchedTargetComponentCount) );
        for I := 0 to (PrjMapping.DM_UnmatchedSourceComponentCount - 1) do
        begin
            Comp := PrjMapping.DM_UnmatchedSourceComponent(I);
            PrjReport.Add('Unmatched in SchDoc : ' + IntToStr(I + 1) + ' '+ Comp.DM_FullLogicalDesignatorForDisplay
                          + '  ' + Comp.DM_LibraryReference);
            MMObjAddr := Comp.DM_ObjectAdress;
            MMessage := 'UnMatched Sch Component  : '+ IntToStr(I) + ' | ' + Comp.DM_FullLogicalDesignatorForDisplay + ' | ' + Comp.DM_LibraryReference;
            //                                                            'CrossProbeConnective=' + IntToStr(MMObjAddr)
            AddMessage(MMPanel, '[Info]', MMessage , MSource, Comp.DM_OwnerDocumentFullPath, 'WorkspaceManager:View', 'CrossProbeConnective=' + IntToStr(MMObjAddr), IMG_Component);
        end;

        for I := 0 to (PrjMapping.DM_UnmatchedTargetComponentCount - 1) do
        begin
            Comp := PrjMapping.DM_UnmatchedTargetComponent(I);
            PCBComp := FindPCBComponent(Comp);

            PrjReport.Add('Unmatched in PcbDoc : ' + IntToStr(I + 1) + ' ' + Comp.DM_FullLogicalDesignatorForDisplay
                          + '  ' + Comp.DM_FootPrint + '  ' + Comp.DM_LibraryReference);
            MMObjAddr := Comp.DM_ObjectAdress;
            MMessage := 'UnMatched PCB Component  : '+ IntToStr(I) + ' | ' + Comp.DM_FullLogicalDesignatorForDisplay + + ' | ' + Comp.DM_FootPrint;

// need find method that does not use uniqueID as unmatched PCb comps might not have them.
            if PCBComp <> nil then
                MMessage := MMessage + ' | ' + PCBComp.SourceFootprintLibrary;   //  FindParameterValue(Comp , 'Library Name');

            AddMessage(MMPanel, '[Info]', MMessage , MSource, PrimDoc.DM_FileName, 'WorkspaceManager:View', 'CrossProbeConnective=' + IntToStr(MMObjAddr), IMG_Component);
        end;

        PrjReport.Add('');
    end;

    PrjReport.Add('Matched components in SchDoc(s) : ' + IntToStr(PrjMapping.DM_MatchedComponentCount) );

    For I := 0 to (Prj.DM_PhysicalDocumentCount - 1) Do
    Begin
        Doc := Prj.DM_PhysicalDocuments(I);
        If Doc.DM_DocumentKind = cDocKind_Sch Then
        begin
            LLinkCount := 0; FLinkCount := 0;

            PrjReport.Add('');
            PrjReport.Add('Sheet : ' + IntToStr(I+1) + '  ' + Doc.DM_FileName + ' ' + IntToStr(Doc.DM_ChannelIndex) );
            PrjReport.Add('');
            for J := 0 to Doc.DM_ComponentCount - 1 Do
            begin
                Comp := Doc.DM_Components(J);

                PrjReport.Add(IntToStr(J+1) + ' Component LogDes : ' + Comp.DM_LogicalDesignator + '  | PhysDes: ' + Comp.DM_PhysicalDesignator + '  | CalcDes: ' + Comp.DM_CalculatedDesignator);
                PrjReport.Add(' Lib Reference    : ' + Comp.DM_LibraryReference);
                PrjReport.Add(' Comp FootPrint   : ' + Comp.DM_FootPrint);
                PrjReport.Add(' Current FP Model : ' + Comp.DM_CurrentImplementation(cDocKind_PcbLib).DM_ModelName + '  ModelType :' + Comp.DM_CurrentImplementation(cDocKind_PcbLib).DM_ModelType);

             // old way to get PCB footprint
                PCBComp := FindPCBComponent(Comp);

// report the project mapping source sch to target pcb
// Matched Source & Target have the same index

                for K := 0 to (PrjMapping.DM_MatchedComponentCount - 1) do
                begin
                    if (PrjMapping.DM_MatchedSourceComponent(K).DM_UniqueId = Comp.DM_UniqueId) then
                    begin

                        TargetComp := PrjMapping.DM_MatchedTargetComponent(K);
                        CompImpl   := Comp.DM_CurrentImplementation(cDocKind_PcbLib);
                    // Is one Impl in PCB, & it has no model files or datalinks.
                        TargetComp.DM_ImplementationCount ;
                        TargetImpl := TargetComp.DM_CurrentImplementation(cDocKind_PcbLib);

// the below method does not always return the SchImp lib path ?????
                        CompImpl.DM_DatafileCount;
                        SchImplLib := CompImpl.DM_DatafileLibraryIdentifier(0);
                        CompImpl.DM_DatafileEntity(0);
                        CompImpl.DM_DatafileLocation(0);

                        PcbFPLib   := TargetComp.DM_SourceLibraryName ;   // TargetImpl.DM_DatafileLibraryIdentifier(0);

                    //    PrjReport.Add(' Mapping Target : ' + IntToStr(K) + ' | Des: ' + TargetComp.DM_FullLogicalDesignatorForDisplay);

                        if (CompImpl.DM_ModelName = TargetImpl.DM_ModelName) then
                        begin
                   // this does not work
                   //         if trim(SchImplLib) <> trim(PcbFPLib) then
                            if (PCBComp <> nil) then
                            if PCBComp.SourceFootprintLibrary <> PCBComp.SourceComponentLibrary then
                            begin
                                PrjReport.Add('*** mismatched FP model libs : ' + PCBComp.SourceComponentLibrary + ' <> ' + PCBComp.SourceFootprintLibrary + '  ***');
                                inc(LLinkCount);
                            end;

// report component level parameters
//                            if (Comp.DM_ParameterCount <> TargetComp.DM_ParameterCount) then
//                                PrjReport.Add(' mismatch parameter count : Sch | PCB' + PadRight(IntToStr(Comp.DM_ParameterCount), 3) + ' | ' + PadRight(IntToStr(TargetComp.DM_ParameterCount), 3));

                            for L := 0 to (Comp.DM_ParameterCount - 1) do
                            begin
                                Param := Comp.DM_Parameters(L);
                                M := 0;
                                bFound := false;
                                bSkip := CheckIgnoreParameter(Param.DM_Name);

                                while (not bSkip) and (not bFound) and (M < TargetComp.DM_ParameterCount) do
                                begin
                                    FPParam := TargetComp.DM_Parameters(M);
                                    Inc(M);
                                    if (FPParam.DM_Name = Param.DM_Name) then
                                    begin
                                        bFound := true;
                                        if (FPParam.DM_Value <> Param.DM_Value) then
                                            PrjReport.Add('*** mismatch parameter value for ' + Param.DM_Name + ' | ' + Param.DM_Value + ' <> ' + FPParam.DM_Value + ' ***');
                                    end;
                                    Param.DM_Kind;
                                    Param.DM_ConfigurationName;
                                end;
                                if (not bSkip) and (not bFound) then
                                    PrjReport.Add('*** missing FP parameter ' + PadRight(IntToStr(L + 1), 3) + '  ' + Param.DM_Name + ' | ' + Param.DM_Value + ' ***');
                            end;

                        end
                        else begin
                            PrjReport.Add('***  non-matching Source-Target FP ModelNames  ***');
                            inc(FLinkCount);
                        end;
                    end;

                end;  // k prjmapping

                if PCBComp = nil then
                    PrjReport.Add('***  strange ? missing PCB Component  ***');

                PrjReport.Add('');
            end;  // j dm_components


            PrjReport.Add('');
            TotLLinkCount := TotLLinkCount + LLinkCount;
            TotFLinkCount := TotFLinkCount + FLinkCount;
        end;
    End;  // i physical docs.

// report project level parameters
    for I := 0 to Prj.DM_ParameterCount - 1 Do
    begin
        Param := Prj.DM_Parameters(I);
        PrjReport.Add(PadRight(IntToStr(I + 1), 3)+ Param.DM_Name + ' ' + Param.DM_Value + ' ' + Param.DM_Description);
        Param.DM_ConfigurationName;
        Param.DM_Kind;
        Param.DM_RawText;

        Param.DM_OriginalOwner;
        Param.DM_Visible;
    end; // i prj parameters

    PrjReport.Insert(2, 'Total Mismatched Model Library Link Count : ' + IntToStr(TotLLinkCount));
    PrjReport.Insert(3, 'Total Mismatched Model Name Links   Count : ' + IntToStr(TotFLinkCount));
    PrjReport.Add('===========  EOF  ==================================');



    FilePath := ExtractFilePath(Prj.DM_ProjectFullPath);
    FileName := FilePath + ExtractFileName(Prj.DM_ProjectFileName) + '_ReportMappings.Txt';
    PrjReport.SaveToFile(FileName);

    EndHourGlass;

    WS := GetWorkspace;
    WS.DM_ShowMessageView;
    //Prj.DM_AddSourceDocument(FileName);
    ReportDocument := Client.OpenDocument('Text', FileName);
    If ReportDocument <> Nil Then
        Client.ShowDocument(ReportDocument);

End;

// see Project/OutJob-Script/SimpleOJScript.pas.

//      first 7 parameters are system NOT user..
//            'Component Kind'
//            'Component Type'
//            'Description'
//            'Designator'
//            'Footprint'
//            'Library Reference'
//            'Pin Count'
//            'Ibis Model'




{..............................................................................}
// Function DM_UnmatchedSourceComponent(Index : Integer) : IComponent;  Returns the indexed unmatched source component, that is, a target component could not be found to map to this source component. Use the DM_UnmatchedSourceComponentCount function.
// Function DM_UnmatchedTargetComponent(Index : Integer) : IComponent;  Returns the indexed unmatched target component, that is, a source component could not be found to map to the target component. Use the DM_UnmatchedTargetComponentCount function.
// Function DM_MatchedComponentCount: Integer;  Returns the number of matched components.
// Function DM_MatchedSourceComponent  (Index : Integer) : IComponent;  Returns the indexed matched source component (that has been matched with a target component). Use the DM_MatchedSourceComponentCount function.
// Function DM_MatchedTargetComponent  (Index : Integer) : IComponent;  Returns the indexed matched source component (that has been matched with a target component). Use the DM_MatchedTargetComponentCount function.

