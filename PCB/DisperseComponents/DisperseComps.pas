{ DisperseComponents.pas
Group by comp class.
Components inside board outline are NOT moved.
Graphical "Kind" footprints are not moved

B. Miller
06/07/2019 : v0.1  Initial POC
07/07/2019 : v0.2  Added component bounding box offsets.
                   Added Source SchDoc method.
08/08/2019 : v0.21 Minor reporting changes. Bit faster ?
09/07/2019 : v0.3  Better spacing & origin adjustment & coord extreme range checks.
                   CleanNets to refresh connection lines.
10/07/2019 : v0.31 Round the final Comp location to job units & board origin offset.
14/07/2019 : v0.40 Class Component subtotals & Room placement; tweaks to spacing

Notes  Board.DisplayUnits TUnit returns wrong values !

}
const
    debug       = true;    // report file
    SpaceFactor = 1.5;     // 1 == no extra dead space
    GRatio      = 1.618;   // aspect R of moved rooms.
    MilFactor   = 50;      // round off Coord in mils
    MMFactor    = 1;
    mmInch      = 25.4;

var
    FileName      : WideString;
    Board         : IPCB_Board;
    BUnits        : TUnit;
    BOrigin       : TCoordPoint;
    BRBoard       : TCoordRect;
    CSize         : TCoordPoint;
    maxXsize      : TCoord;
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

Procedure PositionComp(Location : TCoordPoint, Comp : IPCB_Component);
var
    BRComp       : TCoordRect;
    OriginOffset : TCoordPoint;    // component origin offset to bounding box

begin
    BRComp   := Comp.BoundingRectangleNoNameComment;
    CSize    := Point( (BRComp.X2 - BRComp.X1), (BRComp.Y2 - BRComp.Y1) );
    CSize.X  := Max(CSize.X, MilsToCoord(20) );
    CSize.Y  := Max(CSize.Y, MilsToCoord(20) );
    maxXSize := Max(maxXsize, CSize.X);
    OriginOffset := Point(( Comp.x - BRComp.X1), (Comp.y - BRComp.Y1) );

    PCBServer.SendMessageToRobots(Comp.I_ObjectAddress, c_Broadcast, PCBM_BeginModify , c_NoEventData);

    Comp.x := RndUnitPos(Location.X + OriginOffset.X, BOrigin.X, BUnits);
    Comp.y := RndUnitPos(Location.Y + OriginOffset.Y, BOrigin.Y, BUnits);

    PCBServer.SendMessageToRobots(Comp.I_ObjectAddress, c_Broadcast, PCBM_EndModify , c_NoEventData);

    if debug then
        Report.Add('ChannelIndex = ' + IntToStr(Comp.ChannelOffset) +  '  Desig : ' + Comp.Name.Text + '  FP : '
             + Comp.Pattern + ' absX ' + CoordUnitToString(Comp.x, BUnits) + ' absY ' + CoordUnitToString(Comp.y, BUnits) );
end;

Procedure PositionRoom(Room : IPCB_Rule, RArea : Double, Location : TCoordPoint, var RSize : TCoordPoint);
var
    RuleBR       : TCoordRect;
    OriginOffset : TCoordPoint;    // component origin offset to bounding box
    Length       : TCoord;
    Height       : TCoord;

begin
    RuleBR   := Room.BoundingRectangle;
    // Area in sq mils
    RArea := RArea * SpaceFactor * SpaceFactor;
    // new size
    Length := RArea * GRatio;
    Length := Sqrt(Length);
    Length := RndUnit(Length, 0, BUnits);
    Height := RArea / Length;
    Height := Height;
    Height := RndUnit(Height, 0, BUnits);

    Length  := Max(Length,MilsToCoord(100) );
    Height  := Max(Height, MilsToCoord(100) );

//    OriginOffset := Point(( Comp.x - BRComp.X1), (Comp.y - BRComp.Y1) );

//    PCBServer.SendMessageToRobots(Room.I_ObjectAddress, c_Broadcast, PCBM_BeginModify , c_NoEventData);
    Room.BeginModify;

    Room.MoveToXY(RndUnitPos(Location.X, BOrigin.X, BUnits), RndUnitPos(Location.Y, BOrigin.Y, BUnits) );
    Room.EndModify;

//    PCBServer.SendMessageToRobots(Room.I_ObjectAddress, c_Broadcast, PCBM_EndModify , c_NoEventData);

    RuleBR := Room.BoundingRectangle;
    RSize := Point(RuleBR.right - RuleBR.left, RuleBR.top - RuleBR.bottom);
    maxXSize := Max(maxXsize, RSize.X);
    if debug then
        Report.Add('Room : ' + Room.Identifier +  '  absX ' + CoordUnitToString(Room.X, BUnits) + ' absY ' + CoordUnitToString(Room.Y, BUnits) );
