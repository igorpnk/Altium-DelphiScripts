{..............................................................................
 Summary 
         PCB Doc focused component parameter dumper

B. Miller
13/01/2020  v0.01   initial POC
14/01/2020  v0.11   cruft removal

                                         
..............................................................................}

Var
    WS         : IWorkspace;
    Doc        : IDocument;
    Prj        : IBoardProject;
    Board      : IPCB_Board;
    Param      : IParameter;
    PrjReport  : TStringList;
    PCBList    : TStringList;
    FilePath   : WideString;
    FileName   : WideString;


{..............................................................................}

Procedure ReportCompParameters;
var
    PCBComp        : IPCB_Component;
    Iterator       : IPCB_BoardIterator;
    ParamReport    : TStringList;

    ReportDocument : IServerDocument;
    PrimDoc        : IDocument;

    Comp           : IComponent;
    I, J, K, L     : Integer;

Begin
    WS  := GetWorkspace;
    If WS = Nil Then Exit;

    WS.DM_ProjectCount;

    Prj := WS.DM_FocusedProject;
//    If Prj = Nil Then Exit;

//    Prj.DM_Compile;


//    PrimDoc := Prj.DM_PrimaryImplementationDocument;
    Doc := WS.DM_FocusedDocument;
    If (Doc.DM_DocumentKind <> cDocKind_Pcb) Then exit;

// required for the Board interface iterating eCompObject
    If PCBServer = Nil then Client.StartServer('PCB');
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then
    Board := PCBServer.GetPCBBoardByPath(Doc.DM_FullPath);
    If Board = Nil Then
        Board := PCBServer.LoadPCBBoardByPath(Doc.DM_FullPath);
    if Board = Nil then Exit;


    BeginHourGlass(crHourGlass);

    // Get current document.

//   CurrentSch := SchServer.GetSchDocumentByPath(Doc.DM_FullPath);

    PrjReport  := TStringList.Create;

    if Prj <> Nil then
    begin
        PrjReport.Add('Project Footprint Model information:');
        PrjReport.Add('  Project: ' + Prj.DM_ProjectFileName);
        PrjReport.Add('');
    end;

    PrjReport.Add('');

//    For I := 0 to (Prj.DM_PhysicalDocumentCount - 1) Do
//    Begin
//        Doc := Prj.DM_PhysicalDocuments(I);

    If Doc.DM_DocumentKind = cDocKind_Pcb Then
    begin
//        without this the DM_ComponentCount = 0 !! 
            Doc.DM_Compile;

            PrjReport.Add('');
            PrjReport.Add('  Board  : ' + Doc.DM_FileName);
            PrjReport.Add('');

            for J := 0 to Doc.DM_ComponentCount - 1 Do
            begin
                Comp := Doc.DM_Components(J);

                PrjReport.Add(' Component LogDes : ' + Comp.DM_LogicalDesignator + '  | PhysDes: ' + Comp.DM_PhysicalDesignator + '  | CalcDes: ' + Comp.DM_CalculatedDesignator);
                PrjReport.Add(' Lib Reference    : ' + Comp.DM_LibraryReference);
                PrjReport.Add(' Comp FootPrint   : ' + Comp.DM_FootPrint);
                PrjReport.Add(' Current FP Model : ' + Comp.DM_CurrentImplementation(cDocKind_PcbLib).DM_ModelName + '  ModelType :' + Comp.DM_CurrentImplementation(cDocKind_PcbLib).DM_ModelType);


//   report component level parameters
                for K := 0 to (Comp.DM_ParameterCount - 1) do
                begin
                    Param := Comp.DM_Parameters(K);
                    PrjReport.Add(Param.DM_Name + ' ' + Param.DM_Value); // + ' ' + Param.DM_Description);
                end;

                PrjReport.Add('');
            end;  // j dm_components


        PrjReport.Add('');
    end;

// report project level parameters
    for I := 0 to (Prj.DM_ParameterCount - 1) Do
    begin
        Param := Prj.DM_Parameters(I);
        PrjReport.Add(Param.DM_Name + ' ' + Param.DM_Value + ' ' + Param.DM_Description);
        Param.DM_ConfigurationName;
        Param.DM_Kind;
        Param.DM_RawText;

        Param.DM_OriginalOwner;
        Param.DM_Visible;
    end; // i prj parameters

    PrjReport.Add('===========  EOF  ==================================');


    FilePath := ExtractFilePath(Doc.DM_FullPath);
    FileName := FilePath + ExtractFileName(Doc.DM_FileName) + '_ReportPcbDocParas.Txt';
    PrjReport.SaveToFile(FileName);

    EndHourGlass;

    WS := GetWorkspace;
    //Prj.DM_AddSourceDocument(FileName);
    ReportDocument := Client.OpenDocument('Text', FileName);
    If ReportDocument <> Nil Then
        Client.ShowDocument(ReportDocument);

End;

