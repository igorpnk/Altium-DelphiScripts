{  BoardCentre.pas

BL Miller
10/07/2020  v0.10 POC
11/07/2020  v0.11 added Messages Panel due to useless PlaceLocation.
12/07/22020 v0.12 added width, height, area & perimeter

TBD
   Verify result to external reference
   Add support for board cutouts (big holes)
   Try fix (waste more hours) PlaceLocation Marks.
}

Const
    iMechLayer = 2;       // Mechanical Layer 2 == 2

// Green's Theorem
function FindCentroid(GPC : IPCB_GeometricPolygon) : TPoint;
var
    Contour     : IPCB_Contour;
    i, j        : integer;
    P1, P2, Off : TPoint;
    x, y, f     : double;
    TArea       : double;
begin
    Result := TPoint;
    i := 0;
// ignore the holes for now..
    repeat
        if not GPC.IsHole(i) then break;
        Inc(i);
    until (i >= GPC.Count);
    Contour := GPC.Contour(i);

    Off    := Point(Contour.x(0), Contour.y(0));
    TArea  := 0; f := 0;
    x      := 0; y := 0;

    for i := 0 to (Contour.Count - 1) do
    begin
        j := i + 1;
        if j >= Contour.Count  then j := 0;

        P1 := Point(Contour.x(i), Contour.y(i));
        P2 := Point(Contour.x(j), Contour.y(j));
// type cast to double
        f := CoordToMils(P1.x - Off.x) * CoordToMils(P2.y - Off.y)- CoordToMils(P2.x - Off.x) * CoordToMils(P1.y - Off.y);
        TArea := TArea + f;
        x := x + CoordToMils(P1.x + P2.x - 2 * Off.x) * f;
        y := y + CoordToMils(P1.y + P2.y - 2 * Off.y) * f;
    end;
    f := TArea * 3;
    Result := Point(MilsToCoord(x / f) + Off.x, MilsToCoord(y / f) + Off.y);
end;

function BoardOutlinePerimeter(BOL : IPCB_BoardOutline) : double;
var
    I, J           : integer;
    X1, Y1, X2, Y2 : double;
    A1, A2, A3     : double;

begin
    Result := 0;
//  Segments of a polygon
    for I := 0 to (BOL.PointCount - 1) do
    begin
        J := I + 1;
        if J = BOL.PointCount then J := 0;
        if BOL.Segments[I].Kind = ePolySegmentLine then
        begin
            X1 := BOL.Segments[I].vx;
            Y1 := BOL.Segments[I].vy;
            X2 := BOL.Segments[J].vx;
            Y2 := BOL.Segments[J].vy;
            Y2 := (Y2 - Y1) / k1Mil;      // to force double/float
            X2 := (X2 - X1) / k1Mil;
            Result := Result + SQRT((Y2*Y2) + (X2*X2));
//                Rpt.Add(' Segment Line X :  ' + PadLeft(CoordUnitToString(X1, BUnits), 15) + '  Y : ' + PadLeft(CoordUnitToString(Y1, BUnits), 15) );
        end
        else
        begin
//              Rad := P.Radius / k1Mil;
            A1 := BOL.Segments[I].Angle1;           // degrees
            A2 := BOL.Segments[I].Angle2;
            A3 := A2 - A1;
            if A3 < 0 then A3 := A3 + 360;
            X1 := BOL.Segments[I].Radius / k1Mil;   // Coord
            Result := Result + c2PI * A3 / 360 * X1;
        end;
    end;
    Result := Result * k1Mil;        // back to Coord units but float
end;

procedure LocateBoardCentre;
var
    Board      : IPCB_Board;
    BOL        : IPCB_BoardOutline;
    GPC        : IPCB_GeometricPolygon;
    BUnits     : TUnit;
    BRect      : TCoordRect;
    BOrigin    : TPoint;
    BC         : TPoint;
    Perimeter  : double; 
    WS         : IWorkSpace;
    MM         : IDXPMessagesManager;
    MMM1, MMM2 : WideString;

begin
    Board  := PCBServer.GetCurrentPCBBoard;
    if Board = nil then exit;

    BUnits := Board.DisplayUnit;
//    GetCurrentDocumentUnit;
    if (BUnits = eImperial) then BUnits := eMetric
    else BUnits := eImperial;

    BC      := TPoint;
    BOrigin := Point(Board.XOrigin, Board.YOrigin);
//    BRect := Board.BoundingRectangle;
    BRect := Board.BoardOutline.BoundingRectangle;
    BC.X  := (BRect.X1 + BRect.X2) / 2 - BOrigin.X;
    BC.Y  := (BRect.Y1 + BRect.Y2) / 2 - BOrigin.Y;