end;

procedure TestStartNewColumn(BoxSize : TCoordPoint, var Location : TCoordPoint, const force : boolean);
// this proc called twice if forced after class finish..
begin
    if force then
        Location.Y := Location.Y + MilsToCoord(100)              //new class offset in column.
    else
        if BoxSize.Y < MilsToCoord(150) then
            Location.Y := Location.Y + BoxSize.Y * SpaceFactor        // next footprint Y coord.
        else
            Location.Y := Location.Y + BoxSize.Y + MilsToCoord(50);        // next footprint Y coord.

    if (Location.Y > BRBoard.Top) then                      // (Loc.Y>BRB..) or force  // to start new column with every new class/sourcedoc
    begin
        if maxXsize < MilsToCoord(150) then
            Location := Point( (Location.X + maxXsize * SpaceFactor), BRBoard.Bottom)
        else
            Location := Point( (Location.X + maxXsize + MilsToCoord(50)), BRBoard.Bottom)
        maxXsize := 0;
    end;

    Location.X := Min(Location.X, kMaxCoord);
    Location.Y := Min(Location.Y, kMaxCoord);
    Location.X := Max(Location.X, kMinCoord);
    Location.Y := Max(Location.Y, kMinCoord);
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

Procedure CleanUpNetConnections(Board : IPCB_Board);
var
    Iterator : IPCB_BoardIterator;
    Connect  : IPCB_Connection;

begin
    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eConnectionObject));
    Iterator.AddFilter_LayerSet(AllLayers);
    Iterator.AddFilter_Method(eProcessAll);

    Connect := Iterator.FirstPCBObject;
    while (Connect <> Nil) Do
    begin
        if Connect.Net <> Nil then
            Board.CleanNet(Connect.Net);
        Connect := Iterator.NextPCBObject;
    end;
    Board.BoardIterator_Destroy(Iterator);
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

procedure GetClassCompSubTotals(Board, ClassList, var ClassSubTotal : TParameterList);
var
     PCBComp   : IPCB_Component;
     Iterator  : IPCB_BoardIterator;
     Count     : integer;
     CompClass : IPCB_ObjectClass;
     I         : integer;

begin
    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    Iterator.AddFilter_LayerSet(AllLayers);

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
   Loc           : TCoordPoint;
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
    Loc := Point((BRBoard.Right + MilsToCoord(400)), BRBoard.Bottom);

// returns TUnits but with swapped meanings AD17 0 == Metric but API has eMetric = 1
    BUnits := Board.DisplayUnit;
    if BUnits = 0 then BUnits := 1
    else BUnits := 0;

//    Board.VisibleGridUnit;
//    Board.ComponentGridSize; // TDouble

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
                            PositionComp(Loc, PCBComp);
                            TestStartNewColumn(CSize, Loc, false);
                        end;
                PCBComp := Iterator.NextPCBObject;
            end;
            TestStartNewColumn(CSize, Loc, true);
        end;

    end;

    PCBServer.PostProcess;

    Board.BoardIterator_Destroy(Iterator);
    CleanUpNetConnections(Board);

    ClassList.Destroy;
    Board.SetState_DocumentHasChanged;
    Board.GraphicallyInvalidate;

    EndHourGlass;

    if debug then
    begin
        FileName := ChangeFileExt(Board.FileName, '.clsrep');
        Report.SaveToFile(Filename);
        Report.Free;
    end;
    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 1024, Client.CurrentView);
End;

Procedure DisperseBySourceSchDoc;
Var
   PCBComp        : IPCB_Component;
   Loc            : TCoordPoint;
   Iterator       : IPCB_BoardIterator;
   LSchDocs       : TStringList;
   SchDocFileName : IPCB_String;
   I              : integer;
   skip           : boolean;

Begin
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;

    BeginHourGlass(crHourGlass);

    if debug then Report := TStringList.Create;
    BOrigin := Point(Board.XOrigin, Board.YOrigin);
    BRBoard := Board.BoardOutline.BoundingRectangle;
    Loc := Point((BRBoard.Right + MilsToCoord(400)), BRBoard.Bottom);

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
                        PositionComp(Loc, PCBComp);
                        TestStartNewColumn(CSize, Loc, false);
                    end;
            PCBComp := Iterator.NextPCBObject;
        End;

        TestStartNewColumn(CSize, Loc, true);
    end;

    PCBServer.PostProcess;
    Board.BoardIterator_Destroy(Iterator);

    CleanUpNetConnections(Board);

    Board.SetState_DocumentHasChanged;
    Board.GraphicallyInvalidate;
    LSchDocs.Free;

    EndHourGlass;

    if debug then
    begin
        FileName := ChangeFileExt(Board.FileName, '.sdocrep');
        Report.SaveToFile(Filename);
        Report.Free;
    end;
    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 1024, Client.CurrentView);
