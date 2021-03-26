{ MakeExtrudedBody.pas     (from OutLiner.pas)

  for Pcbdoc.

  Create ComponentBody Extruded model(s) or just Regions from selected region or polygon
  Polygon (solid) child regions are used not the polyline outline.

25/09/2020 v0.01 POC working.
26/09/2020 v0.10 use PCB current layer for new model if is Mechanical else use defined const iMechLayer
06/11/2020 v0.20 added support for output Regions onto any current layer
05/03/2021 v0.21 Can pre-select (multiple obj) or run with no selection (single obj); works in PcbLib.

Units for IPCB_Model are MickeyMouse(TM)

Note this script :-
- does not handle intersecting/overlapping/merging of expanded shapes.
- can make regions of hatched polygons but NOT merged.

}

Const
    iMechLayer           = 13;   // Mechanical Layer 13 == 13  used for Comp Body if current layer <> type mech-layer
    OutlineExpansion     = 0.0;  // 0 mils from edge.
    ArcResolution        = 0.02; // mils : impacts number of edges etc..

    olTrack  = 1;
    olRegion = 2;
    olBody   = 3;
    olRoom   = 4;

Var
   WSM             : IWorkSpace;
   Doc             : IDocument;
   CurrentLib      : IPCB_Library;
   Board           : IPCB_Board;
   BUnits          : TUnit;
   BOrigin         : TCoordPoint;
   ReportLog       : TStringList;

procedure SaveReportLog(FileExt : WideString, const display : boolean);
var
    FileName     : TPCBString;
    Document     : IServerDocument;
begin
    FileName := ChangeFileExt(Board.FileName, FileExt);
    if ExtractFilePath(FileName) = '' then FileName := 'c:\temp\' + FileName;
    ReportLog.SaveToFile(Filename);

    Document  := Client.OpenDocument('Text', FileName);
    If display and (Document <> Nil) Then
    begin
        Client.ShowDocument(Document);
        if (Document.GetIsShown <> 0 ) then
            Document.DoFileLoad;
    end;
end;

function AddExtrudedBodyToBoard(GPC : IPCB_GeometricPolygon, const Layer : TLayer, const UIndex : integer, const MainContour : boolean) : IPCB_ComponentBody;
var
    CompModel      : IPCB_Model;
    StandoffHeight : Integer;
    OVAHeight      : integer;
    Colour         : TColor;

begin
    Result := PcbServer.PCBObjectFactory(eComponentBodyObject, eNoDimension, eCreate_Default);
    PCBServer.SendMessageToRobots(Result.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);

    StandoffHeight := 0;
    Colour := clBlue;
    StringToRealUnit('5mm', OVAHeight, eMM);

    Result.BodyProjection := eBoardSide_Top;
    Result.Layer := Layer;
    Result.BodyOpacity3D := 1;
    Result.BodyColor3D := Colour;
    Result.StandoffHeight := StandoffHeight;
    Result.OverallHeight  := OVAHeight;
    Result.Kind           := eRegionKind_Copper;        // necessary ??

    if (MainContour) then
        Result.SetOutlineContour( GPC.Contour(0) )
    else
        Result.GeometricPolygon := GPC;

    if Assigned(Result.Model) Then
    begin
        CompModel := Result.ModelFactory_CreateExtruded(StandoffHeight, OVAheight, Colour);
        if Assigned(CompModel) then
        begin
            // SOHeight := MMsToCoord(StandoffHeight);
            CompModel.SetState(0,0,0,0);          // (RotX, RotY, RotZ, SOHeight);
            Result.SetModel(CompModel);
        end;
    end;

    Result.UnionIndex := UIndex;
//     Result.MoveToXY(MilsToCoord(1500) + OffX, MilsToCoord(500) + OffY);

    Board.AddPCBObject(Result);
    PCBServer.SendMessageToRobots(Result.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
    PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Result.I_ObjectAddress);
    Result.GraphicallyInvalidate;

    Result.Selected := true;
    ReportLog.Add('Added New Extruded Body on Layer ' + Layer2String(Result.Layer) + ' kind : ' + IntToStr(Result.Kind) + '  area ' + SqrCoordToUnitString(Result.Area , eMM, 6) );
end;

function AddRegionToBoard(GPC : IPCB_GeometricPolygon, Net : IPCB_Net, const Layer : TLayer, const UIndex : integer, const MainContour : boolean) : IPCB_Region;
var
    GPCVL  : Pgpc_vertex_list;
begin
    Result := PCBServer.PCBObjectFactory(eRegionObject, eNoDimension, eCreate_Default);
    PCBServer.SendMessageToRobots(Result.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);

    if MainContour then
        Result.SetOutlineContour( GPC.Contour(0) )
    else
        Result.GeometricPolygon := GPC;

    Result.SetState_Kind(eRegionKind_Copper);
    Result.Layer := Layer;
    Result.Net   := Net;
    Result.UnionIndex := UIndex;

    Board.AddPCBObject(Result);
    PCBServer.SendMessageToRobots(Result.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
    PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Result.I_ObjectAddress);

    Result.Selected := true;
    ReportLog.Add('Added New Region on Layer ' + Layer2String(Result.Layer) + ' kind : ' + IntToStr(Result.Kind) + '  area ' + SqrCoordToUnitString(Result.Area , eMM, 6) ); // + '  net : ' + Result.Net.Name);
