{..............................................................................
 RefPlaneRegion-fn-MakeRegionFromPoly.pas

Summary:

B. Miller   Ver  Comment
12/12/2019  0.10 Function copied from RefPlaneRegion 0.25

 ..............................................................................}

Var
   Board         : IPCB_Board;

function MakeRegionFromPoly (Poly : IPCB_Polygon, Expansion : TCoord, Layer : TLayer) : TObjectList;
var
    GIterator  : IPCB_GroupIterator;
    Region     : IPCB_Region;
    NewRegion  : IPCB_Region;
    GMPC       : IPCB_GeometricPolygon;
    Net        : IPCB_Net;
begin
    Result := TObjectList.Create;
    Net    := Poly.Net;
//  poly can be composed of multiple regions
    GIterator  := Poly.GroupIterator_Create;
    Region := GIterator.FirstPCBObject;
    while Region <> nil do
    begin
//  holes are extra contours in GeoPG
        GMPC := PcbServer.PCBContourMaker.MakeContour(Region, Expansion, Layer);
//        GMPC.Count;
        NewRegion := PCBServer.PCBObjectFactory(eRegionObject, eNoDimension, eCreate_Default);
        NewRegion.GeometricPolygon := GMPC;
        NewRegion.SetState_Kind(eRegionKind_Copper);
        NewRegion.Layer := Layer;
        if Net <> Nil then NewRegion.Net := Net;
        Board.AddPCBObject(NewRegion);
        Result.Add(NewRegion);

        Region := GIterator.NextPCBObject;
    end;
    Poly.GroupIterator_Destroy(GIterator);
end;

{..............................................................................}

{
// alt code path when my MakeRegionFromPoly() did not work.
if (false) then
begin    // use builtin Explode process call
//  help guarantee the UI dialog targets the right object.
        ConfigPCBFilter('Apply=True|Expr=IsPolygon|Mask=True|Zoom=False|Select=False');

        TempPoly.Selected := true;
        Client.SendMessage('PCB:GroupPrimitives', 'Action=Explode | Object=Polygon | ContextObject=Polygon', 256, Client.CurrentView);

        ConfigPCBFilter('Clear=True|Expr=All|Zoom=False|Select=False|Mask=False');
end;
}

{

 eSetOperation_Union
 eSetOperation_Intersect  ??
 eSetOperation_Except ??

    PCBServer.PCBContourUtilities.ClipContourContour(eSetOperation_Union, incont1, inContour2, outgpc);
    PCBServer.PCBContourUtilities.ClipSetContour(eSetOperation_Union, ingpc, inContour, outgpc);
    PcbServer.PCBContourUtilities.ClipSetSet(eSetOperation_Union, ingpc, outgpc, outgpc);
    PointInRegion := PcbServer.PCBContourUtilities.PointInContour(RegContour.Contour(0), TargetX, TargetY);

IPCB_ContourMaker interface
Function MakeContour(APrim   : IPCB_Primitive; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(ATrack  : IPCB_Track    ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(APad    : IPCB_Pad      ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(AFill   : IPCB_Fill     ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(AVia    : IPCB_Via      ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(AArc    : IPCB_Arc      ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(ARegion : IPCB_Region   ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(AText   : IPCB_Text     ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;
Function MakeContour(APoly   : IPCB_Polygon  ; AExpansion : TCoord; ALayer : TLayer) : Pgpc_Polygon;



TPolyRegionKind = ( ePolyRegionKind_Copper,
                    ePolyRegionKind_Cutout,
                    ePolyRegionKind_NamedRegion);

TPolygonType = ( eSignalLayerPolygon,
                 eSplitPlanePolygon);

The segments property denotes the array of segments used to construct a polygon.
Each segment consists of a record consisting of one group of points in X, Y coordinates as a line (ePolySegmentline type)
 or an arc, a radius and two angles ( ePolySegmentArc type).
Each segment record has a Kind field which denotes the type of segment it is.

A segment of a polygon either as an arc or a track is encapsulated as a TPolySegment record as shown below;
TPolySegment = Record
      Kind      : TPolySegmentType;
//  Vertex
      vx,vy      : TCoord;
//  Arc
      cx,cy      : TCoord;
      Radius     : TCoord;
      Angle1     : TAngle;
      Angle2     : TAngle;
End;

{..............................................................................}
