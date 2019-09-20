{ RunDesignRulesZone.pas
  DocKind: PcbDoc
  Summary: Two call methods, object & rectangular area
  Method:  Interate the rules in board over an object collection
           Generate DRCmarkers & log file.

Author: BL Miller
19/08/2019 : first cut POC
20/08/2019 : implemented choose rectange & got DRCmarkers to display.
21/08/2019 : binary rule loop iterating was creating duplicate violations.
19/09/2019 : test only the dominant Rule of each RuleKind.
20/09/2019 : Ensure all child objects of "Group objects" i.e. component are collected.
             Confirm continue with multiples of n const violations

tbd: problems with violation descriptions

consider:
-  not using SpatialIterator (non group)
-  implementing option Inside or Touching selection rect box using modifier key(s).
}

const
    OpenReport       = true;      // not working
    FocusReport      = false;
    ErrorCountPrompt = 20;     // modulus this confirm dialog
    cESC      = -1;
    cAllRules = -1;
    cAltKey   = 1;
    cShiftKey = 2;
    cCntlKey  = 3;

var
    Board          : IPCB_Board;
    Rpt            : TStringList;
    FileName       : TPCB_String;
    Document       : IServerDocument;
    BUnits         : TUnit;
    BOrigin        : TPoint;
    Prim1          : IPCB_Primitive;
    Prim2          : IPCB_Primitive;
    KeySet         : TObjectSet;    // keyboard key modifiers <alt> <shift> <cntl>
    VCount         : integer;
    dlgResult      : boolean;   // integer for cancel version FFS

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

function MaxGapFromRules(Board : IPCB_Board, const RuleKSet : TObjectSet) : single;
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
        if InSet(Rule.RuleKind, RuleKSet) and Rule.Enabled then
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

function GetRuleKinds(RulesList : TObjectList) : TStringList;
var
    Rule     : IPCB_Rule;
    RuleKind : TRuleKind;
    I        : integer;
begin
    Result := TStringList.Create;
    Result.Sorted := true;                  // required for dupInore
    Result.Duplicates := dupIgnore;         // ignores attempt add dups IF sorted!   alt. dupAccept
    for I := 0 to (RulesList.Count - 1) do
    begin
        Rule := RulesList.Items(I);
        RuleKind := Rule.RuleKind;
//        if Result.IndexOf(RuleKind) = -1 then
        Result.Add(RuleKind);
    end;
end;

function CheckPosRectCoord(R : TCoordRect) : TCoordRect;
var
    temp   : TCoord;       // dodgy rect forms.
begin
    Result := R;
    temp := Result.Y1;
    if Result.Y2 < temp then
    begin
        Result.Y1 := Result.Y2;
        Result.Y2 := temp;
    end;
    temp := Result.X1;
    if Result.X2 < temp then
    begin
        Result.X1 := Result.X2;
        Result.X2 := temp;
    end;
end;

function GetComponentBR(Comp : IPCB_Component) : TCoordRect;
var
    temp   : TCoord;       // dodgy rect forms.
begin
    Result := RectToCoordRect(Comp.BoundingRectangleNoNameComment);      //TCoord
//    Result   := Comp.BoundingRectangleForPainting;    // inc. masks
//    Result   := Comp.BoundingRectangleForSelection;
    Result := CheckPosRectCoord(Result);
end;

procedure AddPrimAndNetToList(Prim : IPCB_Primitive, var Primitives : TObjectList); 
begin
    if Primitives.IndexOf(Prim2) = -1 then
    begin
        Primitives.Add(Prim2);
        Rpt.Add(PadRight(Prim2.ObjectIDString, 15) + StringOfChar(' ', 17) + Layer2String(Prim2.Layer));
    end;
    if Prim2.InNet then
        if Primitives.IndexOf(Prim2.Net) = -1 then
        begin
            Primitives.Add(Prim2.Net);
            Rpt.Add(PadRight(Prim2.Net.ObjectIDString,15) + ' ' + PadRight(Prim2.Net.Name, 15) + ' ' + Layer2String(Prim2.Layer));
        end;
