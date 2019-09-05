{ DisperseComponents.pas
PcbDoc: Disperse/distribute component footprints in controlled groups to the
        right hand edge of board outline based on:-
 - components classes.
 - source SchDoc
 - Rooms
Rooms are also auto sized & placed to RHS of the Board Outline.

Things that are NOT moved:-
- any existing Component or Room in the required placement space.
- Component or Room inside the Board Outline shape.
- Graphical "Kind" Footprints

Script can be re-run after partial placement to move Rooms & Components closer
 to Board Outline.
All Room vertices & Component coordinates remain on Board grid units (integer).
For minimum processing duration can set LiveUpdate & debug = false.

TBD/Notes:  Board.DisplayUnits - TUnit returns wrong values (reversed) in AD17!   (Client.GetProductVersion;)
            Sort classes & Rooms into a sensible order.
            
B. Miller
06/07/2019 : v0.1  Initial POC
07/07/2019 : v0.2  Added component bounding box offsets.
                   Added Source SchDoc method.
08/08/2019 : v0.21 Minor reporting changes. Bit faster ?
09/07/2019 : v0.3  Better spacing & origin adjustment & coord extreme range checks.
                   CleanNets to refresh connection lines.
10/07/2019 : v0.31 Round the final Comp location to job units & board origin offset.
14/07/2019 : v0.40 Class Component subtotals & Room placement; tweaks to spacing
02/09/2019 : v0.41 Fix CleanNets; was changing the iterated objects.
03/09/2019 : v0.42 Rooms auto sizing & placement.
05/09/2019 : v0.50 Refactored bounding box & comp offsets to reuse for Room & Room comp placement.
06/09/2019 : v0.51 Add board origin details to reported bounding rectangle to match Rooms UI
}
const
    LiveUpdate  = true;    // display PCB changes "live"
    debug       = false;    // report file
    GRatio      = 1.618;   // aspect R of moved rooms.
    MilFactor   = 10;      // round off Coord in mils
    MMFactor    = 1;
    mmInch      = 25.4;
    TSP_NewCol  = 0;
    TSP_Before  = 1;
    TSP_After   = 2;

var
    FileName      : WideString;
    Board         : IPCB_Board;
    BUnits        : TUnit;
    BOrigin       : TCoordPoint;
    BRBoard       : TCoordRect;
    maxXsize      : TCoord;          // largest comp in column/group
    maxRXsize     : TCoord;          // largest room in column
    SpaceFactor   : double;          // 1 == no extra dead space
    Report        : TStringList;

function RndUnitPos( X : Coord, Offset : Integer, const Units :TUnits) : Coord;
// round the TCoord position value w.r.t Offset (e.g. board origin)
begin
    if Units = eImperial then
        Result := MilsToCoord(Round(CoordToMils(X - Offset) / MilFactor) * MilFactor) + Offset
    else
        Result := MMsToCoord(Round(CoordToMMs(X - Offset) / MMFactor) * MMFactor) + Offset;
end;

function RndUnit( X : Coord, Offset : Integer, const Units :TUnits) : Coord;
// round the value w.r.t Offset (e.g. board origin)
begin
    if Units = eImperial then
        Result := Round((X - Offset) / MilFactor) * MilFactor + Offset
    else
        Result := Round((X - Offset) / MMFactor) * MMFactor + Offset;
end;

function TestInsideBoard(Component : IPCB_Component) : boolean;
// for speed.. any part of comp touches or inside BO
var
    Prim   : IPCB_Primitive;
    PIter  : IPCB_GroupIterator;
begin
    Result := false;
    PIter  := Component.GroupIterator_Create;
    PIter.AddFilter_ObjectSet(MkSet(ePadObject, eRegionObject));
    Prim := PIter.FirstPCBObject;
    While (Prim <> Nil) and (not Result) Do
    Begin
        if Board.BoardOutline.GetState_HitPrimitive (Prim) then
            Result := true;
        Prim := PIter.NextPCBObject;
    End;
    Component.GroupIterator_Destroy(PIter);
