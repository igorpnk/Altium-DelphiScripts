{ PostionRooms.pas
PcbDoc: Position Rooms by the bounding rectangle vertices or (X,Y).

Read file & match Room by name.
Uses same units as board & referenced to board origin.
Position & resize Room bounding rectangle.
Position by MoveXY

File Format:
// comment
cLabelRoomBR, RoomName, X1, Y1, X2, Y2
cLabelRoomXY, RoomName, X1, Y1
<eof>

TBD/Notes:  Board.DisplayUnits - TUnit returns wrong values (reversed) in AD17!   (Client.GetProductVersion;)

B. Miller
17/07/2020 : 0.1  Initial POC
19/07/2020 : 0.11 Added MoveXY method

}

const
    LiveUpdate   = true;    // display PCB changes "live"
    debug        = true;    // report file
    MilFactor    = 10;      // round off Coord in mils
    MMFactor     = 1;
    mmInch       = 25.4;
    cLabelRoomBR = 'RoomBR';
    cLabelRoomXY = 'RoomXY';
    cLabelName   = 'PrimName';   // not used, for tuples p=v

var
    FileName      : WideString;
    Board         : IPCB_Board;
    BUnits        : TUnit;
    BOrigin       : TPoint;
    BRBoard       : TCoordRect;
    Report        : TStringList;
    Flag          : Integer;


function GetBoardDetail(const dummy : integer) : TCoordRect;
var
    Height : TCoord;
begin
// returns TUnits but with swapped meanings AD17 0 == Metric but API has eMetric=1 & eImperial=0
    BUnits := Board.DisplayUnit;
    GetCurrentDocumentUnit;
    if (BUnits = eImperial) then BUnits := eMetric
    else BUnits := eImperial;

    BOrigin := Point(Board.XOrigin, Board.YOrigin);
    BRBoard := Board.BoardOutline.BoundingRectangle;

    if debug then
    begin
        Report := TStringList.Create;
        Report.Add('Board originX : ' + CoordUnitToString(BOrigin.X, BUnits) + ' originY ' + CoordUnitToString(BOrigin.Y, BUnits));
    end;

// set some minimum height to work in.
    Height := RectHeight(BRBoard) + MilsToCoord(200);
    if Height < MilsToCoord(2000) then Height := MilsToCoord(2000);
    Result := RectToCoordRect(
              Rect(BRBoard.Right + MilsToCoord(400), BRBoard.Bottom + Height,
                   kMaxCoord - MilsToCoord(10)     , BRBoard.Bottom          ) );
end;

function MinF(a, b : Double) : Double;
begin
    Result := a;
    if a > b then Result := b;
end;
function MaxF(a, b : Double) : Double;
begin
    Result := b;
    if a > b then Result := a;
end;

function RndUnitPos( X : TCoord, Offset : TCoord, const Units : TUnits) : TCoord;
// round the TCoord position value w.r.t Offset (e.g. board origin)
begin
    if Units = eImperial then
        Result := MilsToCoord(Round(CoordToMils(X - Offset) / MilFactor) * MilFactor) + Offset
    else
        Result := MMsToCoord (Round(CoordToMMs (X - Offset) / MMFactor) *  MMFactor ) + Offset;
end;

function RndUnit( X : double, const Units : TUnits) : double;
// round the value w.r.t Offset (e.g. board origin)
begin
    if (Units = eImperial) then
        Result := Round(X / MilFactor) * MilFactor
    else
        Result := Round(X / MMFactor)  * MMFactor;
end;

procedure PositionRoom(Room : IPCB_ConfinementConstraint, LocationBox : TCoordRect);
var
    RoomBR    : TCoordRect;
begin
//    RoomBR   := Room.BoundingRectangle;
//
    Room.BeginModify;
    if (LocationBox.X1 = LocationBox.X2) and (LocationBox.Y1 = LocationBox.Y2) then
    begin
        Room.MoveToXY(LocationBox.X1 + BOrigin.X, LocationBox.Y2 + BOrigin.Y);
        RoomBR := Room.BoundingRect;
    end else
    begin
        RoomBR := RectToCoordRect(         //          Rect(L, T, R, B)
                  Rect(RndUnitPos(LocationBox.X1 + BOrigin.X, BOrigin.X, BUnits), RndUnitPos(LocationBox.Y2 + BOrigin.Y, BOrigin.Y, BUnits),
                       RndUnitPos(LocationBox.X2 + BOrigin.X, BOrigin.X, BUnits), RndUnitPos(LocationBox.Y1 + BOrigin.Y, BOrigin.Y, BUnits)) );
        Room.BoundingRect := RoomBR;
    end;
    Room.EndModify;

    if debug then
        Report.Add('Repositioning Room : ' + Room.Identifier + 
                   ' X1 ' + CoordUnitToString(RoomBR.X1 - BOrigin.X, BUnits) + ' Y1 ' + CoordUnitToString(RoomBR.Y1 - BOrigin.Y, BUnits) +
                   ' X2 ' + CoordUnitToString(RoomBR.X2 - BOrigin.X, BUnits) + ' Y2 ' + CoordUnitToString(RoomBR.Y2 - BOrigin.Y, BUnits) );
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

