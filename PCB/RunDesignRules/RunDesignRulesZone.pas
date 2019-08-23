{ RunDesignRulesZone.pas
  DocKind: PcbDoc
  Summary: Two call methods, object & rectangular area
  Method:  Interate the rules in board over an object collection
           Generate DRCmarkers & log file.

Author: BL Miller
19/08/2019 : first cut POC
20/08/2019 : implemented choose rectange & got DRCmarkers to display.
21/08/2019 : binary rule loop iterating was creating duplicate violations.

tbd: problems with violation descriptions
}

const
    cESC      = -1;
    cAllRules = -1;

var
    Board          : IPCB_Board;
    Rpt            : TStringList;
    FileName       : TPCB_String;
    Document       : IServerDocument;
    Prim1          : IPCB_Primitive;
    Prim2          : IPCB_Primitive;

function RuleKindToString (const ARuleKind : TRuleKind) : String;
// more failings of API
begin
    Result := '';
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
        eRule_UnconnectedPin           : Result := 'UnConnectedPin';
        eRule_SMDToPlane               : Result := 'SMDToPlane';
        eRule_SMDNeckDown              : Result := 'SMDNeckDown';
        eRule_LayerPair                : Result := 'LayerPairs';
        eRule_FanoutControl            : Result := 'FanoutControl';
        eRule_MaxMinHeight             : Result := 'Height';
        eRule_DifferentialPairsRouting : Result := 'DiffPairsRouting';
    end;
end;

function MaxGapFromRules(Board : IPCB_Board) : single;
var
    Iterator   : IPCB_BoardIterator;
    Rule       : IPCB_Rule;
begin
    Result := 0;
    //Determine MaxWidth to help narrow area of focus
    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eRuleObject));
    Iterator.AddFilter_LayerSet(AllLayers);
    Iterator.AddFilter_Method(eProcessAll);
    Rule := Iterator.FirstPCBObject;
    while (Rule <> Nil) do
    begin
        if (Rule.RuleKind = eRule_Clearance) and Rule.Enabled then
            Result := Max(Result, Rule.Gap);
        Rule := Iterator.NextPCBObject;
    end;
    Board.BoardIterator_Destroy(Iterator);
end;

function GetRulesFromBoard (const Board : IPCB_Board, const RuleKind : TRuleKind) : TObjectList;
var
    Iterator : IPCB_BoardIterator;
    Rule     : IPCB_Rule;
begin
    Result := TObjectList.Create;

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eRuleObject));
    Iterator.AddFilter_LayerSet(AllLayers);
    Iterator.AddFilter_Method(eProcessAll);
    Rule := Iterator.FirstPCBObject;
    while (Rule <> Nil) do
    begin
        if RuleKind = cAllRules then
            Result.Add(Rule)
        else
            if Rule.RuleKind = RuleKind then Result.Add(Rule);

        Rule := Iterator.NextPCBObject;
    end;
    Board.BoardIterator_Destroy(Iterator);
end;

procedure ShowViolations(x1, y1, x2, y2 : TCoord);
var
    SIterator  : IPCB_SpatialIterator;
    Iterator   : IPCB_BoardIterator;
    Rule       : IPCB_Rule;
    RuleKind   : TRuleKind;
    RulesList  : TObjectList;
    Primitives : TObjectList;
    Violation  : IPCB_Violation;
    ViolDesc   : WideString;
//    BR         : TCoordRect;
    I, J, K    : integer;

begin
    BeginHourGlass(crHourGlass);

    Rpt        := TStringList.Create;
    Primitives := TObjectList.Create;
    RulesList  := TObjectList.Create;

// collection of all primitive objects at cursor.
    SIterator := Board.SpatialIterator_Create;
    SIterator.AddFilter_IPCB_LayerSet(AllLayers);
    SIterator.AddFilter_ObjectSet(AllPrimitives);
    SIterator.AddFilter_Area(x1, y1, x2, y2);

    Prim2 := SIterator.FirstPCBObject;
    while Prim2 <> Nil do
    begin
        if Primitives.IndexOf(Prim2) = -1 then
        begin
            Primitives.Add(Prim2);
            Rpt.Add('prim : ' + Prim2.ObjectIDString + '  layer : ' + IntToStr(Prim2.Layer));
        end;
        if Prim2.InNet then
            if Primitives.IndexOf(Prim2.Net) = -1 then
            begin
                Primitives.Add(Prim2.Net);
                Rpt.Add('prim : ' + Prim2.Net.ObjectIDString + '  net : ' + Prim2.Net.Name + '  layer : ' + IntToStr(Prim2.Layer));
            end;
        Prim2 := SIterator.NextPCBObject;
    end;
    Board.SpatialIterator_Destroy(SIterator);
    Prim2 := Prim1;

    RulesList := GetRulesfromBoard(Board, cAllRules);

    // clear existing violations
    Client.SendMessage('PCB:ResetAllErrorMarkers', '', 255, Client.CurrentView);
    Rpt.Add('');
    Rpt.Add('Cleared existing DRC markers');
    Rpt.Add('');
    Rpt.Add('   prim1:    prim2:       Violation Name:         Desc.:                  RuleName:     RuleType: ');

    for K := 0 to (RulesList.Count - 1) do
    begin
        Rule := RulesList.Items(K);
        for I := 0 to (Primitives.Count - 1) do
        begin
            Prim1 := Primitives.Items(I);
            //Rule := Board.FindDominantRuleForObject(Prim1, RuleKind);
            if Rule.IsUnary and Rule.Enabled then
            begin
                Rule.CheckUnaryScope(Prim1);
                Rule.Scope1Includes(Prim1);
                Violation := Rule.ActualCheck(Prim1, nil);
                if Violation <> nil then
                begin
                    Board.AddPCBObject(Violation);
                    ViolDesc := Copy(Violation.Description, 0, 60);
                    //Setlength(ViolDesc,40);
                    Rpt.Add('U  ' + PadRight(Prim1.ObjectIDString, 10) + '            ' + PadRight(Violation.Name, 20) + ' '
                            + PadRight(ViolDesc, 60) + '   ' + Rule.Name + ' ' + RuleKindToString(Rule.RuleKind));

                    Prim1.SetState_DRCError(true);
                    Prim1.GraphicallyInvalidate;
                end;
            end;

            for J := (I + 1) to (Primitives.Count - 1) do
            begin
                Prim2 := Primitives.Items(J);
                //Rule := Board.FindDominantRuleForObjectPair(Prim1, Prim2, RuleKind);
                if (not Rule.IsUnary) and Rule.Enabled then
                begin