end;

function MakeContourShapes(MaskObjList : TObjectList, Operation : TSetOperation, Layer : TLayer, Expansion : Tcoord) : TInterfaceList;
var
    GMPC1         : IPCB_GeometricPolygon;
//    GMPC2         : IPCB_GeometricPolygon;
    RegionVL      : Pgpc_vertex_list;
    Primitive     : IPCB_Primitive;
    TrkPrim       : IPCB_Primitive;
    GIterator     : IPCB_GroupIterator;
    Region        : IPCB_Region;
    Fill          : IPCB_Fill;
    Polygon       : IPCB_Polygon;
    I, J, K       : integer;

begin
    Result := TInterfaceList.Create;  // GPOL needed for non PCB objs & batch contour fn

    GMPC1 := PcbServer.PCBGeometricPolygonFactory;

//    PcbServer.PCBContourMaker.SetState_ArcResolution := MilsToCoord(0.5); // very strange result if > 1
    PCBServer.PCBContourMaker.SetState_ArcResolution(MilsToCoord(ArcResolution));

    for I := 0 to (MaskObjList.Count - 1) Do
    begin
        Primitive := MaskObjList.Items[I];
        if Primitive <> Nil then
        begin

//            PolyRegionKind := eRegionKind_Copper;          // ePolyRegionKind_Copper, ePolyRegionKind_Cutout, eRegionKind_cutout
            case Primitive.ObjectID of
                eRegionObject :
                begin
                    Region := Primitive;
//                    if (Region.Kind = eRegionKind_Copper) and not (Region.InPolygon or Region.IsKeepout ) then  //  and Region.InComponent
                    if not Region.InPolygon then
                    begin
                        GMPC1 := PcbServer.PCBContourMaker.MakeContour(Region, Expansion, Layer);
                        Result.Add(GMPC1);
                    end;
                end;
                ePolyObject :
                begin
                    Polygon := Primitive;
                    GIterator := Polygon.GroupIterator_Create;
                    if (Polygon.PolyHatchStyle = ePolySolid) and (Polygon.InBoard ) then  //  and Region.InComponent
                    begin
                        Region    := GIterator.FirstPCBObject;
                        while Region <> nil do
                        begin
                            GMPC1 := PcbServer.PCBContourMaker.MakeContour(Region, Expansion, Layer);
                            Result.Add(GMPC1);
                            Region := GIterator.NextPCBObject;
                        end;
//                        GMPC1 := PcbServer.PCBContourMaker.MakeContour(Polygon, Expansion, Layer);
                    end;
                    if (Polygon.PolyHatchStyle <> ePolyNoHatch) and (Polygon.PolyHatchStyle <> ePolySolid) and (Polygon.InBoard ) then  //  and Region.InComponent
                    begin
                        TrkPrim     := GIterator.FirstPCBObject;
                        while TrkPrim <> nil do    // track or arc
                        begin
                            if (TrkPrim.ObjectId = eTrackObject) or (trkPrim.ObjectId = eArcObject) then
                            begin
                                GMPC1 := PcbServer.PCBContourMaker.MakeContour(TrkPrim, 0, Polygon.Layer);  //GPG
                                Result.Add(GMPC1);
                            end;
                            TrkPrim := GIterator.NextPCBObject;
                        end;
                    end;
                    Polygon.GroupIterator_Destroy(GIterator);
                end;
                eFillObject :
                begin
                    Fill := Primitive;
                    GMPC1 := PcbServer.PCBContourMaker.MakeContour(Fill, Expansion, Layer);
                    Result.Add(GMPC1);
                end;
            end; // case

            ReportLog.Add(PadRight(IntToStr(I), 3) + Primitive.ObjectIDString + ' ' + Primitive.Detail);
            for J := 0 to (GMPC1.Count - 1) do
            begin
                RegionVL   := GMPC1.Contour(J);
                ReportLog.Add(Padright(IntToStr(J), 3) + 'VL count ' + IntToStr(RegionVL.Count));
                for K := 0 to (RegionVL.Count - 1) do
                    ReportLog.Add(CoordUnitToString(RegionVL.x(K) - BOrigin.X ,eMils) + '  ' + CoordUnitToString(RegionVL.y(K) - BOrigin.Y, eMils) );
            end;
        end;
    end;  // for I
end;