// PITA POS system DNW.
//    Client.SendMessage('PCB:Jump', 'Object=Location | Location.X=' + CoordUnitToString(BC.X, BUnits) + '| Location.Y=' + CoordUnitToString(BC.Y, BUnits), 255, Client.CurrentView);
//    Client.SendMessage('PCB:Jump', 'Object=PlaceLocation1 | Location.X=' + CoordUnitToString(BC.X, BUnits) + '| Location.Y=' + CoordUnitToString(BC.Y, BUnits), 255, Client.CurrentView);
//    Client.SendMessage('PCB:Jump', 'Object=PlaceLocation1 | CurrentLocation=true', 255, Client.CurrentView);

    WS := GetWorkSpace;
    MM := WS.DM_MessagesManager;
    MM.ClearMessages;
    WS.DM_ShowMessageView;
    MM.BeginUpdate;

    MMM1 := 'Board Origin X = ' + CoordUnitToString(BOrigin.X, BUnits) + '  | Origin Y = ' + CoordUnitToString(BOrigin.Y, BUnits);
    MMM2 := 'Object=Location | Location.X=' + CoordUnitToString(0, BUnits) + ' | Location.Y=' + CoordUnitToString(0, BUnits);
    MM.AddMessage('[Info]', 'Board Origin : ' + MMM1 , 'BoardCentre.pas', WS.DM_FocusedDocument.DM_FileName, 'PCB:Jump', MMM2, 3, false);

    MMM1 := 'Board X width   : ' + CoordUnitToString(RectWidth(BRect), BUnits) +     '  Y height ' + CoordUnitToString(RectHeight(BRect), BUnits);
    MM.AddMessage('[Info]', MMM1 , 'BoardCentre.pas', WS.DM_FocusedDocument.DM_FileName, '', '' , 3, false);

    BOL := Board.BoardOutline;

    MMM1 := 'Board Area size : ' + SqrCoordToUnitString(BOL.AreaSize, Board.DisplayUnit);
    MM.AddMessage('[Info]', MMM1 , 'BoardCentre.pas', WS.DM_FocusedDocument.DM_FileName, '', '' , 3, false);

    Perimeter := BoardOutlinePerimeter(BOL);
    MMM1 := 'Board Outline Perimeter : ' + CoordUnitToString(Perimeter, BUnits);
    MM.AddMessage('[Info]', MMM1 , 'BoardCentre.pas', WS.DM_FocusedDocument.DM_FileName, '', '' , 3, false);

    MMM1 := 'Location.X=' + CoordUnitToString(BC.X, BUnits) + ' | Location.Y=' + CoordUnitToString(BC.Y, BUnits);
    MMM2 := 'Object=Location | ' + MMM1;
    MM.AddMessage('[Info]', 'Board Bounding Rectangle Centre : ' + MMM1 , 'BoardCentre.pas', WS.DM_FocusedDocument.DM_FileName, 'PCB:Jump', MMM2, 3, false);

    GPC  := BOL.BoardOutline_GeometricPolygon;
    BC   := FindCentroid(GPC);
    BC.X := BC.X - BOrigin.X;
    BC.Y := BC.Y - BOrigin.Y;

    MMM1 := 'Location.X=' + CoordUnitToString(BC.X, BUnits) + ' | Location.Y=' + CoordUnitToString(BC.Y, BUnits);
    MMM2 := 'Object=Location | ' + MMM1;
    MM.AddMessage('[Info]', 'Board Outline Polygon Centroid  : ' + MMM1 , 'BoardCentre.pas', WS.DM_FocusedDocument.DM_FileName, 'PCB:Jump', MMM2, 3, false);
    MM.EndUpdate;
end;

{
Messages Panel Spy Report
------------------------------
MsgClass    Distance
Text        Point 1 (5400mil, 3505mil) to Point 2 (7005mil, 2095mil), Distance = 2136.381mil (54.264mm)
Source      Measurement
Document    SimplePoly.PcbDoc
MsgDateTime 12/07/2020 9:00:15 a.m.
ImageIndex  0
UserID
CallBackProcess     PCB:DisplayMeasurementLine3D
CallBackParameters  X1=54000000|Y1=35050000|Z1=0|X2=70050000|Y2=20950000|Z2=0|DISTANCE=21363813|BODYTOBOARD=0|BOARDSIDE=TOP|FILENAME=P:\Projects\PCB-Testcard-Hierarchy\SimplePoly.PcbDoc|ZOOM=-1
CallBackProcess2
CallBackParameters2
HelpFileName
HelpFileID
MsgIndex
}
