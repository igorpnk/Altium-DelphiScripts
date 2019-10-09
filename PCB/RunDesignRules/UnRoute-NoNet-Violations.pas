{ UnRoute-NoNet-Violations.pas
  Reports NoNets & UnRouted Nets by Pad designators

  To Use:
  Run the DRC or just the UnRoutedNets rule in PCB Rules & violations panel.
  Or can Run the defined Rule check & report..
  DRCReport: reports the existing DRC state from board.
  DRCViolateNoRoute: Runs rule defined "RuleToRunRC" ; only unary rules supported.

B.L. Miller
03/08/2019 v0.1  POC hack
04/08/2019 v0.2  Additional reporting of Pads with NoNet.
07/08/2019 v0.3  Two script call entry points DRCReport & DRCViolateNoRoute
21/08/2019 v0.31 Tidied reporting some.. added DRC marker code still DNW!
26/08/2019 v0.32 Added all associated Nets to Scoped Objects.
25/09/2019 v0.33 Allow for multiple Rules of same rulekind
10/10/2029 v0.34 Add green DRC dots to terminating pads without duplicating violations

Displays yellow parallel bars for broken Nets & green DRC dots on pad ends of Nets

}
const
    RuleToRunRC  = eRule_BrokenNets;     // only one tested/attempted.
    RuleToReport = eRule_BrokenNets;
    cAllRules    = -1;
    ErrorCountPrompt = 50;

var
    Board     : IPCB_Board;
    Rpt       : TStringList;
    dlgResult : boolean;   // integer for cancel version FFS