procedure OutLiner(const Shape : integer);
Var
    BoardIterator : IPCB_BoardIterator;
    Primitive      : IPCB_Primitive;
    Region         : IPCB_Region;
    CompBody       : IPCB_ComponentBody;

    GPOL           : TInterfaceList;         // required for non PCB objects passed to external fn.
    GMPC1          : IPCB_GeometricPolygon;
    Expansion      : TCoord;
    Layer          : TLayer;
    ML             : TLayer;
    MLayer         : IPCB_MechanicalLayer;
    I, J, K        : Integer;
    MaskObjList    : TObjectList;
    PObjSet        : TSet;
    UnionIndex     : integer;
    FYI            : WideString;
    IsLib          : boolean;
    HasHoles       : boolean;
    dConfirm       : boolean;

begin
    Doc := GetWorkSpace.DM_FocusedDocument;
    if not ((Doc.DM_DocumentKind = cDocKind_PcbLib) or (Doc.DM_DocumentKind = cDocKind_Pcb)) Then
    begin
         ShowMessage('No PcbDoc or PcbLib selected. ');
         Exit;
    end;
    IsLib  := false;
    if (Doc.DM_DocumentKind = cDocKind_PcbLib) then
    begin
        CurrentLib := PCBServer.GetCurrentPCBLibrary;
        Board := CurrentLib.Board;
        IsLib := true;
    end else
        Board  := PCBServer.GetCurrentPCBBoard;

    if ((Board = nil) and (CurrentLib = nil)) then
    begin
        ShowError('Failed to find PcbDoc or PcbLib.. ');
        exit;
    end;

    BOrigin := Point(Board.XOrigin, Board.YOrigin);
    BUnits := Board.DisplayUnit;
    if (BUnits = eImperial) then BUnits := eMetric
    else BUnits := eImperial;
    GetCurrentDocumentUnit;
    GetRunningScriptProjectName;

    ReportLog   := TStringList.Create;
    MaskObjList := TObjectList.Create;

// code for using const defined layer   hint: make Layer := ML !!
    ML     := LayerUtils.MechanicalLayer(iMechLayer);
    MLayer := Board.LayerStack_V7.LayerObject_V7[ML];
    Layer  := Board.CurrentLayer;        // ML;

// only allow ComponentBody on Mechanical layer
    if (Shape = olBody) then
        if not LayerUtils.IsMechanicalLayer((Layer)) then
            Layer := ML;

// support regions & polygon regions (exclude keepouts?)
    PObjSet := MkSet(eRegionObject, ePolyObject);

// make a primitive object list & then loop & test & generate contours.
    MaskObjList.Clear;

    for I := 0 to (Board.SelectedObjectsCount - 1) do
    begin
        Primitive := Board.SelectecObject(I);
        if InSet(Primitive.ObjectId, PObjSet ) then
            MaskObjList.Add(Primitive);
    end;

    if (MaskObjList.Count = 0) then
    begin
        Primitive := Board.GetObjectAtCursor(PObjSet, SignalLayers, 'Choose Poly/Region ');
        if Primitive <> nil then MaskObjList.Add(Primitive);
    end;

    Expansion := MilsToCoord(OutlineExpansion);
    GPOL := MakeContourShapes(MaskObjList, 0, Layer, Expansion);

    if (GPOL.Count > 0) then
    begin
        PcbServer.PreProcess;
        ReportLog.Add(' Added Shape Contour  Vertex count ');

        UnionIndex := GetHashID_ForString(GetWorkSpace.DM_GenerateUniqueID);
//        UnionIndex := IBoardUnionManager.FindUnusedUnionIndex;

        HasHoles := false;
        dConfirm := false;

// if shape has multiple contours ask if only biggest area?
        for I := 0 to (GPOL.Count - 1) do
        begin
            FYI := '';
            GMPC1 := GPOL.Items(I);
            if GMPC1.Count > 1 then FYI := 'One outline shape has 2 or more contours. ';

            for J := 0 to (GMPC1.Count - 1) do
            begin
                HasHoles := HasHoles or GMPC1.IsHole(J);
            end;

            if (not dConfirm) and (HasHoles) then
                dConfirm := ConfirmNoYesWithCaption('Shape Has Holes ','Just keep the outside shape ? ');

            if (Shape = olBody) then
                CompBody := AddExtrudedBodyToBoard(GMPC1, Layer, UnionIndex, dConfirm);

            if (Shape = olRegion) then
                AddRegionToBoard(GMPC1, nil, Layer, UnionIndex, dConfirm);

            ReportLog.Add(PadRight(IntToStr(I),2) + '  :  ' + IntTostr(GMPC1.Count) );
        end;

        PcbServer.PostProcess;
    end;
    GPOL.Clear;

    Board.CurrentLayer := Layer;
//    Client.SendMessage('PCB:SetCurrentLayer', 'Layer=' + IntToStr(Layer) , 255, Client.CurrentView);
    Board.ViewManager_UpdateLayerTabs;
    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);
    SaveReportLog('-MExBody.txt', false);
end;

// main entry points
procedure OutXBodys;
begin
    OutLiner(olBody);
end;
procedure OutXRegions;
begin
    OutLiner(olRegion);
end;


