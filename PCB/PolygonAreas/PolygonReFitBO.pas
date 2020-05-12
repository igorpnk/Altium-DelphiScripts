{ PolygonReFitBO.pas
   from SolderMaskCopper02.pas

   Modify selected polygon's outline to Board Outline.

B. Miller
12/05/2020  v0.10  POC
13/05/2020  v0.11  Allow pre-selection of poly obj. Select object.

 ..............................................................................}
const
    bDisplay = false;
Var
   Board        : IPCB_Board;
   ReportLog    : TStringList;

{..............................................................................}

Function ModifyPolygonToBoardOutline(const Polygon : IPCB_Polygon) : boolean;
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

{..............................................................................}
Procedure ModifyPolygonOutline;
Var
    RepourMode      : TPolygonRepourMode;
    PolyRegionKind  : TPolyRegionKind;
    Poly            : IPCB_Polygon;
    Prim            : IPCB_Primitive;

    FileName     : TPCBString;
    Document     : IServerDocument;
    Count        : Integer;
    I, J         : Integer;

    PolyLayer    : TLayer;
    MAString     : String;

Begin
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;

    BeginHourGlass(crHourGlass);
    ReportLog    := TStringList.Create;

    //Save the current Polygon repour setting
    RepourMode := PCBServer.SystemOptions.PolygonRepour;
// Update so that Polygons always repour - avoids polygon repour yes/no dialog box popping up.
    PCBServer.SystemOptions.PolygonRepour := eAlwaysRepour;

//    Net := FindNetName('GND');
    
    Poly := nil;

    if Board.SelectecObjectCount > 0 then
    begin
        Prim := Board.SelectecObject(0);
        if Prim.ObjectId = ePolyObject then
            Poly := Prim;
    end;

    if Poly = nil then
        Poly := Board.GetObjectAtCursor(MkSet(ePolyObject),SignalLayers,'Select polygon to refit to Board Outline');

    if Poly <> nil then
    begin
        Poly.Selected := true;
        ReportLog.Add('Original Outline area : ' + SqrCoordToUnitString(Poly.AreaSize, 0, 7));
        ModifyPolygonToBoardOutline(Poly);

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

