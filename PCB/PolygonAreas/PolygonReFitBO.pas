{ PolygonReFitBO.pas
   from SolderMaskCopper02.pas

   Modify selected polygon's outline to Board Outline.
    or copy polygon outline to board outline

B. Miller
12/05/2020  v0.10  POC
13/05/2020  v0.11  Allow pre-selection of poly obj. Select object.
12/07/2020  v0.12  Make board outline from selected polygon Outline.
04/11/2020  v0.13  Clip Polygon to board outline shape.
06/11/2020  v0.14  refactor 2 func into one fn.
 ..............................................................................}

const
    bDisplay = true ; //false;
    OutlineExpansion     = 0.0;  // 30 mils from edge.
    ArcResolution        = 0.02; // mils : impacts number of edges etc..

Var
   Board        : IPCB_Board;
   BOrigin      : TPoint;
   ReportLog    : TStringList;

{..............................................................................}
Function ClipPolygonToBoardOutline(Polygon : IPCB_Polygon) : boolean;
Var
    Layer  : TLayer;
    PNet   : IPCB_Net;
    I         : Integer;
    GMPC1     : IPCB_GeometricPolygon;
    GMPC2     : IPCB_GeometricPolygon;
    GPCVL     : Pgpc_vertex_list;
    ArcRes    : float;
    Expansion : TCoord;
    Operation : TSetOperation;
    PolySeg : TPolySegment;