function TestRoomIsInsideBoard(Room : IPCB_Rule) : boolean;
// touching is inside BO!
var
    RuleBR : TCoordRect;

begin
{  Rule.Polygon / Outline  ;       // may have to consider
   for I := 0 To Polygon.PointCount - 1 do
   begin
   if Polygon.Segments[I].Kind = ePolySegmentLine then
}
    Result := false;
    RuleBR := Room.BoundingRect;
    Result := Result or Board.BoardOutline.GetState_StrictHitTest(RuleBR.left, RuleBR.bottom);
    Result := Result or Board.BoardOutline.GetState_StrictHitTest(RuleBR.left, RuleBR.top);
    Result := Result or Board.BoardOutline.GetState_StrictHitTest(RuleBR.right, RuleBR.bottom);
    Result := Result or Board.BoardOutline.GetState_StrictHitTest(RuleBR.right, RuleBR.top);
end;

//----------------------------------------------------------------------------------
function GetRoomPlacementTuples(RoomName : WideString, PrimOffsets : TStringList, RoomRect : TCoordRect) : boolean;
var
    OneLine    : TStringList;
    Rot        : double;
    I, J       : integer;
begin
    result := false;

    OneLine := TStringList.Create;
    OneLine.Delimiter := '|';
    OneLine.StrictDelimiter := true;
    OneLine.NameValueSeparator := '=';

{    StandoffHeight := 0;
    X1 := 0; Y2 := 0; Rot := 0;
    X2 := 0; Y2 := 0;


    for I := 0 to (PrimOffsets.Count - 1) do   // was stepfiles
    begin
        OneLine.DelimitedText := PrimOffsets.Strings(I);
        J := OneLine.IndexOfName(cCoreFNLabel);
        OffsetFN := OneLine.ValueFromIndex(J);
        OffX := OneLine.ValueFromIndex(OneLine.IndexOfName('X1'));
        OffY := OneLine.ValueFromIndex(OneLine.IndexOfName('Y1'));

    end;
}
end;

function GetRoomPlacement(RoomName : WideString, PrimOffsets : TStringList, var RoomRect : TCoordRect) : boolean;
var
    OneLine        : TStringList;
    I              : integer;
    sTemp          : WideString;
    dValue         : double;
begin
    Result := false;

    OneLine := TStringList.Create;
    OneLine.Delimiter := ',';
    OneLine.StrictDelimiter := true;

    for I := 0 to (PrimOffsets.Count - 1) do
    begin
        OneLine.DelimitedText := PrimOffsets.Strings(I);
        if (Trim(OneLine.Strings(0)) = cLabelRoomBR) and (OneLine.Count > 5) then
        begin
            if (Trim(OneLine.Strings(1)) = RoomName) then
            begin
                sTemp := OneLine.Strings(2);
//            StringToRealUnit(sTemp, dValue, BUnits);
//            dValue := StrToFloat(sTemp);
                StringToCoordUnit(sTemp, dValue, BUnits);
                RoomRect.X1 := dValue;
                sTemp := OneLine.Strings(3);
                StringToCoordUnit(sTemp, dValue, BUnits);
                RoomRect.Y1 := dValue;
                sTemp := OneLine.Strings(4);
                StringToCoordUnit(sTemp, dValue, BUnits);
                RoomRect.X2 := dValue;
                sTemp := OneLine.Strings(5);
                StringToCoordUnit(sTemp, dValue, BUnits);
                RoomRect.Y2 := dValue;
                Result := true;
                break;
            end;
        end;
        if (Trim(OneLine.Strings(0)) = cLabelRoomXY) and (OneLine.Count > 3) then
        begin
            if (Trim(OneLine.Strings(1)) = RoomName) then
            begin
                sTemp := OneLine.Strings(2);
                StringToCoordUnit(sTemp, dValue, BUnits);
                RoomRect.X1 := dValue;
                sTemp := OneLine.Strings(3);
                StringToCoordUnit(sTemp, dValue, BUnits);
                RoomRect.Y1 := dValue;
                RoomRect.X2 := RoomRect.X1;
                RoomRect.Y2 := RoomRect.Y1;
                Result := true;
                break;
            end;
        end;
    end;
