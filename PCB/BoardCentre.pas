{  BoardCentre.pas

BL Miller
10/07/2020  v0.10 POC
11/07/2020  v0.11 added Messages Panel due to useless PlaceLocation.

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

procedure GotoBoardCentre;
var
    Board   : IPCB_Board;
    GPC     : IPCB_GeometricPolygon;
    BUnits  : TUnit;
    BRect   : TCoordRect;
    BOrigin : TPoint;
    BC      : TPoint;
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
    GetWorkspace.
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

    MMM1 := 'Location.X=' + CoordUnitToString(BC.X, BUnits) + ' | Location.Y=' + CoordUnitToString(BC.Y, BUnits);
    MMM2 := 'Object=Location | ' + MMM1;
    MM.AddMessage('[Info]', 'Board Bounding Rectangle Centre : ' + MMM1 , 'BoardCentre.pas', WS.DM_FocusedDocument.DM_FileName, 'PCB:Jump', MMM2, 3, false);

    GPC  := Board.BoardOutline.BoardOutline_GeometricPolygon;
    BC   := FindCentroid(GPC);
    BC.X := BC.X - BOrigin.X;
    BC.Y := BC.Y - BOrigin.Y;

    MMM1 := 'Location.X=' + CoordUnitToString(BC.X, BUnits) + ' | Location.Y=' + CoordUnitToString(BC.Y, BUnits);
    MMM2 := 'Object=Location | ' + MMM1;
    MM.AddMessage('[Info]', 'Board Outline Polygon Centroid  : ' + MMM1 , 'BoardCentre.pas', WS.DM_FocusedDocument.DM_FileName, 'PCB:Jump', MMM2, 3, false);
    MM.EndUpdate;
end;