function RuleKindToString (ARuleKind : TRuleKind) : String;
// more failings of API
begin
//    Result := cRuleIdStrings[ARuleKind];
    case ARuleKind of
        eRule_Clearance                : Result := 'Clearance';
        eRule_ParallelSegment          : Result := 'ParallelSegment';
        eRule_MaxMinWidth              : Result := 'Width';
        eRule_MaxMinLength             : Result := 'Length';
        eRule_MatchedLengths           : Result := 'MatchedLengths';
        eRule_DaisyChainStubLength     : Result := 'StubLength';
        eRule_PowerPlaneConnectStyle   : Result := 'PlaneConnect';
        eRule_RoutingTopology          : Result := 'RoutingTopology';
        eRule_RoutingPriority          : Result := 'RoutingPriority';
        eRule_RoutingLayers            : Result := 'RoutingLayers';
        eRule_RoutingCornerStyle       : Result := 'RoutingCorners';
        eRule_RoutingViaStyle          : Result := 'RoutingVias';
        eRule_PowerPlaneClearance      : Result := 'PlaneClearance';
        eRule_SolderMaskExpansion      : Result := 'SolderMaskExpansion';
        eRule_PasteMaskExpansion       : Result := 'PasteMaskExpansion';
        eRule_ShortCircuit             : Result := 'ShortCircuit';
        eRule_BrokenNets               : Result := 'UnRoutedNet';
        eRule_ViasUnderSMD             : Result := 'ViasUnderSMD';
        eRule_MaximumViaCount          : Result := 'MaximumViaCount';
        eRule_MinimumAnnularRing       : Result := 'MinimumAnnularRing';
        eRule_PolygonConnectStyle      : Result := 'PolygonConnect';
        eRule_AcuteAngle               : Result := 'AcuteAngle';
        eRule_ConfinementConstraint    : Result := 'RoomDefinition';
        eRule_SMDToCorner              : Result := 'SMDToCorner';
        eRule_ComponentClearance       : Result := 'ComponentClearance';
        eRule_ComponentRotations       : Result := 'ComponentOrientations';
        eRule_PermittedLayers          : Result := 'PermittedLayers';
        eRule_NetsToIgnore             : Result := 'NetsToIgnore';
        eRule_SignalStimulus           : Result := 'SignalStimulus';
        eRule_Overshoot_FallingEdge    : Result := 'OvershootFalling';
        eRule_Overshoot_RisingEdge     : Result := 'OvershootRising';
        eRule_Undershoot_FallingEdge   : Result := 'UndershootFalling';
        eRule_Undershoot_RisingEdge    : Result := 'UndershootRising';
        eRule_MaxMinImpedance          : Result := 'MaxMinImpedance';
        eRule_SignalTopValue           : Result := 'SignalTopValue';
        eRule_SignalBaseValue          : Result := 'SignalBaseValue';
        eRule_FlightTime_RisingEdge    : Result := 'FlightTimeRising';
        eRule_FlightTime_FallingEdge   : Result := 'FlightTimeFalling';
        eRule_LayerStack               : Result := 'LayerStack';
        eRule_MaxSlope_RisingEdge      : Result := 'SlopeRising';
        eRule_MaxSlope_FallingEdge     : Result := 'SlopeFalling';
        eRule_SupplyNets               : Result := 'SupplyNets';
        eRule_MaxMinHoleSize           : Result := 'HoleSize';
        eRule_TestPointStyle           : Result := 'Testpoint';
        eRule_TestPointUsage           : Result := 'TestPointUsage';
        eRule_UnconnectedPin           : Result := 'UnConnected Pin';
        eRule_SMDToPlane               : Result := 'SMD to Plane';
        eRule_SMDNeckDown              : Result := 'SMD NeckDown';
        eRule_LayerPair                : Result := 'Layer Pairs';
        eRule_FanoutControl            : Result := 'Fanout Control';
        eRule_MaxMinHeight             : Result := 'Height';
        eRule_DifferentialPairsRouting  : Result := 'Diff Pairs Routing';
        eRule_HoleToHoleClearance       : Result := 'Hoe to Hole Clearance';
        eRule_MinimumSolderMaskSliver   : Result := 'Minimum SolderMask Sliver';
        eRule_SilkToSolderMaskClearance : Result := 'Silk to SolderMask Clearance';
        eRule_SilkToSilkClearance       : Result := 'Silk to Silk Clearance';
        eRule_NetAntennae               : Result := 'Net Antennae';
        eRule_AssyTestPointStyle        : Result := 'Assy TestPoint Style';
        eRule_AssyTestPointUsage        : Result := 'Assy TestPoint Usage';
        eRule_SilkToBoardRegion         : Result := 'Silk To Board Region';
        eRule_SMDPADEntry               : Result := 'SMD Pad Entry';
        eRule_None                      : Result := 'NO Rule';
        eRule_ModifiedPolygon           : Result := 'Modified Polygon';
        eRule_BoardOutlineClearance     : Result := 'Board Outline Clearance';
        eRule_BackDrilling              : Result := 'Back Drilling';
    else Result := '';
    End;
End;

function GetMatchingRulesFromBoard (const RuleKind : TRuleKind) : TObjectList;
var
    Iterator : IPCB_BoardIterator;
    Rule     : IPCB_Rule;
begin
    Result := TObjectList.Create;;

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eRuleObject));
    Iterator.AddFilter_LayerSet(AllLayers);
    Iterator.AddFilter_Method(eProcessAll);
    Rule := Iterator.FirstPCBObject;
    while (Rule <> Nil) Do
    begin
        if RuleKind = cAllRules then
            Result.Add(Rule)
        else
            if Rule.RuleKind = RuleKind then Result.Add(Rule);

        Rule := Iterator.NextPCBObject;
    end;
    Board.BoardIterator_Destroy(Iterator);
end;

function GetScopedObjects (Rule : IPCB_Rule, const scope : integer) : TObjectList;
var
    Iterator      : IPCB_BoardIterator;
    Prim          : IPCB_Primitive;
    Net           : IPCB_net;
    ScopeIncludes : boolean;

begin
    Result := TObjectList.Create;

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(AllPrimitives);
    Iterator.AddFilter_LayerSet(AllLayers);
    Iterator.AddFilter_Method(eProcessAll);
    Prim := Iterator.FirstPCBObject;
    While (Prim <> Nil) Do
    Begin
        ScopeIncludes := false;
        if scope = 1 then
        begin
            if Rule.Scope1Includes(Prim) then ScopeIncludes := true;