end;

function LoadFile(PlacementPath : WideString) : TStringList;
var
    PrimOffsets    : TStringList;
begin
    Result := TStringList.Create;
    Result.StrictDelimiter := true;
    Result.Delimiter := #13;
    Result.LoadFromFile(PlacementPath);
end;

Procedure PositionRoomFromFile;
var
    Iterator      : IPCB_BoardIterator;
    Rule          : IPCB_Rule;
    Room          : IPCB_ConfinementConstraint;
    LocRect       : TCoordRect;
    RoomRect      : TCoordRect;
//    RoomArea      : Double;
    RoomRuleList  : TObjectList;
    OpenDialog    : TOpenDialog;
    PrimOffsets   : TStringList;
    FilePath      : WideString;
    ClassList     : TObjectList;
    CompClass     : IPCB_ObjectClass;
//    ClassSubTotal : TParameterList;
//    CSubTotal     : integer;
    I, J          : integer;
    found         : boolean;

begin
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;
    LocRect := GetBoardDetail(0);
    RoomRect := TCoordRect;

    BeginHourGlass(crHourGlass);
    RoomRuleList := TObjectList.Create;

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eRuleObject));
    Iterator.AddFilter_IPCB_LayerSet(LayerSetUtils.AllLayers);
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
//    ClassSubTotal := TParameterList.Create;
//    GetClassCompSubTotals(Board, ClassList, ClassSubTotal);

    if RoomRuleList.Count = 0 then
    begin
        ShowMessage('No Rooms found ');
        exit;
    end;

//    prompt input file
    OpenDialog        := TOpenDialog.Create(Application);
    OpenDialog.Title  := 'Load Room Placement.txt file';
    OpenDialog.Filter := 'TXT (*.txt)|*.txt';
    OpenDialog.InitialDir := ExtractFilePath(Board.FileName);
    OpenDialog.FileName := '';
    Flag := OpenDialog.Execute;
    if (Flag = 0) then exit;
    FilePath := OpenDialog.FileName;

    PrimOffsets := LoadFile(FilePath);
    if PrimOffsets.Count = 0 then
    begin
        ShowMessage('No Placement Data in file ');
        exit;
    end;

    if debug then Report.Add('Rooms Rule Count = ' + IntToStr(RoomRuleList.Count));

    for I := 0 to (RoomRuleList.Count - 1) do
    begin
        Room := RoomRuleList.Items(I);
        if debug then
            Report.Add(IntToStr(I) + ': ' + Room.Name + ', UniqueId: ' +  Room.UniqueId +
                       ', RuleType: ' + IntToStr(Room.RuleKind) + '  Layer : ' + Board.LayerName(Room.Layer) );       // + RuleKindToString(Rule.RuleKind));

//        if debug then Report.Add(IntToStr(I) + ': ' + Room.Name + ' is Inside BO');

// find the matching class
            found := false;
            J := 0;
            while (not found) and (J < ClassList.Count) do
            begin
//                CSubTotal := 0;
                CompClass := ClassList.Items(J);
//                ClassSubTotal.GetState_ParameterAsInteger(CompClass.Name, CSubTotal);

                if (CompClass.Name = Room.Identifier) and (not CompClass.SuperClass) then  // and (CSubTotal > 0)
                begin
                    found := true;
                    if debug then Report.Add('found matching Class ' + IntToStr(J) + ': ' + CompClass.Name);  // + '  Member Count = ' + IntToStr(CSubTotal));
                end;
                Inc(J);
            end;

        if debug then Report.Add('X = ' + CoordUnitToString(Room.X, BUnits) + '  Y = ' + CoordUnitToString(Room.Y, BUnits) );
        if debug then Report.Add('DSS    ' + Room.GetState_DataSummaryString);
        if debug then Report.Add('Desc   ' + Room.Descriptor);
        if debug then Report.Add('SDS    ' + Room.GetState_ScopeDescriptorString);

        if GetRoomPlacement(Room.Name, PrimOffsets, RoomRect) then
            PositionRoom(Room, RoomRect);

        if LiveUpdate then Board.ViewManager_FullUpdate;
    end;

//    CleanUpNetConnections(Board);
    EndHourGlass;

    RoomRuleList.Destroy;
//    ClassList.Destroy;

    Board.GraphicallyInvalidate;
    Board.ViewManager_FullUpdate;

    if debug then
    begin
        FileName := ChangeFileExt(Board.FileName, '.rmcrep');
        Report.SaveToFile(Filename);
        Report.Free;
    end;
    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);
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