//                  Rule.CheckBinaryScope(Prim1, Prim2);
//                  Rule.Scope2Includes(Prim2);
                // Violation := PCBServer.PCBObjectFactory(eViolationObject, eNoDimension, eCreate_Default);
                    Violation := Rule.ActualCheck(Prim1, Prim2);
                    if Violation <> nil then
                    begin
                        Board.AddPCBObject(Violation);
                        ViolDesc := Copy(Violation.Description, 0, 60;
                        //SetLength(ViolDesc,40);
                        Rpt.Add('B  '+ PadRight(Prim1.ObjectIDString, 10) + ' ' + PadRight(Prim2.ObjectIDString, 10) + ' ' + PadRight(Violation.Name, 20)
                                + ' ' + PadRight(ViolDesc, 60) + '   ' + Rule.Name + ' ' + RuleKindToString(Rule.RuleKind));
                        Prim1.SetState_DRCError(true);
                        Prim2.SetState_DRCError(true);
                        Prim1.GraphicallyInvalidate;
                        Prim2.GraphicallyInvalidate;
                    end;
                end;
            end;  // J
        end;   // I
    end;

    Primitives.Destroy;
    RulesList.Destroy;

    EndHourGlass;
    Board.ViewManager_FullUpdate;
    Client.SendMessage('PCB:Zoom', 'Action=Redraw' , 255, Client.CurrentView);

    Rpt.Insert(0,'Rule Violations for Selected Object' + ExtractFileName(Board.FileName) + ' document.');
    Rpt.Insert(1,'----------------------------------------------------------');
    Rpt.Insert(2,'');

    // Display the Rules report
    FileName := ExtractFilePath(Board.FileName) + ChangefileExt(ExtractFileName(Board.FileName),'') + '-ObjViolateReport.txt';
    Rpt.SaveToFile(Filename);
    Rpt.Free;

    Document  := Client.OpenDocument('Text', FileName);
    if Document <> Nil Then
    begin
        Client.ShowDocument(Document);
        if (Document.GetIsShown <> 0 ) then
            Document.DoFileLoad;
    end;
end;

procedure ShowViolationsArea;
var
    x, y      : TCoord;
    x2, y2    : TCoord;

begin
    Board := PCBServer.GetCurrentPCBBoard;
    if Board = Nil then exit;

    if Board.ChooseRectangleByCorners('Zone First Corner','Zone Opposite Corner',x,y,x2,y2) then
        ShowViolations(x, y, x2, y2);
end;

procedure ShowViolationsObject;
var
    SetObjects : TSet;
    x, y       : TCoord;
    MaxGap     : single;
    msg        : WideString;

begin
    Board := PCBServer.GetCurrentPCBBoard;
    if Board = Nil then exit;

    SetObjects := MkSet(eComponentObject, eTrackObject, ePadObject, eViaObject, eTextObject, ePolyObject, eRegionObject);
    Prim1 := nil;

    if Board.GetState_SelectecObjectCount > 0 then
        Prim1 := Board.SelectecObject(0);
        x := Prim1.X;
        y := prim1.Y;
    if not InSet(Prim1.ObjectId, SetObjects) then Prim1 := nil;

    msg := 'Select Object for Rules Checking';
    While not (Prim1 <> Nil) do
    begin
        if Board.ChooseLocation(x, y, msg) then  // false = ESC Key is pressed
        begin
            Prim1 := Board.GetObjectAtXYAskUserIfAmbiguous(x, y, SetObjects, AllLayers, eEditAction_Select);
        end
        else Prim1 := cESC;
    end;

    if (Prim1 <> cESC) and (Prim1 <> eNoObject) then
    begin
        MaxGap := MaxGapfromRules(Board);
        MaxGap := MaxGap * 1.05;
        ShowViolations(x - MaxGap, y + MaxGap, x + MaxGap, y - MaxGap);
     end;
end;

