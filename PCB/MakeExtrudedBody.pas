{ MakeExtrudedBody.pas     (from OutLiner.pas)

  for Pcbdoc.

  Create ComponentBody Extruded model(s) from selected region or polygon
  Polygon (solid) child regions are used not the polyline outline.

25/09/2020 v0.01 POC working.
26/09/2020 v0.10 use PCB current layer for new model if is Mechanical else use defined const iMechLayer

Units for IPCB_Model are MickeyMouse(TM)

}

Const
    iMechLayer           = 13;   // Mechanical Layer 13 == 13  NOT USED
    OutlineExpansion     = 0.0;  // 0 mils from edge.
    ArcResolution        = 0.1; // mils : impacts number of edges etc..

Var
   WSM             : IWorkSpace;
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

function MakeContourShapes(MaskObjList : TObjectList, Operation : TSetOperation, Layer : TLayer, Expansion : Tcoord) : TInterfaceList;
var
    GMPC1         : IPCB_GeometricPolygon;
    GMPC2         : IPCB_GeometricPolygon;
    RegionVL      : Pgpc_vertex_list;
    Primitive     : IPCB_Primitive;
    GIterator     : IPCB_GroupIterator;
    Region        : IPCB_Region;
    Fill          : IPCB_Fill;
    Polygon       : IPCB_Polygon;
    I, J, K       : integer;

begin
    Result := TInterfaceList.Create;  // GPOL needed for non PCB objs & batch contour fn
    GMPC1 := nil;
    GMPC2 := nil;

//    PcbServer.PCBContourMaker.ArcResolution := MilsToCoord(0.5); // very strange result if > 1
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
                    if (Region.Kind = eRegionKind_Copper) and not (Region.InPolygon or Region.IsKeepout ) then  //  and Region.InComponent
                    begin
                        GMPC1 := PcbServer.PCBContourMaker.MakeContour(Region, Expansion, Layer);
                        Result.Add(GMPC1);
                    end;
                end;
                ePolyObject :
                begin
                    Polygon := Primitive;
                    if (Polygon.PolyHatchStyle = ePolySolid) and (Polygon.InBoard ) then  //  and Region.InComponent
                    begin
                        GIterator := Polygon.GroupIterator_Create;
                        Region    := GIterator.FirstPCBObject;
                        while Region <> nil do
                        begin
                            GMPC1 := PcbServer.PCBContourMaker.MakeContour(Region, Expansion, Layer);
                            Result.Add(GMPC1);
                            Region := GIterator.NextPCBObject;
                        end;
                        Polygon.GroupIterator_Destroy(GIterator);
//                        GMPC1 := PcbServer.PCBContourMaker.MakeContour(Polygon, Expansion, Layer);
                    end;
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
    UnionIndex     : integer;
    FYI            : WideString;
    HasHoles       : boolean;
    dConfirm       : boolean;

begin
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;
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
    Layer  := Board.CurrentLayer;

    if not LayerUtils.IsMechanicalLayer((Layer)) then
        Layer := ML;

   //   make a primitive object list & then loop & test & generate contours.
    MaskObjList.Clear;

// support regions & polygon regions (exclude keepouts?)
    BoardIterator := Board.BoardIterator_Create;
    BoardIterator.AddFilter_ObjectSet(MkSet(eRegionObject, ePolyObject));
    BoardIterator.AddFilter_LayerSet(AllLayers);      // MkSet(Layer));   added Vias!
    BoardIterator.AddFilter_Method(eProcessAll);

    Primitive := BoardIterator.FirstPCBObject;
    while (Primitive <> Nil) do
    begin
        if Primitive.Selected then
        begin
            MaskObjList.Add(Primitive);
        end;
        Primitive := BoardIterator.NextPCBObject;
    end;
    Board.BoardIterator_Destroy(BoardIterator);

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

            if (Shape = eComponentBodyObject) then
                CompBody := AddExtrudedBodyToBoard(GMPC1, Layer, UnionIndex, dConfirm);

            ReportLog.Add(PadRight(IntToStr(I),2) + '  :  ' + IntTostr(GMPC1.Count) );
        end;

        PcbServer.PostProcess;
    end;
    GPOL.Clear;

    Client.SendMessage('PCB:SetCurrentLayer', 'Layer=' + IntToStr(Layer) , 255, Client.CurrentView);
    SaveReportLog('-MExBody.txt', false);
end;

// main entry points
procedure OutXBodys;
begin
    OutLiner(eComponentBodyObject);
end;