end;

procedure TestStartPosition(var LocationBox : TCoordRect, var LBOffset : TCoordPoint, var maxXCSize : TCoord, const CSize : TCoordPoint, const Opern : integer);
var
    tempOffsetY : TCoord;

begin
    if Opern = TSP_NewCol then
        LBOffset.Y := LBOffset.Y + MilsToCoord(100);               // new class offset in column.

    tempOffsetY := LBOffset.Y;
    if Opern = TSP_After then                                      // next footprint Y coord.
    begin
        if CSize.Y < MilsToCoord(150) then
            LBOffset.Y := LBOffset.Y + CSize.Y * SpaceFactor
        else
            LBOffset.Y := LBOffset.Y + CSize.Y + MilsToCoord(80);
    end;

    if ((LocationBox.Y1 + tempOffsetY + CSize.Y) > LocationBox.Y2) then       // col too high or force to start new column with every new class/sourcedoc
    begin
        LBOffset.Y := 0;
        if maxXCsize < MilsToCoord(150) then
            LBOffset.X := LBOffset.X + maxXCsize * SpaceFactor
        else
        begin
            LBOffset.X := LBOffset.X + maxXCsize + MilsToCoord(50);
        end;
        maxXCsize := 0;
    end;

    LBOffset.X := Min(LBOffset.X, kMaxCoord - LocationBox.X1 - MilsToCoord(100));
    LBOffset.Y := Min(LBOffset.Y, kMaxCoord - LocationBox.Y1 - MilsToCoord(100));
end;

procedure PositionComp(Comp : IPCB_Component, var LocationBox : TCoordRect, var LBOffset : TCoordPoint);
var
    BRComp       : TCoordRect;
    OriginOffset : TCoordPoint;    // component origin offset to bounding box
    CSize        : TCoordPoint;

begin
  //  BRComp   := RectToCoordRect(Comp.BoundingRectangleNoNameComment);
    BRComp   := Comp.BoundingRectangleForPainting;    // inc. masks

    CSize    := Point(RectWidth(BRComp), RectHeight(BRComp));
    CSize.X  := Max(CSize.X, MilsToCoord(20) );
    CSize.Y  := Max(CSize.Y, MilsToCoord(20) );

//  will it fit?
    TestStartPosition(LocationBox, LBOffset, maxXSize, CSize, TSP_Before);

    maxXSize := Max(maxXsize, CSize.X);
    OriginOffset := Point(( Comp.x - BRComp.X1), (Comp.y - BRComp.Y1) );

    PCBServer.SendMessageToRobots(Comp.I_ObjectAddress, c_Broadcast, PCBM_BeginModify , c_NoEventData);

    Comp.x := RndUnitPos(LocationBox.X1 + LBOffset.X + OriginOffset.X, BOrigin.X, BUnits);
    Comp.y := RndUnitPos(LocationBox.Y1 + LBOffset.Y + OriginOffset.Y, BOrigin.Y, BUnits);

    PCBServer.SendMessageToRobots(Comp.I_ObjectAddress, c_Broadcast, PCBM_EndModify , c_NoEventData);
    Board.ViewManager_GraphicallyInvalidatePrimitive(Comp);

    TestStartPosition(LocationBox, LBOffset, maxXSize, CSize, TSP_After);
    if debug then
        Report.Add('Ch.Idx ' + IntToStr(Comp.ChannelOffset) +  '  Desg : ' + Comp.Name.Text + '  FP : ' + Comp.Pattern
                 + ' absX  ' + CoordUnitToString(Comp.x, BUnits)     + ' absY ' + CoordUnitToString(Comp.y, BUnits)
                 + ' offX  ' + CoordUnitToString(LBOffset.X, BUnits) + ' offY ' + CoordUnitToString(LBOffset.Y, BUnits) );
