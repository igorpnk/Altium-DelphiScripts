{..............................................................................
 SolderMaskOnMechLayer.pas
   from SolderMaskTracks02.pas

   Make (+ve) soldermask on mechanical layer(s).
   Sliver removal option.
   Optional expansion.
   Can use auto mask expansions & direct primitives on SM layer.
   Can rerun Top & Bottom SM separately/repeated.

   Existing soldermask shapes used.
   Supports:
   Pad & Via
   Region (inc polygon parts)
   Track & Arc
   Fill
   String

   Electrical clearances are NOT applied to polygons on mask layer (or mech)
      100% board outline poly pour with regions for selected objects.
      Can not add SM shapes as only use polygon poured as region shape..
      Use mask expansion rules for pads & pad regions.


B. Miller
05/02/2021  v1.01  from original SolderMaskTracks -/+ve mech layer mask

 ..............................................................................}

Const
    cSMPolyNeck         = 2 ;     // mils
    cArcApproximation   = 0.1;    //mils
    cExtraExpansion     = 0;      //mils          this is not useable because of UGLY HACK
    cSMSliverRemoval    = true;   // true or false ONLY.

// to support ugly mech layer mess above eMech 24/32, these will have to change to value j = [8,  9]
// and code to use  LayerUtils.MechanicalLayer(j);
    cScratchPadTop         = eMechanical8;      // mech layers with no regions or poly (or cutouts)
    cScratchPadBottom      = eMechanical9;

    mmInch = 25.4;
    ePolyRegionKind_Cutout = 1;
    cMaskPolygonNameTop    = '__TempOutlinePolygonTop__';    // allows retain BOTH top & bottom mask outputs together.
    cMaskPolygonNameBot    = '__TempOutlinePolygonBot__';
    cTempPolyName          = '__TempTrkMaskPoly___';

Var
   Board        : IPCB_Board;
   ReportLog    : TStringList;
   WSM          : IWorkSpace;
   AExpansion   : TCoord;


{..............................................................................}

Function MakeNewPolygonRegion(PGPC : IPCB_GeometricPolygon, OutLayer : TLayer, const PolyRegionKind : TPolyRegionKind; UIndex : integer) : IPCB_Region;
Var
    I      : Integer;
    Fill        : IPCB_Fill;
    Poly        : IPCB_Polygon;
    Region      : IPCB_Region;
    Pad         : IPCB_Pad;

Begin
    Result := PCBServer.PCBObjectFactory(eRegionObject, eNoDimension, eCreate_Default);
    PCBServer.SendMessageToRobots(Result.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);

    Result.GeometricPolygon := PGPC;
//    Result.SetOutlineContour(PGPC.Contour[0]);
    Result.Layer := OutLayer;
    Result.SetState_Kind(PolyRegionKind);
    Result.Kind  := PolyRegionKind;
    Result.UnionIndex := UIndex;

    Board.AddPCBObject(Result);

    PCBServer.SendMessageToRobots(Result.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
    PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Result.I_ObjectAddress);
End;

Function AddPolygonToBoard(GPC : IPCB_GeometricPolygon; const PolygonName : WideString; PNet : IPCB_Net; Layer : TLayer, UIndex : integer) : IPCB_Polygon;
Var
    I       : Integer;
    Reg     : IPCB_Region;
    GPCVL   : Pgpc_vertex_list;
    PolySeg : TPolySegment;

