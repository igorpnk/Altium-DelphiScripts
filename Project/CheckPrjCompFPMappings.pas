{..............................................................................
 Summary 
         Project focused comparison of FP model names & paths
         Uses Component iterators etc to be able to set symbol lib links      
         Footprints should be in same IntLib as symbols.

         This code does check (untested!) footprint source matches FPcomponent source !!
                                                                              
B. Miller
21/08/2018  v0.1  intial
15/12/2018  v0.2  added message panel stuff 

                                         
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
    Param      : IParameter;
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

Procedure ReportCompMappings;
var
    PCBComp        : IPCB_Component;
    Iterator       : IPCB_BoardIterator;
    ParamReport    : TStringList;

    ReportDocument : IServerDocument;
    PrimDoc        : IDocument;

    Comp           : IComponent;
    TargetComp     : iComponent;
    CompImpl       : IComponentImplementation;
    TargetImpl     : IComponentImplementation;
    CurrentSch     : ISch_Document;
    I, J, K, L     : Integer;
    TotSLinkCount  : Integer;            // Total missing symbol link count
    TotFLinkCount  : Integer;            // Total missing footprint model link count
    SLinkCount     : Integer;
    FLinkCount     : Integer;
    SMess          : WideString;

Begin
    WS  := GetWorkspace;
    If WS = Nil Then Exit;

    Prj := WS.DM_FocusedProject;
    If Prj = Nil Then Exit;

    Prj.DM_Compile;

    IntLibMan := IntegratedLibraryManager;
    If IntLibMan = Nil Then Exit;

    PrimDoc := Prj.DM_PrimaryImplementationDocument;
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

    TotSLinkCount :=0;
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
            MMessage := 'UnMatched Component  : '+ IntToStr(I) + ' |  Name : ' + Chr(34) + Comp.DM_LibraryReference + Chr(34) + '  ' + Comp.DM_FullLogicalDesignatorForDisplay;
            //                                                            'CrossProbeConnective=' + IntToStr(MMObjAddr)
            AddMessage(MMPanel, '[Info]', MMessage , MSource, Comp.DM_OwnerDocumentFullPath, 'WorkspaceManager:View', 'CrossProbeConnective=' + IntToStr(MMObjAddr), IMG_Component);
        end;

        for I := 0 to (PrjMapping.DM_UnmatchedTargetComponentCount - 1) do
        begin
            Comp := PrjMapping.DM_UnmatchedTargetComponent(I);
            PrjReport.Add('Unmatched in PcbDoc : ' + IntToStr(I + 1) + ' ' + Comp.DM_FullLogicalDesignatorForDisplay
                          + '  ' + Comp.DM_FootPrint);
            MMObjAddr := Comp.DM_ObjectAdress;
            MMessage := 'UnMatched Component  : '+ IntToStr(I) + ' |  Name : ' + Chr(34) + Comp.DM_LibraryReference + Chr(34);
            //                                                            'CrossProbeConnective=' + IntToStr(MMObjAddr)
            AddMessage(MMPanel, '[Info]', MMessage , MSource, PrimDoc.DM_FileName, 'WorkspaceManager:View', 'CrossProbeConnective=' + IntToStr(MMObjAddr), IMG_Component);
        end;

        PrjReport.Add('');
    end;

    For I := 0 to (Prj.DM_PhysicalDocumentCount - 1) Do
    Begin
        Doc := Prj.DM_PhysicalDocuments(I);
        If Doc.DM_DocumentKind = cDocKind_Sch Then
        begin
            SLinkCount := 0; FLinkCount := 0;

            PrjReport.Add('');
            PrjReport.Add('  Sheet  : ' + Doc.DM_FileName);
            PrjReport.Add('');
            for J := 0 to Doc.DM_ComponentCount - 1 Do
            begin
                Comp := Doc.DM_Components(J);

                PrjReport.Add(' Component LogDes : ' + Comp.DM_LogicalDesignator + '  | PhysDes: ' + Comp.DM_PhysicalDesignator + '  | CalcDes: ' + Comp.DM_CalculatedDesignator);
                PrjReport.Add(' Lib Reference    : ' + Comp.DM_LibraryReference);
                PrjReport.Add(' Comp FootPrint   : ' + Comp.DM_FootPrint);
                PrjReport.Add(' Current FP Model : ' + Comp.DM_CurrentImplementation(cDocKind_PcbLib).DM_ModelName + '  ModelType :' + Comp.DM_CurrentImplementation(cDocKind_PcbLib).DM_ModelType);

// report the project mapping source sch to target pcb
// Matched Source & Target have the same index



                for K := 0 to (PrjMapping.DM_MatchedComponentCount - 1) do
                begin
                    if PrjMapping.DM_MatchedSourceComponent(K).DM_UniqueId = Comp.DM_UniqueId then
                    begin
                        TargetComp := PrjMapping.DM_MatchedTargetComponent(K);
                        CompImpl := Comp.DM_CurrentImplementation(cDocKind_PcbLib);
                        TargetImpl := TargetComp.DM_CurrentImplementation(cDocKind_PcbLib);
                        PrjReport.Add(' Mapping Target : ' + IntToStr(K) + ' | Des: ' + TargetComp.DM_FullLogicalDesignatorForDisplay);
                        TargetImpl.DM_DatafileCount ;
                        CompImpl.DM_DatafileCount;

                        if CompImpl.DM_ModelName <> TargetImpl.DM_ModelName then
                            PrjReport.Add('Not matching Source-Target FP ModelNames');
                                                                              // TargetComp.DM_DatafileLibId DNEX
                        if Comp.DM_SourceLibraryName <> TargetComp.DM_SourceLibraryName then
//                        if CompImpl.DM_D <> TargetComp.DM_SourceLibraryName  then
                            PrjReport.Add(' mismatched FP model libs : ' + Comp.DM_SourceLibraryName + '  ' + TargetComp.DM_SourceLibraryName );

                    end;
                end;  // k prjmapping
{
                for K := 0 to (Comp.DM_ImplementationCount - 1) do
                begin
                    CompImpl := Comp.DM_Implementations(K);
                    if (CompImpl.DM_ModelType = cDocKind_PcbLib) and CompImpl.DM_IsCurrent then
                    begin
                    //  GetMatchCompInPCB
                       Iterator := Board.BoardIterator_Create;
                       Iterator.AddFilter_ObjectSet(MkSet(eComponentObject));
                       Iterator.AddFilter_IPCB_LayerSet(MkSet(eTopLayer,eBottomLayer));
                       Iterator.AddFilter_Method(eProcessAll);

                       PCBComp := Iterator.FirstPCBObject;

                       While (PCBComp <> Nil) Do
                       Begin
                           if  Comp.DM_UniqueId = PCBComp.SourceUniqueID then
                           begin
                               PrjReport.Add('found matching component');
                               if CompImpl.DM_ModelName = PCBComp.Pattern then
                                   PrjReport.Add('found matching FP ModelName')
                               else
                                   PrjReport.Add('No matching FP ModelName found!');
                               if PCBComp.SourceFootprintLibrary <> PCBComp.SourceComponentLibrary then
                                   PrjReport.Add(' ----------- Footprint Warning check  : '  + PCBComp.Pattern + '  -----------');
                           end;
                           PCBComp := Iterator.NextPCBObject;
                       End;

                       Board.BoardIterator_Destroy(Iterator);

                    end;

                end;  // k implementations
}

//   report component level parameters
                for K := 0 to (Comp.DM_ParameterCount - 1) do
                begin
                    Param := Comp.DM_Parameters(K);
                    PrjReport.Add(Param.DM_Name + ' ' + Param.DM_Value); // + ' ' + Param.DM_Description);
                end;

                PrjReport.Add('');
            end;  // j dm_components


            PrjReport.Add('');
                TotSLinkCount := TotSLinkCount + SLinkCount;
                TotFLinkCount := TotFLinkCount + FLinkCount;
        end;
    End;  // i physical docs.

// report project level parameters
    for I := 0 to Prj.DM_ParameterCount - 1 Do
    begin
        Param := Prj.DM_Parameters(I);
        PrjReport.Add(Param.DM_Name + ' ' + Param.DM_Value + ' ' + Param.DM_Description);
        Param.DM_ConfigurationName;
        Param.DM_Kind;
        Param.DM_RawText;

        Param.DM_OriginalOwner;
        Param.DM_Visible;
    end; // i prj parameters

    PrjReport.Insert(2, 'Total Missing Sch Symbol Link Count : ' + IntToStr(TotSLinkCount));
    PrjReport.Insert(3, 'Total Missing Footprint Link Count  : ' + IntToStr(TotFLinkCount));
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



{..............................................................................}
// Function DM_UnmatchedSourceComponent(Index : Integer) : IComponent;  Returns the indexed unmatched source component, that is, a target component could not be found to map to this source component. Use the DM_UnmatchedSourceComponentCount function.
// Function DM_UnmatchedTargetComponent(Index : Integer) : IComponent;  Returns the indexed unmatched target component, that is, a source component could not be found to map to the target component. Use the DM_UnmatchedTargetComponentCount function.
// Function DM_MatchedComponentCount: Integer;  Returns the number of matched components.
// Function DM_MatchedSourceComponent  (Index : Integer) : IComponent;  Returns the indexed matched source component (that has been matched with a target component). Use the DM_MatchedSourceComponentCount function.
// Function DM_MatchedTargetComponent  (Index : Integer) : IComponent;  Returns the indexed matched source component (that has been matched with a target component). Use the DM_MatchedTargetComponentCount function.