end;

procedure PositionRoom(Room : IPCB_ConfinementConstraint, RArea : Double, LocationBox : TCoordRect, var LBOffset : TCoordPoint);
var
    RoomBR    : TCoordRect;
    Length    : TCoord;
    Height    : TCoord;
    RSize     : TCoordPoint;

begin
    // Area in sq mils
    RArea := RArea * SpaceFactor * SpaceFactor;
    // new size
    Length := Sqrt(RArea * GRatio);
    Height := RArea / Length;
    Length := MilsToCoord( RndUnit(Length, 0, BUnits) );
    Height := MilsToCoord( RndUnit(Height, 0, BUnits) );
    Length := Max(Length, MilsToCoord(100 * GRatio) );
    Height := Max(Height, MilsToCoord(100) );

    RSize := Point(Length, Height);

//  will it fit?
    TestStartPosition(LocationBox, LBOffset, maxRXSize, RSize, TSP_Before);
    maxRXSize := Max(maxRXsize, RSize.X);

//    RoomBR   := Room.BoundingRectangle;
    RoomBR := RectToCoordRect(         //          Rect(L, T, R, B)
              Rect(RndUnitPos(LocationBox.X1 + LBOffset.X,          BOrigin.X, BUnits), RndUnitPos(LocationBox.Y1 + LBOffset.Y + Height, BOrigin.Y, BUnits),
                   RndUnitPos(LocationBox.X1 + LBOffset.X + Length, BOrigin.X, BUnits), RndUnitPos(LocationBox.Y1 + LBOffset.Y,          BOrigin.Y, BUnits)) );
    Room.BeginModify;
    Room.BoundingRect := RoomBR;
    Room.EndModify;

    TestStartPosition(LocationBox, LBOffset, maxRXSize, RSize, TSP_After);
    RSize := Point(RectWidth(RoomBR), RectHeight(RoomBR));
    if debug then
        Report.Add('Room : ' + Room.Identifier +  '  absX ' + CoordUnitToString(Room.X - BOrigin.X, BUnits) + ' absY ' + CoordUnitToString(Room.Y - BOrigin.Y, BUnits)
                 + '  offX ' + CoordUnitToString(LBOffset.X, BUnits) + ' offY ' + CoordUnitToString(LBOffset.Y, BUnits)  );
end;

procedure PositionCompsInRoom(Room : IPCB_ConfinementConstraint, CompClass : IPCB_ObjectClass);
var
    PCBComp   : IPCB_Component;
    Iterator  : IPCB_BoardIterator;
    I         : integer;
    RoomBR    : TCoordRect;
    LCOffset  : TCoordPoint;       // comp offsets in room box

begin
//    RoomBR := RectToCoordRect(Room.BoundingRectangleForPainting);
//    Room.BoundingRectangleForSelection;
    RoomBR := Room.BoundingRect;   // not BoundingRectangle !

    if debug then
        Report.Add('Room : ' + Room.Identifier +  '  X1 ' + CoordUnitToString(RoomBR.X1 - BOrigin.X, BUnits) + ' Y1 ' + CoordUnitToString(RoomBR.Y1 - BOrigin.Y, BUnits)
                                                + '  X2 ' + CoordUnitToString(RoomBR.X2 - BOrigin.X, BUnits) + ' Y2 ' + CoordUnitToString(RoomBR.Y2 - BOrigin.Y, BUnits)  );
    LCOffset := Point(10, 10);
    maxXsize := 0;

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    Iterator.AddFilter_LayerSet(SignalLayers);
    PCBComp := Iterator.FirstPCBObject;
    while PCBComp <> Nil Do
    begin
        if PCBComp.ComponentKind <> eComponentKind_Graphical then
            if CompClass.IsMember(PCBComp) then
                if not TestInsideBoard(PCBComp) then
                begin
                     PositionComp(PCBComp, RoomBR, LCOffset);
                end;
        PCBComp := Iterator.NextPCBObject;
    end;
    Board.BoardIterator_Destroy(Iterator);