end;

procedure ShowViolations(BR : TCoordRect);   // x1, y1, x2, y2
var
    SIterator  : IPCB_SpatialIterator;
    GIterator  : IPCB_GroupIterator;
    Rule       : IPCB_Rule;
    RuleKind   : TRuleKind;
    RKindList  : TStringList;
    RulesList  : TObjectList;
    Comp       : IPCB_Component;
    Primitives : TObjectList;
    Violation  : IPCB_Violation;
    ViolDesc   : WideString;
//    BR         : TCoordRect;
    MaxGap     : single;
    I, J, K    : integer;
    GetOutOfLoops : boolean;

begin
    BeginHourGlass(crHourGlass);
    BR := CheckPosRectCoord(BR);
    MaxGap := MaxGapfromRules(Board, MkSet(eRule_Clearance));
    MaxGap := MaxGap * 1.1;    // 10% more

//   if InSet(cShiftKey, KeySet) then
//   if (BRect.X1 < x) and (BRect.X2 > x) and  (BRect.Y1 < y) and (BRect.Y2 > y) then

    Primitives := TObjectList.Create;
    RulesList  := TObjectList.Create;

// collection of all primitive objects at cursor.
    SIterator := Board.SpatialIterator_Create;   // excludes Group (Component & dimension)!
    SIterator.AddFilter_LayerSet(AllLayers);
    SIterator.AddFilter_ObjectSet(AllPrimitives);
    SIterator.AddFilter_Area(BR.x1 - MaxGap, BR.y2 + MaxGap, BR.x2 + MaxGap, BR.y1 - MaxGap);

    Rpt.Add('X1 ' +   CoordUnitToString(BR.x1 - BOrigin.X, BUnits) + '  Y1 ' + CoordUnitToString(BR.y1 - BOrigin.Y, BUnits) +
            '  X2 ' + CoordUnitToString(BR.x2 - BOrigin.X, BUnits) + '  Y2 ' + CoordUnitToString(BR.y2 - BOrigin.Y, BUnits) );
    Rpt.Add('');
    Rpt.Add('Selected Objects for Design Rule Checking');
    Rpt.Add('prim objId     |  net name    |  layer ');

    Prim2 := SIterator.FirstPCBObject;
    while Prim2 <> Nil do
    begin
        Comp := Prim2.Component;    // if in Component then add all the child objects.
        if Comp <> Nil then
        begin
            GIterator := Comp.GroupIterator_Create;
            GIterator.AddFilter_LayerSet(AllLayers);
            GIterator.AddFilter_ObjectSet(MkSet(eTrackObject, eArcObject, ePadObject, eViaObject, eTextObject, eRegionObject, eFillObject));
            Prim1 := GIterator.FirstPCBObject;
            while Prim1 <> Nil do
            begin
                AddPrimAndNetToList(Prim1, Primitives);
                Prim1 := GIterator.NextPCBObject;
            end;
            Comp.GroupIterator_Destroy(GIterator);
        end;

        AddPrimAndNetToList(Prim2, Primitives);
        Prim2 := SIterator.NextPCBObject;
    end;
    Board.SpatialIterator_Destroy(SIterator);

    RulesList := GetRulesfromBoard(Board, cAllRules);
    RKindList := GetRuleKinds(RulesList);
    Rpt.Add('');
//    Rpt.Add('Existing DRC markers cleared');
//    Rpt.Add('');
    Rpt.Add('Violations from Design Rule Checking');
    Rpt.Add('   prim1:    prim2:       Violation Name:         Desc.:                  RuleName:              RuleType: ');

    VCount := 0;
    GetOutOfLoops := false;

    for K := 0 to (RKindList.Count - 1) do
    begin
        RuleKind := RKindList.Strings(K);
        for I := 0 to (Primitives.Count - 1) do
        begin
            Prim1 := Primitives.Items(I);
            Rule := Board.FindDominantRuleForObject(Prim1, RuleKind);
            if Rule <> nil then
            if Rule.IsUnary and Rule.Enabled then
            begin