Begin
    ReportLog.Add('NewPolygon: ''' + PolygonName + ''' on Layer ''' + cLayerStrings[Layer] + '''');
    //Update so that Polygons always repour - avoids polygon repour yes/no dialog box popping up.
    PCBServer.SystemOptions.PolygonRepour := eAlwaysRepour;

    Result := PCBServer.PCBObjectFactory(ePolyObject, eNoDimension, eCreate_Default);
    PCBServer.SendMessageToRobots(Result.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);
    Result.Name                := PolygonName;
    Result.Layer               := Layer;
    Result.PolyHatchStyle      := ePolySolid;
    Result.NeckWidthThreshold  := MilsToCoord(cSMPolyNeck);
    Result.RemoveNarrowNecks   := cSMSliverRemoval;
    Result.RemoveIslandsByArea := False;
    Result.ArcApproximation    := MilsToCoord(cArcApproximation);
    Result.RemoveDead          := False;
    Result.PourOver            := ePolygonPourOver_SameNet;  //  ePolygonPourOver_SameNetPolygon;
    Result.AvoidObsticles      := false;
    Result.Net                 := PNet;
    Result.UnionIndex          := UIndex;

    GPCVL := GPC.Contour(0);                   // refed to absolute
    Result.PointCount := GPCVL.Count;

    PolySeg := TPolySegment;
    for I := 0 to GPCVL.Count do
    begin
       PolySeg.Kind := ePolySegmentLine;
       PolySeg.vx   := GPCVL.x(I);
       PolySeg.vy   := GPCVL.y(I);
       Result.Segments[I] := PolySeg;
//       ReportLog.Add(CoordUnitToString(GPCVL.x(I) - BOrigin.X ,eMils) + '  ' + CoordUnitToString(GPCVL.y(I) - BOrigin.Y, eMils) );
    end;

    Board.AddPCBObject(Result);
    Result.SetState_CopperPourInvalid;
    Result.Rebuild;
    Result.CopperPourValidate;

    PCBServer.SendMessageToRobots(Result.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
    PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Result.I_ObjectAddress);
end;

procedure SortPrimList(MOL : TObjectList);
var
    Primitive     : IPCB_Primitive;
    Primitive2    : IPCB_Primitive;
    I, J, K       : integer;
    Rank1, Rank2  : integer;
    ObjectId      : integer;
begin
    For I := 0 to (MOL.Count - 2) Do
    Begin
        For J := 0 to (MOL.Count - 2 - I) Do
        begin
            Primitive :=  MOL.Items(J);
            Primitive2 := MOL.Items(J+1);
            for K := 0 to 1 do
            begin
                if K = 0 then ObjectId := Primitive.ObjectId
                else           ObjectId := Primitive2.ObjectId;

                case ObjectID of
                eTextObject   : Rank2 := 1;
                ePolyObject   : Rank2 := 2;
                eTrackObject  : Rank2 := 3;
                eArcObject    : Rank2 := 4;
                eFillObject   : Rank2 := 5;
                eViaObject    : Rank2 := 6;
                eRegionObject : Rank2 := 7;
                ePadObject    : Rank2 := 8;
                end; //case
                if K = 0 then Rank1 := Rank2;
            end; // K
            if Rank2 > Rank1 then MOL.Exchange(J+1,J);
        end;     // J
    end;         //I
end;

Function MakeNewBoardOutlinePolygon(const PolygonName : string; Layer : TLayer; PNet : IPCB_Net) : IPCB_Polygon;
Var
    I          : Integer;

Begin
    ReportLog.Add('MakeNewPolygon: ''' + PolygonName + ''' on Layer ''' + cLayerStrings[Layer] + '''');

    Result := PCBServer.PCBObjectFactory(ePolyObject, eNoDimension, eCreate_Default);

    PCBServer.SendMessageToRobots(Result.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);

    Result.Name                := PolygonName;
    Result.Layer               := Layer;
    Result.PolyHatchStyle      := ePolySolid;
    Result.RemoveIslandsByArea := false;
    Result.RemoveNarrowNecks   := cSMSliverRemoval;
    Result.NeckWidthThreshold  := MilsToCoord(cSMPolyNeck);
    Result.ArcApproximation    := MilsToCoord(cArcApproximation);
    Result.RemoveDead          := false;
    Result.PourOver            := ePolygonPourOver_None;
    Result.AvoidObsticles      := true; // false;
    Result.Net                 := PNet;

    Result.PointCount := Board.BoardOutline.PointCount;
    For I := 0 To Board.BoardOutline.PointCount Do
    Begin
// if .Segments[I].Kind = ePolySegmentLine then is a straight line.
       Result.Segments[I] := Board.BoardOutline.Segments[I];
    End;

    Board.AddPCBObject(Result);

    Result.SetState_CopperPourInvalid;
    Result.Rebuild;
    Result.CopperPourValidate;

    PCBServer.SendMessageToRobots(Result.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
    PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, Result.I_ObjectAddress);
End;

function RegionArea(Region : IPCB_Region) : Double;
var
   Area : Double;
   i    : Integer;

begin
  Area := Region.MainContour.Area;
  for i := 0 to (Region.HoleCount - 1) do
      Area := Area - Region.Holes[i].Area;
  Result := Area;
end;

Function PolygonArea(Poly : IPCB_Polygon) : Double;
Var
    Region  : IPCB_Region;
    GIter   : IPCB_GroupIterator;

Begin
    if Poly.PolyHatchStyle <> ePolySolid then
    begin
        Result := 0;  //Poly.AreaSize;
        exit;
    end;

    GIter  := Poly.GroupIterator_Create;
    Region := GIter.FirstPCBObject;

    While Region <> nil do
    begin
        Result := Result + RegionArea(Region);
        Region := GIter.NextPCBObject;
    end;
    Poly.GroupIterator_Destroy(GIter);
End;

function RemoveUnionObjects(UIndex : Integer; Layers : TSet) : boolean;
var
    BIterator : IPCB_BoardIterator;
    Primitive    : IPCB_Primitive;
    MaskObjList  : TObjectList;
    J            : integer;
begin
    Result := false;
    MaskObjList := TObjectList.Create;
    BIterator := Board.BoardIterator_Create;

    BIterator.AddFilter_ObjectSet(MkSet(ePolyObject, eRegionObject));   // (eRegionObject, ePadObject, ePolyObject, eFillObject));
    BIterator.AddFilter_LayerSet(AllLayers);
    BIterator.AddFilter_Method(eProcessAll);

    Primitive := BIterator.FirstPCBObject;
    while (Primitive <> Nil) do
    begin
        if (Primitive.UnionIndex = UIndex) and InSet(Primitive.Layer, Layers) then
            MaskObjList.Add(Primitive);
        Primitive := BIterator.NextPCBObject;
    end;
    Board.BoardIterator_Destroy(BIterator);

    For J := 0 to (MaskObjList.Count - 1) Do
    Begin
        Primitive := MaskObjList.Items[J];
        Board.RemovePCBObject(Primitive);
    end;
    MaskObjList.Destroy;
end;

function RemoveMaskPolyAndUnionRegions(MaskPolyName : WideString, OutLayer : TLayer) : boolean;
var
    BIterator : IPCB_BoardIterator;
    Polygon       : IPCB_Polygon;
    UnionIndex    : Integer;

begin
    Result := false;
// remove any previous/pre-existing polygon mask & region pieces including on SolderMask layers.
    BIterator := Board.BoardIterator_Create;
    BIterator.AddFilter_ObjectSet(MkSet(ePolyObject));
    BIterator.AddFilter_LayerSet(AllLayers);          // useless above eMech24.
    BIterator.AddFilter_Method(eProcessAll);

    Polygon := BIterator.FirstPCBObject;
    while (Polygon <> Nil) Do
    Begin
       if (Polygon.Name = MaskPolyName) and (Polygon.Layer = OutLayer) then
       begin
           UnionIndex := Polygon.UnionIndex;
           Board.RemovePCBObject(Polygon);
           Result := true;
           ReportLog.Add('Deleted existing Polygon : ' + Polygon.Name);
           if UnionIndex <> 0 then
               RemoveUnionObjects(UnionIndex, MkSet(OutLayer, eTopSolder, eBottomSolder));
       end;
       Polygon := BIterator.NextPCBObject;
    end;

    Board.BoardIterator_Destroy(BIterator);
end;

function MakeRegionFromPoly (Poly : IPCB_Polygon, Expansion : TCoord, Layer : TLayer, const PolyRegionKind : TPolyRegionKind, Invert : boolean, UIndex : integer) : TObjectList;
// invert is just ignore first contour of each shape & outline area.
var
    GIterator   : IPCB_GroupIterator;
    Region      : IPCB_Region;
    NewRegion   : IPCB_Region;
    GMPC, GMPC2 : IPCB_GeometricPolygon;
    Net         : IPCB_Net;
    I           : integer;
begin
    Result := TObjectList.Create;
    Net    := Poly.Net;
//  poly (solid) can be composed of multiple regions  or lines & arcs (hatched)
    GIterator  := Poly.GroupIterator_Create;
    Region := GIterator.FirstPCBObject;
    while Region <> nil do
    begin
//  holes are extra contours in GeoPG
        GMPC  := PcbServer.PCBContourMaker.MakeContour(Region, Expansion, Layer);
        GMPC2 := PcbServer.PCBGeometricPolygonFactory;    // empty geopoly.

        if Invert then
        begin
            for I := 1 to (GMPC.Count - 1) do
                GMPC2.Addcontour(GMPC.Contour(I));
        end else
            GMPC2 := GMPC1;

        if GMPC2.Count > 0 then
        begin
            NewRegion := PCBServer.PCBObjectFactory(eRegionObject, eNoDimension, eCreate_Default);
            PCBServer.SendMessageToRobots(NewRegion.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);

            NewRegion.GeometricPolygon := GMPC2;
            NewRegion.SetState_Kind(PolyRegionKind);
            NewRegion.Layer := Layer;
            if Net <> Nil then NewRegion.Net := Net;
            NewRegion.UnionIndex := UIndex;
            Board.AddPCBObject(NewRegion);
            Result.Add(NewRegion);

            PCBServer.SendMessageToRobots(NewRegion.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
            PCBServer.SendMessageToRobots(Board.I_ObjectAddress, c_Broadcast, PCBM_BoardRegisteration, NewRegion.I_ObjectAddress);
        end;
        Region := GIterator.NextPCBObject;
    end;
    Poly.GroupIterator_Destroy(GIterator);
end;

{..............................................................................}
Procedure MakeSolderMask(const Dummy : boolean; const Layer : TLayer);
Var
    RepourMode    : TPolygonRepourMode;
    Stack         : IPCB_LayerStack;
    BoardIterator : IPCB_BoardIterator;
    Primitive     : IPCB_Primitive;

    MaskArea      : Double;  // mask pour area without PCO
    MaskWPCOArea  : Double;  // mask pour area with poly cut outs.
    PolyArea      : Double;  // draw full extent area/size of poly.

// temp poly to find area of max pour..
    TempPoly          : IPCB_Polygon;
    TempMaskPolygon   : IPCB_Polygon;
    TempMaskRegion    : IPCB_Region;
    GMPC1             : IPCB_GeometricPolygon;

    PolyRegionKind    : TPolyRegionKind;
    MakeRegion        : boolean;

    Fill        : IPCB_Fill;
    Poly        : IPCB_Polygon;
    Region      : IPCB_Region;
    Pad         : IPCB_Pad;
    Via         : IPCB_Via;
    Track       : IPCB_Track;
    Arc         : IPCB_Arc;
    Text        : IPCB_Text;
    Net         : IPCB_Net;
    SMEX        : TCoord;
    MaskEnabled : boolean;

    MaskObjList  : TObjectList;    // all valid mask objects
    MaskPolyName : WideString;
    UnionIndex   : integer;
    FileName     : TPCBString;
    Document     : IServerDocument;
    Count        : Integer;
    I, J         : Integer;
    InsideBO     : Boolean;

    InLayer      : TLayer;             // alt. source
    OutLayer     : TLayer;             // target output
    PolyLayer    : TLayer;
    LayerSet     : TSet;
    MAString     : String;

Begin
    // Retrieve the current board
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;
    Stack := Board.LayerStack;

    BeginHourGlass(crHourGlass);

    ReportLog    := TStringList.Create;
    MaskObjList  := TObjectList.Create;

    // mech layer to output shapes on.. & cache poly & UnionIndex for cleanup
    OutLayer     := cScratchPadTop;             // LayerUtils.MechanicalLayer(j)
    MaskPolyName := cMaskPolygonNameTop;
    InLayer      := eTopSolder;
    if (Layer = eBottomLayer) then
    begin
        InLayer      := eBottomSolder;
        OutLayer     := cScratchPadBottom;
        MaskPolyName := cMaskPolygonNameBot;
    end;

    UnionIndex := 0;

// clean out previous run mask poly & region pieces (cutouts & solid) 
    RemoveMaskPolyAndUnionRegions(MaskPolyName, OutLayer);

    MaskArea := 0; MaskWPCOArea := 0;
    TempMaskPolygon             := nil;

    //Save the current Polygon repour setting
    RepourMode := PCBServer.SystemOptions.PolygonRepour;
// Update so that Polygons always repour - avoids polygon repour yes/no dialog box popping up.
    PCBServer.SystemOptions.PolygonRepour := eAlwaysRepour;

    Net := nil;
    UnionIndex := GetHashID_ForString(GetWorkSpace.DM_GenerateUniqueID);

    TempMaskPolygon := MakeNewBoardOutlinePolygon(MaskPolyName, OutLayer, Net);
    TempMaskPolygon.UnionIndex := UnionIndex;

    MaskArea := PolygonArea(TempMaskPolygon);
    MAString := FormatFloat(',0.####',(MaskArea) / (k1Inch * k1Inch / mmInch / mmInch));
    ReportLog.Add('Polygon : ' + TempMaskPolygon.Name + ' ' + MAString + 'sqmm');
    TempMaskPolygon.Enabled := false;

// polygon are handled by rendered region object

    MaskObjList.Clear;

    BoardIterator := Board.BoardIterator_Create;
    BoardIterator.AddFilter_ObjectSet(MkSet(ePadObject, eViaObject, eTrackObject, eArcObject, eRegionObject, eFillObject, eTextObject));   // (ePolyObject, eFillObject));
    LayerSet := MkSet(Layer, InLayer, eMultiLayer);
    BoardIterator.AddFilter_LayerSet(AllLayers);
    BoardIterator.AddFilter_Method(eProcessAll);

    Primitive := BoardIterator.FirstPCBObject;
    While (Primitive <> Nil) Do
    Begin
      InsideBO := Board.BoardOutline.GetState_HitPrimitive (Primitive);
      MakeRegion := false;

      if InsideBO and InSet(Primitive.Layer, LayerSet) then
      begin
        case Primitive.ObjectID of
          eFillObject :
          begin
              Fill := Primitive;
//              if Fill.Layer = Layer then MakeRegion := true;
              MakeRegion := true;
          end;

          eTextObject :        // no auto masks
          begin
              Text := Primitive;
              if Text.Layer = InLayer then MakeRegion := true;
          end;

          eTrackObject :
          begin
              Track := Primitive;
//              if Track.Layer = Layer then MakeRegion := true;
              MakeRegion := true;
    //          if Track.InPolygon then MakeRegion := false;      // hatched polygons !
          end;
          eArcObject :
          begin
              Arc := Primitive;
//              if Arc.Layer = Layer then MakeRegion := true;
              MakeRegion := true;
    //          if Arc.InPolygon then MakeRegion := false;      // hatched polygons !
          end;

          ePadObject :
          begin    // check for actual drawn pad on Layer layer
              Pad := Primitive;
              if Pad.Mode = ePadMode_Simple then
              begin
                  if ((Pad.Layer = Layer) or (Pad.Layer = eMultilayer)) then
                      MakeRegion := true;
              end
              else
                  if Pad.StackShapeOnLayer(Layer) then   // Pad.Component.Descriptor;
          //    if Pad.Mode = ePadMode_ExternalStack then
          //        if (Pad.XStackSizeOnLayer[Layer] = 0) or (Pad.YStackSizeOnLayer[Layer] = 0) Then
                      MakeRegion := true;
          end;

          eViaObject :
          begin    // check for actual drawn pad on Layer layer
              Via := Primitive;
//              if Via.Mode = ePadMode_Simple then
//              begin

                  if (Via.IntersectLayer(Layer) or (Via.Layer = eMultilayer) ) then
                  // test for expansions.
                       MakeRegion := true;
          end;

//   only interested in rendered primitives of polygons
          ePolyObject :    // make sure not our temp poly!
          begin
              Poly := Primitive;
              if Poly.Name <> MaskPolyName then
                  MakeRegion := true;
              MakeRegion := False;
          end;

          eRegionObject :    // make sure not poly cutout
          begin
              Region := Primitive;           // for component FP
              Region.IsSimpleRegion;         // true
              Region.InNet;                  // true (what if pin is NoNet??)

              MakeRegion := False;
//       pad region
              if (Region.Layer = Layer) then
              begin
                  if (Region.Kind = eRegionKind_Copper) and (Region.InComponent) then
                      MakeRegion := true;
//       polygon copper.
                  if Region.InPolygon then
                      MakeRegion := True;
              end;

//       free region copper
              if (not Region.InComponent) and (not Region.InPolygon) then
                  MakeRegion := True;
//      on soldermask layer
              if (Region.Layer = InLayer) then
                  MakeRegion := True;

              if Region.Name = 'Default Layer Stack Region' then
                  MakeRegion := False;
              if Region.Kind  = eRegionKind_BoardCutout then MakeRegion := False;
              if Region.Kind  = ePolyRegionKind_Cutout  then MakeRegion := False;
              if Region.Layer = eMultiLayer then             MakeRegion := False;
          end;
        end; //case

        if MakeRegion then
            MaskObjList.Add(Primitive);

      end;  // inside board outline
      Primitive := BoardIterator.NextPCBObject;
    end;
    Board.BoardIterator_Destroy(BoardIterator);

// need do pads first so dam poly is not constrained by polycutouts.
    SortPrimList(MaskObjList);

// make the new cutouts in polygon
// tracks & arc   : are poly cutouts with expansion
// pads & vias    : exp correctly handled by internal operation
// copper regions : poly cutouts has auto SM mask then expand shape.

    ReportLog.Add('MakePolyRegion from  Prim : in layer :        onto layer :     RegionKind : ');
    AExpansion := MilsToCoord(0);

    PcbServer.PCBContourMaker.ArcResolution := MilsToCoord(cArcApproximation);

    For I := 0 to (MaskObjList.Count - 1) Do
    Begin
        MakeRegion  := false;
        MaskEnabled := false;

        Primitive := MaskObjList.Items[I];
        Layer := Primitive.Layer;
//  have to go to top or bottom copper pad & get expansion etc??
//  lets try mask expansion layers
        if Layer = eTopLayer    then InLayer := eTopSolder;
        if Layer = eBottomLayer then InLayer := eBottomSolder;

//        InLayer := Layer;
        if Primitive <> Nil then
        begin
//            PolyRegionKind := eRegionKind_Copper;          // ePolyRegionKind_Copper
            PolyRegionKind := ePolyRegionKind_Cutout;      // eRegionKind_cutout
            SMEX := Primitive.GetState_SolderMaskExpansion;
            AExpansion := MilsToCoord(cExtraExpansion);

            case Primitive.ObjectID of
            eTextObject :
              begin
                  Text := Primitive;
                  if (Text.Layer = InLayer) then MakeRegion := true;
//                  InLayer := Layer;
                  GMPC1 := PCBServer.PCBContourMaker.MakeContour (Text, AExpansion, InLayer);
              end;

            eTrackObject :
              begin
                  Track := Primitive;
                  MakeRegion := true;
//                  InLayer := Layer;
                  SMEX        := Track.GetState_SolderMaskExpansion;
                  MaskEnabled := Track.GetState_SolderMaskExpansionMode;
                  AExpansion := MilsToCoord(cExtraExpansion) + SMEX;
                  if (MaskEnabled <> eMaskExpansionMode_NoMask) or (Track.Layer = InLayer) then
                      GMPC1 := PCBServer.PCBContourMaker.MakeContour (Track, AExpansion, InLayer)
                  else
                      MakeRegion := false;
              end;

            eArcObject :
              begin
                  Arc := Primitive;
                  MakeRegion := true;
//                  InLayer := Layer;
                  SMEX        := Arc.GetState_SolderMaskExpansion;
                  MaskEnabled := Arc.GetState_SolderMaskExpansionMode;
                  AExpansion  := MilsToCoord(cExtraExpansion) + SMEX;
                  if (MaskEnabled <> eMaskExpansionMode_NoMask)  or (Arc.Layer = InLayer) then
                      GMPC1 := PCBServer.PCBContourMaker.MakeContour (Arc, AExpansion, InLayer)
                  else
                      MakeRegion := false;
              end;

            eRegionObject :
              begin
                  Region      := Primitive;
                  SMEX        := Region.GetState_SolderMaskExpansion;
                  MaskEnabled := Region.GetState_SolderMaskExpansionMode;
                  AExpansion  := MilsToCoord(cExtraExpansion) + SMEX;

// cutouts holes
                  if Region.Kind  = eRegionKind_BoardCutout then
                      MakeRegion := true;

                  if (Region.Kind = eRegionKind_Copper) then
                  begin
//           free regions
                      if (not Region.InComponent) then
                      begin
                          MakeRegion := true;
                          Region.Layer;
                      end;
//           polygon regions
//           pad regions
                      if (Region.InComponent) and (not Region.InPolygon) then
                          MakeRegion := true;
                  end;

                  if (MaskEnabled = eMaskExpansionMode_NoMask) and (Region.Layer <> InLayer) then
                      MakeRegion := false;

                  if (MakeRegion) then
                      GMPC1 := PCBServer.PCBContourMaker.MakeContour (Region, AExpansion, InLayer);
              end;

            eFillObject :
              begin
                  Fill := Primitive;
                  SMEX        := Fill.GetState_SolderMaskExpansion;
                  MaskEnabled := Fill.GetState_SolderMaskExpansionMode;
                  AExpansion  := MilsToCoord(cExtraExpansion) + SMEX;
                  MakeRegion := true;
                  if (MaskEnabled <> eMaskExpansionMode_NoMask) or (Region.Layer = InLayer) then
                      MakeRegion := true;
                  GMPC1 := PCBServer.PCBContourMaker.MakeContour (Fill, AExpansion, InLayer);
              end;

            ePadObject :
              begin
                  Pad := Primitive;
                  MakeRegion := true;
                  GMPC1 := PCBServer.PCBContourMaker.MakeContour (Pad, AExpansion, InLayer);
              end;

            eViaObject  :
              begin
                  Via := Primitive;
                  MakeRegion := true;
                  GMPC1 := PCBServer.PCBContourMaker.MakeContour (Via, AExpansion, InLayer);
              end;
            end;

            if MakeRegion then
            begin
                TempMaskRegion := MakeNewPolygonRegion(GMPC1, OutLayer, PolyRegionKind, UnionIndex);
                ReportLog.Add(PadRight(Primitive.ObjectIDString,16) + '  '  +  PadRight(cLayerStrings[OutLayer],16) + '  ' + IntToStr(PolyRegionKind));
            end;
        end;
    end;    // for I
    MaskObjList.Destroy;


// re pour the full mask polygon.
    if (TempMaskPolygon <> Nil) then
    Begin
        TempMaskPolygon.Enabled := true;
        PCBServer.SendMessageToRobots(TempMaskPolygon.I_ObjectAddress, c_Broadcast, PCBM_BeginModify, c_NoEventData);

        TempMaskPolygon.SetState_CopperPourInvalid;
        TempMaskPolygon.Rebuild;
        TempMaskPolygon.CopperPourValidate;

        PCBServer.SendMessageToRobots(TempMaskPolygon.I_ObjectAddress, c_Broadcast, PCBM_EndModify, c_NoEventData);
        TempMaskPolygon.GraphicallyInvalidate;

        MaskWPCOArea := PolygonArea(TempMaskPolygon);
//           PolyArea := TempMaskPolygon.AreaSize;
        MAString := FormatFloat(',0.####',(MaskWPCOArea) / (k1Inch * k1Inch / mmInch / mmInch));
        ReportLog.Add('Polygon : ' + TempMaskPolygon.Name + ' with cutouts ' + MAString + 'sqmm');
    end;


// Explode Polygon from mech layer to regions on solderMask
//    if (Layer = eTopLayer) then InLayer := eTopSolder;
//    if (Layer = eBottomLayer) then InLayer := eBottomSolder;
//    MakeRegionFromPoly (TempMaskPolygon, 0, InLayer, eRegionKind_Copper, true, UnionIndex); // fn TObjectList;


    Board.LayerIsDisplayed(OutLayer) := True;
    Client.SendMessage('PCB:SetCurrentLayer', 'Layer=' + IntToStr(OutLayer) , 255, Client.CurrentView);
    Client.SendMessage('PCB:Zoom', 'Action=Redraw', 255, Client.CurrentView);

     // PolyArea := Board.BoardOutline.AreaSize ;
    MAString := FormatFloat(',0.####',(MaskArea - MaskWPCOArea) / (k1Inch * k1Inch / mmInch / mmInch));
    ShowMessage(Layer2String(Layer) + ' : ' + MAString + 'sqmm');

    //Revert back to previous user polygon repour option.
    PCBServer.SystemOptions.PolygonRepour := RepourMode;

    FileName := ChangeFileExt(Board.FileName,'.txt');
    ReportLog.SaveToFile(Filename);
    ReportLog.Free;

    EndHourGlass;

    Document  := Client.OpenDocument('Text', FileName);
//    If Document <> Nil Then
//        Client.ShowDocument(Document);
 End;

Procedure SolderMaskTop;
begin
    MakeSolderMask(True, eTopLayer);      
end;
Procedure SolderMaskBottom;
begin
    MakeSolderMask(True, eBottomLayer);
end;
{
Procedure NoTrackSolderMaskTop(dummy : integer);
begin
    MakeSolderMask(false, eTopLayer);   
end;
Procedure NoTrackSolderMaskBottom(dummy : integer);
begin
    MakeSolderMask(false, eBottomLayer);
end;
}
Procedure PurgeClean;
begin
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;
    ReportLog    := TStringList.Create;

//    if (TempMaskPolyClearanceRule <> nil) then
//        Board.RemovePCBObject(TempMaskPolyClearanceRule);

// clean out previous mask poly & region (& poly) pieces (cutouts & solid)
    RemoveMaskPolyAndUnionRegions(cMaskPolygonNameTop, cScratchPadTop);
    RemoveMaskPolyAndUnionRegions(cMaskPolygonNameBot, cScratchPadBottom);
    ReportLog.Free;
end;


{..............................................................................}

{ IPCB_MakeContour method
(IPCB_ContourMaker interface)
Syntax
Function MakeContour(APrim   : IPCB_Primitive; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(ATrack  : IPCB_Track    ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(APad    : IPCB_Pad      ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(AFill   : IPCB_Fill     ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(AVia    : IPCB_Via      ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(AArc    : IPCB_Arc      ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(ARegion : IPCB_Region   ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(AText   : IPCB_Text     ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(APoly   : IPCB_Polygon  ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
}

{
     Region.InPolygon   ;
     Region.IsSimpleRegion   ;
     Region.IsKeepout;
     Region.Kind  ;   //TRegionKind

  TPolyRegionKind = ( ePolyRegionKind_Copper,
                    ePolyRegionKind_Cutout,
                    ePolyRegionKind_NamedRegion);

TPolygonType = ( eSignalLayerPolygon,
                 eSplitPlanePolygon);
}
{..............................................................................}