end;

function GetReqRoomArea(Brd : IPCB_Board, CompClass : IPCB_ObjectClass) : Double; {sq mils}
var
    PCBComp  : IPCB_Component;
    Iterator : IPCB_BoardIterator;
    BRComp   : TCoordRect;
    Area     : Double;

begin
    Area := 0;
    CompClass.Name;
    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    Iterator.AddFilter_LayerSet(SignalLayers);
    PCBComp := Iterator.FirstPCBObject;
    while PCBComp <> Nil Do
    begin
        if CompClass.IsMember(PCBComp) then
        begin
            BRComp := PCBComp.BoundingRectangleNoNameComment;
            Area := Area + abs(CoordToMils( RectWidth(BRComp)) * CoordToMils(RectHeight(BRComp)) );
        end;
        PCBComp := Iterator.NextPCBObject;
    end;
    Board.BoardIterator_Destroy(Iterator);
    Result := Area;
end;

function TestRoomInsideBoard(Room : IPCB_Rule) : boolean;
// touching is inside BO!
var
    RuleBR : TCoordRect;

begin
// Rule.PolygonOutline  ;       // may have to consider
    Result := false;
    RuleBR := Room.BoundingRectangle;
    Result := Result or Board.BoardOutline.GetState_StrictHitTest(RuleBR.left, RuleBR.bottom);
    Result := Result or Board.BoardOutline.GetState_StrictHitTest(RuleBR.left, RuleBR.top);
    Result := Result or Board.BoardOutline.GetState_StrictHitTest(RuleBR.right, RuleBR.bottom);
    Result := Result or Board.BoardOutline.GetState_StrictHitTest(RuleBR.right, RuleBR.top);
end;

procedure CleanUpNetConnections(Board : IPCB_Board);
var
    Iterator : IPCB_BoardIterator;
    Connect  : IPCB_Connection;
    Net      : IPCB_Net;
    NetList  : TObjectList;
    N        : integer;
begin
    NetList := TObjectList.Create;

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eConnectionObject));
    Iterator.AddFilter_LayerSet(AllLayers);
    Iterator.AddFilter_Method(eProcessAll);
    Connect := Iterator.FirstPCBObject;
    while (Connect <> Nil) Do
    begin
        Net := Connect.Net;
        if Net <> Nil then
            if NetList.IndexOf(Net) = -1 then NetList.Add(Net);
        Connect := Iterator.NextPCBObject;
    end;
    Board.BoardIterator_Destroy(Iterator);

    for N := 0 to (NetList.Count - 1) do
    begin
        Net := NetList.Items(N);
        Board.CleanNet(Net);
    end;
    NetList.Destroy;
end;

procedure GetBoardClasses(Board : IPCB_Board, var ClassList : TObjectList, const ClassKind : Integer);
var
    Iterator  : IPCB_BoardIterator;
    CompClass : IPCB_ObjectClass;

begin
    Iterator := Board.BoardIterator_Create;
    Iterator.SetState_FilterAll;
    Iterator.AddFilter_ObjectSet(MkSet(eClassObject));
    CompClass := Iterator.FirstPCBObject;
    While CompClass <> Nil Do
    Begin
        if CompClass.MemberKind = ClassKind Then
            if Classlist.IndexOf( CompClass) = -1 then
                ClassList.Add(CompClass);

        CompClass := Iterator.NextPCBObject;
    End;
    Board.BoardIterator_Destroy(Iterator);
end;

procedure GetClassCompSubTotals(Board : IPCB_Board, ClassList, var ClassSubTotal : TParameterList);
var
     PCBComp   : IPCB_Component;
     Iterator  : IPCB_BoardIterator;
     Count     : integer;
     CompClass : IPCB_ObjectClass;
     I         : integer;