//      easier to retain pin/pad now so can display DRC markers on pads!
            if (Prim.ObjectId <> eNetObject) and Prim.InNet then
            begin
                Net := Prim.Net;
                if Rule.Scope1Includes(Net) then ScopeIncludes := true;
            end;
        end;
        if scope = 2 then
        begin
            if Rule.Scope2Includes(Prim) then ScopeIncludes := true;
            if (Prim.ObjectId <> eNetObject) and Prim.InNet then
            begin
                Net := Prim.Net;
                if Rule.Scope2Includes(Net) then ScopeIncludes := true;
            end;
        end;

        if ScopeIncludes then
            if Result.IndexOf(Prim) = -1 then
                Result.Add(Prim);

  //  add Net in rule runner so have the pin handle.
  //          if (Prim.ObjectId <> eNetObject) and Prim.InNet then
  //          begin
  //              Prim := Prim.Net;
  //              ScopeIncludes := true;
  //          end;

        Prim := Iterator.NextPCBObject;
    End;
    Board.BoardIterator_Destroy(Iterator);
end;

procedure CheckUnaryViolation (Rule : IPCB_Rule, ScopeList : TObjectList);
var
    RuleKind    : TRuleKind;
    Prim, Prim2 : IPCB_Primitive;
    Violation   : IPCB_Violation;
    ViolDesc    : WideString;
    ViolName    : WideString;
    txt         : WideString;
    I, J          : integer;
    VCount        : integer;
    GetOutOfLoops : boolean;
    Redos         : integer;
    Done          : boolean;
begin
    VCount := 0;
    RuleKind := Rule.RuleKind;

    for I := 0 to (ScopeList.Count - 1) do
    begin
        Prim := ScopeList.Items(I);
        Prim2 := Prim;
        Redos := 1;
        repeat
            Violation := nil;
            if Rule.CheckUnaryScope (Prim2) then
                Violation := Rule.ActualCheck (Prim2, nil);
            if Violation <> nil then
            begin
// want to DRC error mark each Net pad end but not make extra violations.
                if Prim = Prim2 then
                begin
                    inc(VCount);
                    Board.AddPCBObject(Violation);
                    Rule.Descriptor;
                    Violation.Detail;
                    ViolDesc := Violation.Description;
                    ViolDesc := Copy(ViolDesc, 0, 60);
                    ViolDesc := PadRight(ViolDesc, 60);
                    ViolName := Violation.Name;
                    Rpt.Add('U ' + IntToStr(VCount) + ' ' + PadRight(Prim2.ObjectIDString, 15) + '            ' + PadRight(ViolName, 20) + ' '
                            + ViolDesc + '   ' + Rule.Name + ' ' + RuleKindToString(RuleKind));
                end;
                Prim.SetState_DRCError(true);
                Prim.GraphicallyInvalidate;
            end;

            dec(Redos);
            if (Prim2.ObjectId <> eNetObject) and Prim.InNet then
            begin
//                Rule.NetScope;   //      eNetScope_DifferentNetsOnly=0
                inc(Redos);
                Prim2 := Prim.Net;
            end;
        until (Redos < 1);

        if (VCount > 0) and ((VCount mod ErrorCountPrompt) = 0) then
        begin
            dlgResult := ConfirmNoYesWithCaption('Lots of Violations (' + IntToStr(VCount) + ') ', 'Continue ? ');
            BeginHourGlass(crHourGlass);
            if not dlgresult then GetOutOfLoops := true;
        end;
        if GetOutOfLoops then break;

    end;
    Rpt.Add(' Total Unary Rule Violation Count : ' + IntToStr(VCount));
end;

procedure CheckBinaryViolation (Rule : IPCB_Rule, Scope1List, Scope2List : TObjectList);
var
    RuleKind    : TRuleKind;
    Prim, Prim2 : IPCB_Primitive;
    Violation   : IPCB_Violation;
    I, J        : integer;
    VCount      : integer;