Begin
    Layer := Polygon.Layer;
    ReportLog.Add('Modify Polygon: ''' + Polygon.Name + ''' on Layer ''' + cLayerStrings[Layer] + '''');

    Expansion := 0; //  MilsToCoord(OutlineExpansion);
    ArcRes := ArcResolution;
    PCBServer.PCBContourMaker.SetState_ArcResolution(MilsToCoord(ArcRes));

    GMPC1 := PcbServer.PCBContourMaker.MakeContour(Polygon, Expansion, Polygon.Layer);
    GMPC2 := Board.BoardOutline.BoardOutline_GeometricPolygon;

    Operation := eSetOperation_Intersection;
    PcbServer.PCBContourUtilities.ClipSetSet (Operation, GMPC1, GMPC2, GMPC1);
    GPCVL := GMPC1.Contour(0);

    PCBServer.SendMessageToRobots(Polygon.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);

    PolySeg := TPolySegment;
    Polygon.PointCount := GPCVL.Count;
    For I := 0 To GPCVL.Count Do
    Begin
        PolySeg.Kind := ePolySegmentLine;
        PolySeg.vx   := GPCVL.x(I);
        PolySeg.vy   := GPCVL.y(I);
        Polygon.Segments[I] := PolySeg;
        ReportLog.Add(CoordUnitToString(GPCVL.x(I) - BOrigin.X ,eMils) + '  ' + CoordUnitToString(GPCVL.y(I) - BOrigin.Y, eMils) );
    End;

    Polygon.SetState_CopperPourInvalid;
    Polygon.Rebuild;
    Polygon.CopperPourValidate;

    PCBServer.SendMessageToRobots(Polygon.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
//  required to get outline area to update!
    Polygon.GraphicallyInvalidate;
End;

Function ModifyPolygonToBoardOutline(Polygon : IPCB_Polygon) : boolean;
Var
    Layer : TLayer;
    PNet  : IPCB_Net;
    I     : Integer;

Begin
    Layer := Polygon.Layer;
    ReportLog.Add('Modify Polygon: ''' + Polygon.Name + ''' on Layer ''' + cLayerStrings[Layer] + '''');

    PCBServer.SendMessageToRobots(Polygon.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);

    Polygon.PointCount := Board.BoardOutline.PointCount;
    For I := 0 To Board.BoardOutline.PointCount Do
    Begin
// if Board.BoardOutline.Segments[I].Kind = ePolySegmentLine then
// current segment is a straight line.
       Polygon.Segments[I] := Board.BoardOutline.Segments[I];
    End;

    Polygon.SetState_CopperPourInvalid;
    Polygon.Rebuild;
    Polygon.CopperPourValidate;

    PCBServer.SendMessageToRobots(Polygon.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
//  required to get outline area to update!
    Polygon.GraphicallyInvalidate;
End;

Function ModifyBoardOutlineFromPolygonOutline(const Polygon : IPCB_Polygon, var Board : IPCB_Board) : boolean;
Var
    BOL   : IPCB_BoardOutline;
    Layer : TLayer;
    PNet  : IPCB_Net;
    I     : Integer;

Begin
    Layer := Polygon.Layer;
    ReportLog.Add('Modify Board outline : ' + Board.FileName);

    BOL := Board.BoardOutline;
    PCBServer.SendMessageToRobots(BOL.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);

    BOL.PointCount := Polygon.PointCount;
    For I := 0 To Polygon.PointCount Do
    Begin
// if Board.BoardOutline.Segments[I].Kind = ePolySegmentLine then
// current segment is a straight line.
       BOL.Segments[I] := Polygon.Segments[I];
    End;

    BOL.SetState_CopperPourInvalid;
    BOL.Rebuild;
    BOL.CopperPourValidate;

    PCBServer.SendMessageToRobots(BOL.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
//  required to get outline area to update!
    BOL.GraphicallyInvalidate;
End;

{..............................................................................}
Procedure ModifyPolyOutline(const Clip : boolean);
Var
    RepourMode      : TPolygonRepourMode;
    PolyRegionKind  : TPolyRegionKind;
    Poly            : IPCB_Polygon;
    Prim            : IPCB_Primitive;

    FileName     : TPCBString;
    Document     : IServerDocument;

    PolyLayer    : TLayer;
//    MAString     : String;
    sMessage     : WideString;

Begin
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;
    BOrigin := Point(Board.XOrigin, Board.YOrigin);

    BeginHourGlass(crHourGlass);
    ReportLog    := TStringList.Create;

    //Save the current Polygon repour setting
    RepourMode := PCBServer.SystemOptions.PolygonRepour;
// Update so that Polygons always repour - avoids polygon repour yes/no dialog box popping up.
    PCBServer.SystemOptions.PolygonRepour := eAlwaysRepour;

    Poly := nil;

    if Board.SelectecObjectCount > 0 then
    begin
        Prim := Board.SelectecObject(0);
        if Prim.ObjectId = ePolyObject then
            Poly := Prim;
    end;

    sMessage := 'Select polygon to refit to Board Outline';
    if Clip then sMessage := 'Select polygon to refit to Board Outline';

    if Poly = nil then
        Poly := Board.GetObjectAtCursor(MkSet(ePolyObject),SignalLayers, sMessage);

    if Poly <> nil then
    begin
        Poly.Selected := true;
        ReportLog.Add('Original Outline area : ' + SqrCoordToUnitString(Poly.AreaSize, 0, 7));

        if (not Clip)  then
            ModifyPolygonToBoardOutline(Poly)
        else
            ClipPolygonToBoardOutline(Poly);

        ReportLog.Add('Refitted Outline area : ' + SqrCoordToUnitString(Poly.AreaSize, 0, 7));
    end;

    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);

    //Revert back to previous user polygon repour option.
    PCBServer.SystemOptions.PolygonRepour := RepourMode;

// test if PCB boardfile not saved.
    Filename := ExtractFilePath(Board.Filename);
    if Filename = '' then
        Filename := SpecialFolder_Temporary;

    FileName := Filename + ChangeFileExt(ExtractFileName(Board.FileName), '.txt');

    ReportLog.SaveToFile(Filename);
    ReportLog.Free;

    EndHourGlass;

    Document  := Client.OpenDocument('Text', FileName);
    If (bDisplay) and (Document <> Nil) Then
    begin
        Client.ShowDocument(Document);
        if (Document.GetIsShown <> 0 ) then
            Document.DoFileLoad;
    end;
End;

Procedure ModifyPolygonOutline;
var
    Clip : boolean;
begin
    Clip := false;
    ModifyPolyOutline(Clip);
end;
Procedure ClipPolygonOutline;
var
    Clip : boolean;
begin
    Clip := true;
    ModifyPolyOutline(Clip);
end;

{..............................................................................}
Procedure ModifyBoardOutline;
Var
    RepourMode      : TPolygonRepourMode;
    PolyRegionKind  : TPolyRegionKind;
    Poly            : IPCB_Polygon;
    Prim            : IPCB_Primitive;

    FileName     : TPCBString;
    Document     : IServerDocument;

    PolyLayer    : TLayer;
//    MAString     : String;

Begin
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;

    BeginHourGlass(crHourGlass);
    ReportLog    := TStringList.Create;

    //Save the current Polygon repour setting
    RepourMode := PCBServer.SystemOptions.PolygonRepour;
// Update so that Polygons always repour - avoids polygon repour yes/no dialog box popping up.
    PCBServer.SystemOptions.PolygonRepour := eAlwaysRepour;

    Poly := nil;

    if Board.SelectecObjectCount > 0 then
    begin
        Prim := Board.SelectecObject(0);
        if Prim.ObjectId = ePolyObject then
            Poly := Prim;
    end;

    if Poly = nil then
        Poly := Board.GetObjectAtCursor(MkSet(ePolyObject),SignalLayers,'Select polygon to Change Board Outline');

    if Poly <> nil then
    begin
        Poly.Selected := true;
        ReportLog.Add('Original Board Outline area : ' + SqrCoordToUnitString(Board.BoardOutline.AreaSize, 0, 7));

        ModifyBoardOutlineFromPolygonOutline(Poly, Board);
        ReportLog.Add('Resized Board Outline area : ' + SqrCoordToUnitString(Board.BoardOutline.AreaSize, 0, 7));
    end;

    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);

    //Revert back to previous user polygon repour option.
    PCBServer.SystemOptions.PolygonRepour := RepourMode;

// test if PCB boardfile not saved.
    Filename := ExtractFilePath(Board.Filename);
    if Filename = '' then
        Filename := SpecialFolder_Temporary;

    FileName := Filename + ChangeFileExt(ExtractFileName(Board.FileName), '.txt');

    ReportLog.SaveToFile(Filename);
    ReportLog.Free;

    EndHourGlass;

    Document  := Client.OpenDocument('Text', FileName);
    If (bDisplay) and (Document <> Nil) Then
    begin
        Client.ShowDocument(Document);
        if (Document.GetIsShown <> 0 ) then
            Document.DoFileLoad;
    end;
End;