begin
    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    Iterator.AddFilter_LayerSet(SignalLayers);

    PCBComp := Iterator.FirstPCBObject;
    while PCBComp <> Nil Do
    begin
        if PCBComp.ComponentKind <> eComponentKind_Graphical then
        begin
            for I := 0 to (ClassList.Count - 1) do
            begin
                CompClass := ClassList.Items(I);
                if CompClass.IsMember(PCBComp) then
                begin
                    Count := 0;
    // if parameter exists then increment else add
                    if ClassSubTotal.GetState_ParameterAsInteger(CompClass.Name, Count) then
                    begin
                        inc(Count);
                        ClassSubTotal.SetState_AddOrReplaceParameter(CompClass.Name, IntToStr(Count), true) ;
                    end
                    else
                    begin
                        Count := 1;
                        ClassSubTotal.SetState_AddParameterAsInteger(CompClass.Name, Count);
                    end;
                end;
            end;
        end;
        PCBComp := Iterator.NextPCBObject;
    end;
end;


//----------------------------------------------------------------------------------

Procedure DisperseByClass;
Var
   PCBComp       : IPCB_Component;
   LocRect       : TCoordRect;
   LCOffset      : TCoordPoint;
   Iterator      : IPCB_BoardIterator;
   ClassList     : TObjectList;
   CompClass     : IPCB_ObjectClass;
   ClassSubTotal : TParameterList;
   CSubTotal     : integer;
   I             : integer;
   skip          : boolean;

Begin
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;

    BeginHourGlass(crHourGlass);

    if debug then Report := TStringList.Create;
    BOrigin := Point(Board.XOrigin, Board.YOrigin);
    BRBoard := Board.BoardOutline.BoundingRectangle;
    LocRect := RectToCoordRect(
               Rect(BRBoard.Right + MilsToCoord(400), BRBoard.Top + MilsToCoord(200),
                    kMaxCoord - MilsToCoord(10), BRBoard.Bottom) );
    LCOffset := Point(0, 0);
    maxXsize := 0;
    SpaceFactor := 2;

// returns TUnits but with swapped meanings AD17 0 == Metric but API has eMetric = 1
    BUnits := Board.DisplayUnit;
    if BUnits = 0 then BUnits := 1
    else BUnits := 0;

    ClassList := TObjectList.Create;
    GetBoardClasses(Board, ClassList, eClassMemberKind_Component);
    ClassSubTotal := TParameterList.Create;
    GetClassCompSubTotals(Board, ClassList, ClassSubTotal);

    if debug then Report.Add('Class count = ' + IntToStr(ClassList.Count) );

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    Iterator.AddFilter_LayerSet(AllLayers);

    PCBServer.PreProcess;

    for I := 0 to (ClassList.Count - 1) Do
    Begin
        CompClass := ClassList.Items(I);
        CSubTotal := 0;
        ClassSubTotal.GetState_ParameterAsInteger(CompClass.Name, CSubTotal);
        skip := false;

        if CompClass.SuperClass then skip := true;
// all below are superclasses so redundant code..
        if CompClass.Name = 'All Components' then skip := true;
        if CompClass.Name = 'Outside Board Components' then skip := true;
        if CompClass.Name = 'Inside Board Components' then skip := true;
        if CompClass.Name = 'Bottom Side Components' then skip := true;
        if CompClass.Name = 'Top Side Components' then skip := true;