begin
    VCount := 0;
    RuleKind := Rule.RuleKind;

    for I := 0 to (Scope1List.Count - 1) do
    begin
        Prim := Scope1List.Items[I];
        for J := 0 to (Scope2List.Count - 1) do
        begin
            Prim2 := Scope2List.Items[J];
            // Rule := Board.FindDominantRuleForObjectPair(Prim1, Prim2, RuleKind);
            Violation := nil;
            if Rule.CheckBinaryScope (Prim, Prim2) then
                Violation := Rule.ActualCheck (Prim, Prim2);
            if Violation <> nil then
            begin
                ViolDesc := Violation.Description;
                ViolDesc := Copy(ViolDesc, 0, 60);
                ViolDesc := PadRight(ViolDesc, 60);
                ViolName := Violation.Name;
                inc(VCount);
                Board.AddPCBObject(Violation);
                Prim.SetState_DRCError(true);
                Prim2.SetState_DRCError(true);
                Prim.GraphicallyInvalidate;
                Prim2.GraphicallyInvalidate;
            end;
        end;
    end;
    Rpt.Add(' Total Binary Rule Violation Count : ' + IntToStr(VCount));
end;

procedure DRCReporter(Rpt : TStringList);
var
    Iterator  : IPCB_BoardIterator;
    Violation : IPCB_Violation;
    ViolDesc  : WideString;
    ViolName  : WideString;
    VioRptTxt : WideString;
    Rule      : IPCB_Rule;
    PCBObj1   : IPCB_Primitive;
    PCBObj2   : IPCB_Primitive;
    Pad       : IPCB_Pad;
    PinDesc   : WideString;
    FileName  : TPCB_String;
    Document  : IServerDocument;
    VCount    : integer;

begin
    Rpt.Add('');
    Rpt.Add(' Pad Object Violations');
    VCount := 0;

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eViolationObject));
    Iterator.AddFilter_LayerSet(AllLayers);
    Iterator.AddFilter_Method(eProcessAll);

    Rpt.Add('cnt  Obj1 Pad:         Obj2 Pad:          Violation Descripton  &  Name:      Rule Name:   RuleType: ');

    Violation := Iterator.FirstPCBObject;
    While Violation <> Nil Do
    Begin
//Get design rule associated with the current violation object
        Rule    := Violation.Rule;

        PCBObj1 := Violation.Primitive1;
        PCBObj2 := Violation.Primitive2;
        VioRptTxt := '';

        if Rule <> Nil then
        begin
            if Rule.ObjectID = RuleToReport then
            begin
               if PCBObj1.ObjectID = ePadObject then
                begin
                    inc(VCount);
                    Pad := PCBObj1;
                    PinDesc := Pad.PinDescriptor;
                    VioRptTxt := PadRight(IntToStr(VCount), 3) + ' ' + PadRight(PinDesc, 20) + ' ';
                end;

                if PCBObj2 <> Nil then
                begin
                    if PCBObj2.ObjectID = ePadObject then
                    begin
                        // inc(VCount);
                        Pad := PCBObj2;
                        PinDesc := Pad.PinDescriptor;
                        If VioRptTxt = '' then
                            VioRptTxt := PadRight(IntToStr(VCount), 3) + ' ' + PadRight(PinDesc, 20) + '            '
                        else
                            VioRptTxt := VioRptTxt + PadRight(PinDesc, 20) + ' ';
                    end;
                end;
                if VioRptTxt <> '' then
                begin
                    ViolDesc := Violation.Description;
                    ViolDesc := Copy(ViolDesc, 0, 60);
                    ViolDesc := PadRight(ViolDesc, 60);
                    ViolName := Violation.Name;
                    VioRptTxt := VioRptTxt + PadRight(ViolName, 20) + ' ' + ViolDesc + '  ' + Rule.Name + '  ' + RuleKindToString(Rule.RuleKind);
                    Rpt.Add(VioRptTxt);
                end;
            end;
        end;
        Violation := Iterator.NextPCBObject;
    end;
    Rpt.Add('');
    Rpt.Add('');