End;

function GetReqRoomArea(Brd : IPCB_Board, CompClass : IPCB_ObjectClass) : Double;
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
    Iterator.AddFilter_LayerSet(AllLayers);
    PCBComp := Iterator.FirstPCBObject;
    while PCBComp <> Nil Do
    begin
        if CompClass.IsMember(PCBComp) then
        begin
            BRComp := PCBComp.BoundingRectangleNoNameComment;
            Area := Area + abs(CoordToMils(BRComp.X2 - BRComp.X1) * CoordToMils(BRComp.Y2 - BRComp.Y1));
        end;
        PCBComp := Iterator.NextPCBObject;
    end;
    Board.BoardIterator_Destroy(Iterator);
    Result := Area;
end;

Procedure DisperseInRooms;
var
    Iterator      : IPCB_BoardIterator;
    Rule          : IPCB_Rule;
    RuleBR        : TCoordRect;
    RLoc          : TCoordPoint;
    CLoc          : TCoordPoint;
    RoomSize      : TCoordPoint;
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

    BOrigin := Point(Board.XOrigin, Board.YOrigin);
    BRBoard := Board.BoardOutline.BoundingRectangle;
    RLoc := Point((BRBoard.Right + MilsToCoord(400)), BRBoard.Bottom);

    BUnits := Board.DisplayUnit;
    if BUnits = 0 then BUnits := 1
    else BUnits := 0;

    if debug then Report := TStringList.Create;
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

{
IPCB_ConfinementConstraint Methods
Procedure RotateAroundXY (AX,
                          AY    : TCoord;
                          Angle : TAngle);
IPCB_ConfinementConstraint Properties
Property X            : TCoord
Property Y            : TCoord
Property Kind         : TConfinementStyle
Property Layer        : TLayer
Property BoundingRect : TCoordRect
}
    Report.Add('Rooms Rule Count = ' + IntToStr(RoomRuleList.Count));

    for I := 0 to (RoomRuleList.Count - 1) do
    begin
        Rule := RoomRuleList.Items(I);
        if debug then
            Report.Add(IntToStr(I) + ': ' + Rule.Name + ', UniqueId: ' +  Rule.UniqueId +
                       ', RuleType: ' + IntToStr(Rule.RuleKind) + '  Layer : ' + Board.LayerName(Rule.Layer) );       // + RuleKindToString(Rule.RuleKind));

        RuleBR := Rule.BoundingRectangle;
        if TestRoomInsideBoard(Rule) then
        begin
            if debug then Report.Add(IntToStr(I) + ': ' + Rule.Name + ' is Inside BO');
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
 
                if (CSubTotal > 0) and (CompClass.Name = Rule.Identifier) and (not CompClass.SuperClass) then
                begin
                    found := true;
                    if debug then Report.Add('found matching Class ' + IntToStr(J) + ': ' + CompClass.Name + '  Member Count = ' + IntToStr(CSubTotal));
                    if debug then Report.Add('X = ' + CoordUnitToString(Rule.X, BUnits) + '  Y = ' + CoordUnitToString(Rule.Y, BUnits) );
                    if debug then Report.Add('DSS    ' + Rule.GetState_DataSummaryString);
                    if debug then Report.Add('Desc   ' + Rule.Descriptor);
                    if debug then Report.Add('SDS    ' + Rule.GetState_ScopeDescriptorString);

        Rule.Kind;
        Rule.Selected;
        Rule.PolygonOutline  ;
        Rule.UserRouted;
        Rule.IsKeepout;
        Rule.UnionIndex;
        Rule.NetScope;                    // convert str
        Rule.LayerKind;                   // convert str
        Rule.Scope1Expression;
        Rule.Scope2Expression;
        Rule.Priority;
        Rule.DefinedByLogicalDocument;

                    RoomArea := GetReqRoomArea(Board, CompClass);
                    if debug then Report.Add(' area sq mils ' + FormatFloat(',0.###', RoomArea) );

                    PositionRoom(Rule, RoomArea, RoomSize);
// PositionCompInRoom()
                    TestStartNewColumn(RoomSize, RLoc, false);
                end;
                Inc(J);
                if found then Report.Add('');
            end;
        end;  // outside BO

    end;

    RoomRuleList.Destroy;
    ClassList.Destroy;

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

room rule collection   // eClassMemberKind_DesignChannel ?
determine required room size
    - iterate all members & BR sum area..

determine which rooms are the same (component classes)  (channel index lists ??)

locate room by moving/sizing the vertex list. TopRight BR BL TopLeft
locate components by channel index order.

TCoordRect   = Record
    Case Integer of
       0 :(left,bottom,right,top : TCoord);
       1 :(x1,y1,x2,y2           : TCoord);
       2 :(Location1,Location2   : TCoordPoint);

}