// potential location below for special hacks..
//        skip := true;
//        if ansipos('_Cell', CompClass.Name) = 0  then skip := true;
//        if ansipos('Cell', CompClass.Name) > 0  then skip := false;

        if debug then
            Report.Add('ClassName : ' + CompClass.Name + '  Kind : ' + IntToStr(CompClass.MemberKind)
                       + '  skip : ' + IntToStr(skip) + '  Member Count = ' + IntToStr(CSubTotal) );
        if not skip then
        begin
            PCBComp := Iterator.FirstPCBObject;
            while PCBComp <> Nil Do
            begin
                if PCBComp.ComponentKind <> eComponentKind_Graphical then
                    if CompClass.IsMember(PCBComp) then
                        if not TestInsideBoard(PCBComp) then
                        begin
                            PositionComp(PCBComp, LocRect, LCOffset);
                        end;
                PCBComp := Iterator.NextPCBObject;
            end;

            TestStartPosition(LocRect, LCOffset, maxXSize, Point(0, 0), TSP_NewCol);
            if LiveUpdate then Board.ViewManager_FullUpdate;
        end;
    end;
    Board.BoardIterator_Destroy(Iterator);

    PCBServer.PostProcess;
    ClassList.Destroy;

    CleanUpNetConnections(Board);
    EndHourGlass;

    Board.SetState_DocumentHasChanged;
    Board.GraphicallyInvalidate;
    Board.ViewManager_FullUpdate;

    if debug then
    begin
        FileName := ChangeFileExt(Board.FileName, '.clsrep');
        Report.SaveToFile(Filename);
        Report.Free;
    end;
    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 1024, Client.CurrentView);
end;

procedure DisperseBySourceSchDoc;
var
   PCBComp        : IPCB_Component;
   LocRect        : TCoordRect;
   LROffset       : TCoordPoint;
   Iterator       : IPCB_BoardIterator;
   LSchDocs       : TStringList;
   SchDocFileName : IPCB_String;
   I              : integer;
   skip           : boolean;

begin
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;

    BeginHourGlass(crHourGlass);

    BOrigin := Point(Board.XOrigin, Board.YOrigin);
    if debug then
    begin
        Report := TStringList.Create;
        Report.Add('Board originX : ' + CoordUnitToString(BOrigin.X, BUnits) + ' originY ' + CoordUnitToString(BOrigin.Y, BUnits));
    end;

    BRBoard := Board.BoardOutline.BoundingRectangle;
    LocRect := RectToCoordRect(     //             Rect(L, T, R, B)
               Rect(BRBoard.Right + MilsToCoord(400), BRBoard.Top + MilsToCoord(200),
                    kMaxCoord - MilsToCoord(10), BRBoard.Bottom) );
    LROffset := Point(0, 0);
    maxXsize := 0;
    SpaceFactor := 2;

    BUnits := Board.DisplayUnit;
    if BUnits = 0 then BUnits := 1
    else BUnits := 0;

    LSchDocs := TStringList.Create;

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    Iterator.AddFilter_LayerSet(AllLayers);

    PCBComp := Iterator.FirstPCBObject;
    while PCBComp <> Nil Do
    begin
        SchDocFileName := PCBComp.SourceHierarchicalPath;
        if SchDocfileName <> '' then
            if LSchDocs.IndexOf(SchDocFileName) = -1 then
                LSchDocs.Add(SchDocFileName);

        PCBComp := Iterator.NextPCBObject;
    end;
    if debug then Report.Add('Source Doc count = ' + IntToStr(LSchDocs.Count) );

    Iterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    Iterator.AddFilter_LayerSet(AllLayers);

    PCBServer.PreProcess;

    for I := 0 to (LSchDocs.Count - 1) Do
    Begin
        SchDocFileName := LSchDocs.Get(I);
        if debug then Report.Add('SourceDoc Name : ' + SchDocFileName);

        PCBComp := Iterator.FirstPCBObject;
        while PCBComp <> Nil Do
        begin
            if PCBComp.ComponentKind <> eComponentKind_Graphical then
                if SchDocFileName = PCBComp.SourceHierarchicalPath then     // or SourceDescription
                    if not TestInsideBoard(PCBComp) then
                    begin
                        PositionComp(PCBComp, LocRect, LROffset);
                    end;
            PCBComp := Iterator.NextPCBObject;
        End;
        TestStartPosition(LocRect, LROffset, maxXSize, Point(0, 0), TSP_NewCol);
        if LiveUpdate then Board.ViewManager_FullUpdate;
    end;
    Board.BoardIterator_Destroy(Iterator);

    PCBServer.PostProcess;
    CleanUpNetConnections(Board);

    LSchDocs.Free;

    EndHourGlass;

    Board.SetState_DocumentHasChanged;
    Board.GraphicallyInvalidate;
    Board.ViewManager_FullUpdate;

    if debug then
    begin
        FileName := ChangeFileExt(Board.FileName, '.sdocrep');
        Report.SaveToFile(Filename);
        Report.Free;
    end;
    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 1024, Client.CurrentView);