// pads with no net
    Rpt.Add('Pads with NoNet');
    Rpt.Add('');
    Rpt.Add('index   Pad Name:              Detail :  ');
    VCount := 0;

    Iterator.AddFilter_ObjectSet(MkSet(ePadObject));
    Iterator.AddFilter_LayerSet(SignalLayers);
    Iterator.AddFilter_Method(eProcessAll);
    Pad := Iterator.FirstPCBObject;
    While Pad <> Nil Do
    Begin
        if Pad.Net = Nil then
        begin
            inc(VCount);
            PinDesc := Pad.PinDescriptor;
            Rpt.Add(PadRight(IntToStr(VCount), 4) + ' ' + PadRight(PinDesc, 20) + '  ' + Pad.Detail);
        end;
        Pad := Iterator.NextPCBObject;
    end;
    Board.BoardIterator_Destroy(Iterator);

    Rpt.Insert(0,'Violation & NoNet Pad Information for ' + ExtractFileName(Board.FileName) + ' document.');
    Rpt.Insert(1,'----------------------------------------------------------');
    Rpt.Insert(2,'');

    // Display the Rules report
    FileName := ExtractFilePath(Board.FileName) + ChangefileExt(ExtractFileName(Board.FileName),'') + '-ViolationsReport.txt';
    Rpt.SaveToFile(Filename);
    Rpt.Free;

    Document  := Client.OpenDocument('Text', FileName);
    If Document <> Nil Then
    begin
        Client.ShowDocument(Document);
        if (Document.GetIsShown <> 0 ) then
            Document.DoFileLoad;
    end;
end;

procedure DRCViolateNoRoute;
var
    Scope1List : TObjectList;
    Scope2List : TObjectList;
    RulesList  : TObjectList;  // IPCB_Rule;     //IPCB_Primitive;
    Rule       : IPCB_Rule;
    R          : integer;

begin
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;

    BeginHourGlass(crHourGlass);
    Rpt := TStringList.Create;
    Rpt.Add('Running DRC Violations Check on' + RuleKindToString(RuleToRunRC) );

    RulesList := TObjectList.Create;
//  find matching rule
    RulesList := GetMatchingRulesFromBoard(RuleToRunRC);

// clear existing violations
    if RulesList.Count > 0 then
        Client.SendMessage('PCB:ResetAllErrorMarkers', '', 255, Client.CurrentView);

    for R := 0 to (RulesList.Count - 1 ) do
    begin
        Rule := RulesList.Items(R);
        Rpt.Add('rule sub-index ' + IntToStr(R));

//  list obj scope 1 & scope2
        Rule.Scope1Expression;
        Scope1List := GetScopedObjects(Rule, 1);

//        Rule.DRCEnabled;
//        Rule := Board.FindDominantRuleForObject(Prim, RuleKind);

        if not Rule.IsUnary then       // Rule.Scope2Expression <> '' 
            Scope2List := GetScopedObjects(Rule, 2);

        if Rule.IsUnary then
            CheckUnaryViolation(Rule, Scope1List)
        else
            CheckBinaryViolation(Rule, Scope1List, Scope2List);
//            CheckNetScope(Scope1List, Scope2List);

    end;
    Board.ViewManager_FullUpdate;

    RulesList.Destroy;
    DRCReporter(Rpt);
    EndHourGlass;

    Client.SendMessage('PCB:Zoom', 'Action=Redraw' , 255, Client.CurrentView);
end;

//wrapper to call DRCReporter
procedure DRCReport;
begin
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;
    Rpt := TStringList.Create;
    DRCReporter(Rpt);
end;


// start of DMObjects violations reporter..
procedure ListViolates2(dummy : boolean);
var
    WS        : IWorkSpace;
    Prj       : IProject;
    PrimDoc   : IDocument;
    DMViolate : IViolation;
    i, j      : integer;
    PCBObj1   : IPCB_Primitive;
    PCBObj2   : IPCB_Primitive;
    Pad       : IPCB_Pad;
    Rule      : IPCB_Rule;     //IPCB_Primitive;
    FileName  : TPCBString;
    Document  : IServerDocument;
    Rpt       : TStringList;