//                Rule.CheckUnaryScope(Prim1);
//                Rule.Scope1Includes(Prim1);
                Violation := Rule.ActualCheck(Prim1, nil);
                if Violation <> nil then
                begin
                    Board.AddPCBObject(Violation);
                    ViolDesc := Violation.Description;
                    ViolDesc := Copy(ViolDesc, 0, 60);
                    //Setlength(ViolDesc,40);
                    Rpt.Add('U  ' + PadRight(Prim1.ObjectIDString, 10) + '            ' + PadRight(Violation.Name, 20) + ' '
                            + PadRight(ViolDesc, 60) + '   ' + Rule.Name + ' ' + RuleKindToString(Rule.RuleKind));

                    Prim1.SetState_DRCError(true);
                    Prim1.GraphicallyInvalidate;
                    inc(VCount);
                end;
            end;

            for J := (I + 1) to (Primitives.Count - 1) do
            begin
                Prim2 := Primitives.Items(J);
                Rule := Board.FindDominantRuleForObjectPair(Prim1, Prim2, RuleKind);
                if Rule <> nil then
                if (not Rule.IsUnary) and Rule.Enabled then
                begin
//                  Rule.CheckBinaryScope(Prim1, Prim2);
//                  Rule.Scope2Includes(Prim2);
                    Violation := Rule.ActualCheck(Prim1, Prim2);
                    if Violation <> nil then
                    begin
                        Board.AddPCBObject(Violation);
                        ViolDesc := Violation.Description;
                        ViolDesc := Copy(ViolDesc, 0, 60);
                        //SetLength(ViolDesc,40);
                        Rpt.Add('B  '+ PadRight(Prim1.ObjectIDString, 10) + ' ' + PadRight(Prim2.ObjectIDString, 10) + ' ' + PadRight(Violation.Name, 20)
                                + ' ' + PadRight(ViolDesc, 60) + '   ' + Rule.Name + ' ' + RuleKindToString(Rule.RuleKind));
                        Prim1.SetState_DRCError(true);
                        Prim2.SetState_DRCError(true);
                        Prim1.GraphicallyInvalidate;
                        Prim2.GraphicallyInvalidate;
                        inc(VCount);
                    end;
                end;
            end;  // J

            if (VCount > 0) and ((VCount mod ErrorCountPrompt) = 0) then
            begin
                dlgResult := ConfirmNoYesWithCaption('Lots of Violations ' + IntToStr(VCount), 'Continue ? ');
                BeginHourGlass(crHourGlass);
                if not dlgresult then GetOutOfLoops := true;
            end;
            if GetOutOfLoops then break;
        end;   // I
        if GetOutOfLoops then break;
    end;    // K

    Primitives.Destroy;
    RulesList.Destroy;
    RKindList.Free;

    EndHourGlass;
    Board.ViewManager_FullUpdate;
//    Client.SendMessage('PCB:Zoom', 'Action=Redraw' , 255, Client.CurrentView);
    if VCount = 0 then ShowMessage('NO Violations Found ');
end;

procedure StartReport(Board : IPCB_Board);
begin
    Rpt     := TStringList.Create;
    BOrigin := Point(Board.XOrigin, Board.YOrigin);
    BUnits  := eImperial;
    Rpt.Add('Board Origin ');
    Rpt.Add('X : ' + CoordUnitToString(BOrigin.X, BUnits) + '  Y : ' + CoordUnitToString(BOrigin.Y, BUnits));
end;

procedure SaveShowReport(Count : integer);
begin
    Rpt.Insert(0,'Rule Violations for Selected Object(s) ');
    Rpt.Insert(1, 'for ' + ExtractFileName(Board.FileName) + ' document.');
    Rpt.Insert(2, '----------------------------------------------------------');
    Rpt.Insert(3, 'Total Violations : ' + IntToStr(Count));

    // Display the Rules report
    FileName := ExtractFilePath(Board.FileName) + ChangefileExt(ExtractFileName(Board.FileName),'') + '-ObjViolateRpt.txt';
    Rpt.SaveToFile(Filename);
    Rpt.Free;

    if OpenReport then
    begin
        Document := Client.OpenDocumentShowOrHide('Text', FileName, true);
        if Document <> Nil Then
        begin