end;

Procedure DisperseInRooms;
var
    Iterator      : IPCB_BoardIterator;
    Rule          : IPCB_Rule;
    Room          : IPCB_ConfinementConstraint;
    RuleBR        : TCoordRect;
    LocRect       : TCoordRect;
    LROffset      : TCoordPoint;       // room offsets in main big box
    RoomArea      : TDouble;
    RoomRuleList  : TObjectList;
    ClassList     : TObjectList;
    CompClass     : IPCB_ObjectClass;
    ClassSubTotal : TParameterList;
    CSubTotal     : integer;
    I, J          : integer;
    found         : boolean;

begin
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;

    BUnits := Board.DisplayUnit;
    if BUnits = 0 then BUnits := 1
    else BUnits := 0;

    BOrigin := Point(Board.XOrigin, Board.YOrigin);
    BRBoard := Board.BoardOutline.BoundingRectangle;
    LocRect := RectToCoordRect(
               Rect(BRBoard.Right + MilsToCoord(400), BRBoard.Top + MilsToCoord(200),
                    kMaxCoord - MilsToCoord(10), BRBoard.Bottom) );
    LROffset := Point(0, 0);
    maxRXSize := 0;

    BeginHourGlass(crHourGlass);

    if debug then
    begin
        Report := TStringList.Create;
        Report.Add('Board originX : ' + CoordUnitToString(BOrigin.X, BUnits) + ' originY ' + CoordUnitToString(BOrigin.Y, BUnits));
    end;

    RoomRuleList := TObjectList.Create;

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eRuleObject));
    Iterator.AddFilter_LayerSet(AllLayers);
    Iterator.AddFilter_Method(eProcessAll);
    Rule := Iterator.FirstPCBObject;
    While (Rule <> Nil) Do
    Begin
        if Rule.RuleKind = eRule_ConfinementConstraint then    // 'RoomDefinition';
            RoomRuleList.Add(Rule);
        Rule := Iterator.NextPCBObject;
    end;
    Board.BoardIterator_Destroy(Iterator);

    ClassList := TObjectList.Create;
    GetBoardClasses(Board, ClassList, eClassMemberKind_Component);
    ClassSubTotal := TParameterList.Create;
    GetClassCompSubTotals(Board, ClassList, ClassSubTotal);


    if debug then Report.Add('Rooms Rule Count = ' + IntToStr(RoomRuleList.Count));

    for I := 0 to (RoomRuleList.Count - 1) do
    begin
        Room := RoomRuleList.Items(I);
        if debug then
            Report.Add(IntToStr(I) + ': ' + Room.Name + ', UniqueId: ' +  Room.UniqueId +
                       ', RuleType: ' + IntToStr(Room.RuleKind) + '  Layer : ' + Board.LayerName(Room.Layer) );       // + RuleKindToString(Rule.RuleKind));

        if TestRoomInsideBoard(Room) then
        begin
            if debug then Report.Add(IntToStr(I) + ': ' + Room.Name + ' is Inside BO');
        end
        else
        begin
 // find the matching class
            found := false;
            J := 0;
            while (not found) and (J < ClassList.Count) do
            begin
                CSubTotal := 0;
                CompClass := ClassList.Items(J);
                ClassSubTotal.GetState_ParameterAsInteger(CompClass.Name, CSubTotal);

                if (CSubTotal > 0) and (CompClass.Name = Room.Identifier) and (not CompClass.SuperClass) then
                begin
                    found := true;
                    if debug then Report.Add('found matching Class ' + IntToStr(J) + ': ' + CompClass.Name + '  Member Count = ' + IntToStr(CSubTotal));
                    if debug then Report.Add('X = ' + CoordUnitToString(Room.X, BUnits) + '  Y = ' + CoordUnitToString(Room.Y, BUnits) );
                    if debug then Report.Add('DSS    ' + Room.GetState_DataSummaryString);
                    if debug then Report.Add('Desc   ' + Room.Descriptor);
                    if debug then Report.Add('SDS    ' + Room.GetState_ScopeDescriptorString);

                    RoomArea {sq mils} := GetReqRoomArea(Board, CompClass);
                    if debug then Report.Add(' area sq mils ' + FormatFloat(',0.###', RoomArea) );

                    SpaceFactor := 2;
                    PositionRoom(Room, RoomArea, LocRect, LROffset);