begin
    WS := GetWorkspace;
    Prj := WS.DM_FocusedProject;
    If Prj = Nil Then exit;

    PrimDoc := Prj.DM_PrimaryImplementationDocument;
    if PrimDoc.DM_DocumentKind <> cDocKind_Pcb then exit;

    Rpt := TStringList.Create;

    for i := 0 to PrimDoc.DM_ViolationCount do
    begin
        DMViolate := DM_Violations(i);

        Rpt.Add('Violation Kind : ' + IntToStr(DMViolate.DM_ErrorKind) + ' Desc : ' + DMViolate.DM_DescriptorString + '  Detail :' + DMViolate.DM_DetailString);
        Rpt.Add(' Num Objs : ' + InttoStr(DMViolate.DM_RelatedObjectCount) );
{IViolation methods
DM_ErrorKind
DM_ErrorLevel
DM_CompilationStage
DM_AddRelatedObject
DM_RelatedObjectCount
DM_RelatedObjects
DM_DescriptorString
DM_DetailString
}
//Get design rule associated with the current violation object
   //     Rule    := Violation.Rule;
   //     PCBObj1 := Violation.Primitive1;
   //     PCBObj2 := Violation.Primitive2;

   //     If Rule <> Nil Then
        for j := 0 to (DMViolate.DM_RelatedObjectCount - 1) do
        begin

//            if Rule.ObjectID = eRule_BrokenNets then
//            begin
//                if PCBObj1.ObjectID = ePadObject then
//                begin
//                    Pad := PCBObj1;
//                    Rpt.Add('    Rule Name : ' + Rule.Name + '  RuleType : ' + RuleKindToString(Rule.RuleKind));
//                    Rpt.Add('    Obj1 Pad : ' + Pad.PinDescriptor);

                //   AddObjectToHighlightObjectList(PCBObj1);
//                end;
            Rpt.Add(IntToStr(j) + ' ');
        end;
    end;

    Rpt.Insert(0,'Violation Information for the ' + ExtractFileName(PrimDoc.FileName) + ' document.');
    Rpt.Insert(1,'----------------------------------------------------------');
    Rpt.Insert(2,'');

    // Display the Rules report
    FileName := ExtractFilePath(Board.FileName) + ChangefileExt(ExtractFileName(Board.FileName),'') + '-Violations.rep';
    Rpt.SaveToFile(Filename);
    Rpt.Free;

    Document  := Client.OpenDocument('Text', FileName);
    If Document <> Nil Then
    begin
        Client.ShowDocument(Document);
        if (Document.GetIsShown <> 0 ) then
            Document.DoFileLoad;
    end;

end;

{
Function NetScopeMatches  (P1, P2 : IPCB_Primitive) : Boolean;
Function CheckBinaryScope (P1, P2 : IPCB_Primitive) : boolean;
Function CheckUnaryScope  (P      : IPCB_Primitive) : Boolean;
Function GetState_DataSummaryString     : TPCBString;
Function GetState_ShortDescriptorString : TPCBString;
Function GetState_ScopeDescriptorString : TPCBString;
Function ActualCheck      (P1, P2 : IPCB_Primitive) : IPCB_Violation;
}

{
(IProject interface)
Function DM_ViolationCount : Integer;
Description
This function returns the number of violations reported by Altium Designer for this current project.

(IProject interface)
Function DM_Violations(Index : Integer) : IViolation;
Description
Returns the indexed violation for a current project.
This is to be used in conjunction with the DM_ViolationCount method.

IViolation methods
DM_ErrorKind
DM_ErrorLevel
DM_CompilationStage
DM_AddRelatedObject
DM_RelatedObjectCount
DM_RelatedObjects
DM_DescriptorString
DM_DetailString

Violation and Error Functions
Function GetViolationTypeInformation(ErrorKind : TErrorKind) : TViolationTypeDescription;
Function GetViolationTypeDescription(ErrorKind : TErrorKind) : TDynamicString;
Function GetViolationTypeDefaultLevel(ErrorKind : TErrorKind) : TErrorLevel;
Function GetViolationTypeGroup(ErrorKind : TErrorKind) : TErrorGroup;
Function GetErrorLevelColor(ErrorLevel : TErrorLevel) : TColor;

}