//            if (Document.GetIsShown <> 0 ) then
                Document.DoFileLoad;
//            Client.ShowDocumentDontFocus(Document);
            if FocusReport then
                Document.Focus;
        end;
    end;
end;

procedure ShowViolationsArea;
var
    x, y      : TCoord;
    x2, y2    : TCoord;
    BR        : TCoordRect;
begin
    Board := PCBServer.GetCurrentPCBBoard;
    if Board = Nil then exit;

    StartReport(Board);
    KeySet := MkSet();

    if Board.ChooseRectangleByCorners('Zone First Corner ','Zone Opposite Corner ', x, y, x2, y2) then
    begin
//   read modifier keys just as/after the "pick" mouse click
        if ShiftKeyDown   then KeySet := MkSet(cShiftKey);
        if AltKeyDown     then KeySet := SetUnion(KeySet, MkSet(cAltKey));
        if ControlKeyDown then KeySet := SetUnion(KeySet, MkSet(cCntlKey));

        BR := RectToCoordRect(Rect(x, y2, x2, y));      // Rect(L, T, R, B)

        Client.SendMessage('PCB:ResetAllErrorMarkers', '', 255, Client.CurrentView);
        Rpt.Add('');
        Rpt.Add('Existing DRC markers cleared');
        VCount := 0;
        ShowViolations(BR);

        SaveShowReport(VCount);
    end;
end;

procedure ShowViolationsObject;
var
    Comp       : IPCB_Component;
    SetObjects : TSet;
    x, y       : TCoord;
    BR         : TCoordRect;
    msg        : WideString;
    Finished   : boolean;
    TotVCount  : integer;
begin
    Board := PCBServer.GetCurrentPCBBoard;
    if Board = Nil then exit;

    StartReport(Board);
    SetObjects := MkSet(eComponentObject, eComponentBodyObject, eTrackObject, eArcObject,ePadObject,
                        eViaObject, eTextObject, ePolyObject, eRegionObject, eFillObject);
    Prim1 := eNoObject;

    if Board.GetState_SelectecObjectCount > 0 then
    begin
        Prim1 := Board.SelectecObject(0);
        if not InSet(Prim1.ObjectId, SetObjects) then Prim1 := eNoObject;
    end;

    Client.SendMessage('PCB:ResetAllErrorMarkers', '', 255, Client.CurrentView);

    TotVCount := 0;
    msg := 'Select Object for Design Rules Check ';
    Finished := false;
    repeat
        if Prim1 = eNoObject then
        begin
            if Board.ChooseLocation(x, y, msg) then  // false = ESC Key is pressed
            begin
                Prim1 := Board.GetObjectAtXYAskUserIfAmbiguous(x, y, SetObjects, AllLayers, eEditAction_Select);
            end
            else Finished := true;
        end;

        if (not Finished) and (Prim1 <> eNoObject) then
        begin
            if Prim1.ObjectId = eComponentObject then Comp := Prim1;
            if Prim1.ObjectiD = eComponentBodyObject then Comp := Prim1.Component;
            if (Comp <> Nil) and InSet(Prim1.ObjectId, MkSet(eComponentObject, eComponentBodyObject)) then
                BR := GetComponentBR(Comp)
            else
                BR := Prim1.BoundingRectangle;

            ShowViolations(BR);
            TotVCount := TotVCount + VCount;
        end;

        Prim1 := eNoObject;
        msg   := 'Select Another Object for DRC ?  or <esc> ';
    until Finished;

    if TotVCount > 0 then SaveShowReport(TotVCount);
end;


// Violation := PCBServer.PCBObjectFactory(eViolationObject, eNoDimension, eCreate_Default);