//                  locate components by channel index order.
//                    LCOffset := Point(0, 0);
                    SpaceFactor := 1.6;
                    PositionCompsInRoom(Room, CompClass);
                    if LiveUpdate then Board.ViewManager_FullUpdate;
                end;
                Inc(J);
                if found then
                    if debug then  Report.Add('');
            end;
        end;  // outside BO
    end;

    CleanUpNetConnections(Board);
    EndHourGlass;

    RoomRuleList.Destroy;
    ClassList.Destroy;

    Board.GraphicallyInvalidate;
    Board.ViewManager_FullUpdate;

    if debug then
    begin
        FileName := ChangeFileExt(Board.FileName, '.rmcrep');
        Report.SaveToFile(Filename);
        Report.Free;
    end;
    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 1024, Client.CurrentView);
end;

{
Rooms
ObjectKind: Confinement Constraint Rule
Category: Placement  Type: Room Definition
   have scope InComponentClass(list of comps)
   have a region BR or VL

        Room.Kind;
        Room.Selected;
        Room.PolygonOutline  ;
        Room.UserRouted;
        Room.IsKeepout;
        Room.UnionIndex;
        Room.NetScope;                    // convert str
        Room.LayerKind;                   // convert str
        Room.Scope1Expression;
        Room.Scope2Expression;
        Room.Priority;
        Room.DefinedByLogicalDocument;

 Room.MoveToXY(RndUnitPos(LocationBox.X1, BOrigin.X, BUnits), RndUnitPos(LocationBox.Y1, BOrigin.Y, BUnits) );

IPCB_ConfinementConstraint Methods
Procedure RotateAroundXY (AX, AY : TCoord; Angle : TAngle);

IPCB_ConfinementConstraint Properties
Property X            : TCoord
Property Y            : TCoord
Property Kind         : TConfinementStyle
Property Layer        : TLayer
Property BoundingRect : TCoordRect

TCoordRect   = Record
    Case Integer of
       0 :(left,bottom,right,top : TCoord);
       1 :(x1,y1,x2,y2           : TCoord);
       2 :(Location1,Location2   : TCoordPoint);

 RectToCoordRect( __Rect__Wrapper) to TCoordRect
}

{  Use built-in functions..
      Board.SelectedObjects_Clear;
      Board.SelectedObjects_Add(Room);
    // DNW can't operate on select rooms..                vvvvvv - does nothing
      Client.SendMessage('PCB:ArrangeComponents', 'Object=Selected|Action=ArrangeWithinRoom', 1024, Client.CurrentView);


//    Board.VisibleGridUnit;
//    Board.ComponentGridSize; // TDouble

}

