{ PolygonAreas2.pas
  Reports poly outline & poured copper area of all polygons in board.

from webpage
 https://techdocs.altium.com/display/SCRT/PCB+API+Design+Objects+Interfaces

 InternalUnits:
     InternalUnits = 10000;
 k1Inch:
     k1Inch = 1000 * InternalUnits;
Notes
1 mil = 10000 internal units
1 inch = 1000 mils
1 inch = 2.54 cm
1 inch = 25.4 mm and 1 cm = 10 mm

Author B.L. Miller
22/10/2019  v1.1 Added copper area & sub region & hole info
31/01/2020  v1.2 Bugfix: totalarea was not zeroed before reuse. Use board units.
17/01/2021  v1.3 iterating pass vertexlist count.

}
Const
    bDebug = false;
    mmInch = 25.4;

Var
    Rpt     : TStringList;
    Board   : IPCB_Board;
    BUnits  : TUnit;

function RegionArea(Region : IPCB_Region) : Double;
var
   Area : Double;
   i    : Integer;
begin
  Area := Region.MainContour.Area;
 // Area := Region.Contour(0).Area;
  Rpt.Add('  HoleCount ' + IntToStr(Region.HoleCount) );
  for i := 0 to (Region.HoleCount - 1) do
     Area := Area - Region.Holes[i].Area;
  Result := Area;
end;

function PolyHatchStyleToStr(HS : TPolyHatchStyle) : WideString;
begin
    case HS of
    ePolyHatch90, ePolyHatch45, ePolyVHatch, ePolyHHatch :
                   Result := 'Hatched';
    ePolyNoHatch : Result := 'No Hatch';
    ePolySolid   : Result := 'Solid';
    else
        Result := '';
    end;
end;

function PerimeterOutline (GP : IPCB_GeometricPolygon) : extended;
var
    GPVL : Pgpc_vertex_list;
     X1,Y1,X2,Y2 : extended;
    I, J : integer;
    L    : extended;
begin
    Result := 0;
    GPVL := PcbServer.PCBContourFactory;
    I := GP.Count;
    repeat
        dec(I);
    until (I = 0) or (GP.IsHole(I) = false);
    GPVL := GP.Contour(I);
    GPVL;
    for I:= 0 to (GPVL.Count - 1) do
    begin
        J := I + 1;
        if J = GPVL.Count then J := 0;
        X1 :=  GPVL.x(I) / k1Mil;
        Y1 :=  GPVL.y(I) / k1Mil;
        X2 :=  GPVL.x(J) / k1Mil;
        Y2 :=  GPVL.y(J) / k1Mil;
        L := Power(X2 -  X1, 2) + Power(Y2 -  Y1, 2);
        L := SQRT(L);     // / k1Mil;
        Result := Result + (L * k1Mil);
    end;
end;

Procedure PolygonsAreas;
Var
    Iterator   : IPCB_BoardIterator;
    GIter      : IPCB_GroupIterator;
    Prim       : IPCB_Primitive;
    ObjectID   : TObjectId;
    Polygon    : IPCB_Polygon;
    Region     : IPCB_Region;
//    Fill       : IPCB_Fill;
    PObjList   : TInterfaceList;
    GMPC1      : IPCB_GeometricPolygon;
    GMPC2      : IPCB_GeometricPolygon;
    RegionVL   : Pgpc_vertex_list;

    PrimCount     : integer;
    TrackCount    : integer;
    ArcCount      : integer;
    CopperArea    : extended;
    TotalArea     : extended;
    CPerimeter    : extended;  // copper
    TotCPerimeter : extended;
    Perimeter     : extended;
    TotPerimeter  : extended;

    FileName    : TPCBString;
    Document    : IServerDocument;
    PolyNo      : Integer;
    I,J,K,L     : Integer;
    X1,Y1,X2,Y2 : extended;
    A1, A2, A3  : extended;

Begin
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;

    BUnits := Board.DisplayUnit;
// something very flaky around this property..
//    if (BUnits = eImperial) then BUnits := eMetric
//    else BUnits := eImperial;

    // Search for Polygons and for each polygon found
    // get its attributes and put them in a TStringList object
    // to be saved as a text file.
    PObjList := TInterfaceList.Create;

    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(ePolyObject));
    Iterator.AddFilter_LayerSet(AllLayers);       // alt. SignalLayers    ??
    Iterator.AddFilter_Method(eProcessAll);

    PolyNo     := 0;
    Rpt := TStringList.Create;
    Rpt.Add(' Board Area size : ' + SqrCoordToUnitString(Board.BoardOutline.AreaSize, BUnits) ); // FloatToStr(Board.BoardOutline.AreaSize / SQR(k1Inch) + ' sq in'));
    Rpt.Add('');

    Polygon := Iterator.FirstPCBObject;
    While (Polygon <> Nil) Do
    Begin
        PObjList.Clear;
        BUnits := Board.DisplayUnit;

        Inc(PolyNo);
        Rpt.Add('Polygon No : '     + IntToStr(PolyNo));
        Rpt.Add(' Name : '          + Polygon.Name);
        Rpt.Add(' Detail : '        + Polygon.Detail);
        Rpt.Add(' Layer : '         + Board.LayerName(Polygon.Layer)  + ' -  ' + Layer2String(Polygon.Layer) );
        Rpt.Add(' Hatch Style : '   + PolyHatchStyleToStr(Polygon.PolyHatchStyle) );

        If Polygon.Net <> Nil Then
            Rpt.Add(' Net : '     + Polygon.Net.Name);

        If Polygon.PolygonType = eSignalLayerPolygon Then
            Rpt.Add(' Type : '     + 'Polygon on Signal Layer')
        Else
            Rpt.Add(' Type : '     + 'Split plane polygon');

        Rpt.Add(' BorderWidth : '  + CoordUnitToString(Polygon.BorderWidth ,BUnits) );     //  FloatToStr(Polygon.BorderWidth));

        Perimeter := 0;
        // Segments of a polygon
        For I := 0 To (Polygon.PointCount - 1) Do
        Begin
            J := I + 1;
            if (J = Polygon.PointCount) then J := 0;

            if Polygon.Segments[I].Kind = ePolySegmentLine then
            begin
                X1 := Polygon.Segments[I].vx;
                Y1 := Polygon.Segments[I].vy;
                X2 := Polygon.Segments[J].vx;
                Y2 := Polygon.Segments[J].vy;
                Y2 := (Y2 - Y1) / k1Mil;
                X2 := (X2 - X1) / k1Mil;
                Perimeter := Perimeter + SQRT((Y2*Y2) + (X2*X2));
                Rpt.Add(' Segment Line X :  ' + PadLeft(CoordUnitToString(X1, BUnits), 15) + '  Y : ' + PadLeft(CoordUnitToString(Y1, BUnits), 15) );
            end
            else begin
//              Rad := P.Radius / k1Mil;
                A1 := Polygon.Segments[I].Angle1;
                A2 := Polygon.Segments[I].Angle2;
                A3 := A2 - A1;
                if A3 < 0 then A3 := A3 + 360;
                X1 := Polygon.Segments[I].Radius / k1Mil;
                Perimeter := Perimeter + c2PI * A3 / 360 * X1;

                Rpt.Add(' Segment Arc 1  : ' + FloatToStr(A1) );
                Rpt.Add(' Segment Arc 2  : ' + FloatToStr(A2) );
                X1 := X1 * k1Mil;
                Rpt.Add(' Segment Radius : ' + CoordUnitToString(X1, BUnits) );

            End;
        End;
        Perimeter := Perimeter * k1Mil;
        Rpt.Add(' Border Perimeter : ' + CoordUnitToString(Perimeter, BUnits) );

        Rpt.Add('');
        PrimCount := Polygon.GetPrimitiveCount(AllObjects);
        Rpt.Add(' Prim (All types) Count : '  + IntToStr(PrimCount));


        BUnits := Board.DisplayUnit;
        if (BUnits = eImperial) then BUnits := eMetric
        else BUnits := eImperial;

        TrackCount := 0;
        ArcCount   := 0;
        CopperArea := 0;
        TotalArea := 0;
        TotCPerimeter := 0;
        I := 0; J := 0;

        GIter := Polygon.GroupIterator_Create;
        if (Polygon.PolyHatchStyle = ePolySolid) then
        begin
            Prim     := GIter.FirstPCBObject;
            while Prim <> nil do
            begin
                Inc(I);
                Rpt.Add('    Prim ' + PadRight(IntToStr(I),3) +  '  type ' + Prim.ObjectIDString  );

                if Prim.ObjectId = eRegionObject then
                begin
                    Region := Prim;

                    Inc(J);
                    CopperArea := RegionArea(Region);
                    TotalArea := TotalArea + CopperArea;
                    Rpt.Add('  Region ' + IntToStr(J) + ' area ' + SqrCoordToUnitString(CopperArea, BUnits) );
                end;
                Prim := GIter.NextPCBObject;
            end;

        end
        else if (Polygon.PolyHatchStyle <> ePolyNoHatch) then
        begin
            Prim     := GIter.FirstPCBObject;
            while Prim <> nil do    // track or arc
            begin
                Inc(I);
                if bDebug then Rpt.Add('    Prim ' + PadRight(IntToStr(I),3) +  '  type ' + Prim.ObjectIDString  );
                if Prim.ObjectId = eTrackObject then inc(TrackCount);
                if Prim.ObjectId = eArcObject   then inc(ArcCount);
                if (Prim.ObjectId = eTrackObject) or (Prim.ObjectId = eArcObject) then
                begin
                    GMPC1 := PcbServer.PCBContourMaker.MakeContour(Prim, 0, Polygon.Layer);  //GPG
                    PObjList.Add(GMPC1);
//                    Region := Prim;
                    Inc(J);
                end;
                Prim := GIter.NextPCBObject;
            end;

            if bDebug then Rpt.Add(' Shape GeoPoly Union ');
            if (PObjList.Count > 0) then
            begin
                GMPC2 := PcbServer.PCBGeometricPolygonFactory;
//            UnionGP := GPOL.Items[0];
                K := 0; L := 1;
                while K < (PObjList.Count - 1) and (K < L) do
                begin
                    GMPC1 := PObjList.Items[K];
                    GMPC2 := PObjList.Items[L];

                    if PcbServer.PCBContourUtilities.GeometricPolygonsTouch(GMPC1, GMPC2) then
                    begin                                         // Operation
                        PcbServer.PCBContourUtilities.ClipSetSet (eSetOperation_Union, GMPC1, GMPC2, GMPC1);

                        if bDebug then Rpt.Add('    touch : ' + IntToStr(K) + '.' + IntToStr(L) + ' ' + IntTostr(GMPC1.Count) + ' ' + IntTostr(GMPC1.Contour(0).Count) );
                        PObjList.Items(K) := GMPC1;
                        PObjList.Delete(L);          // inserting & deleting changes index of all object above
                        K := 0;                      // start again from beginning
                        L := 1;
                    end else
                    begin
                        if bDebug then Rpt.Add(' no touch : ' + IntToStr(K) + '.' + IntToStr(L) );
                        Inc(L);
                        if L >= (PObjList.Count) then
                        begin
                            inc(K);
                            L := K + 1;
                        end;
                    end;
                end;
                if bDebug then Rpt.Add('');
            end;

            Rpt.Add(' tracks ' + IntToStr(TrackCount) + ' ,   arcs ' + IntToStr(ArcCount) );

            for K := 0 to (PObjList.Count - 1) do
            begin
                GMPC1 := PObjList.Items[K];
             //  Area := GMPC1.Contour(0).Area;
                CopperArea := GMPC1.Area;    // copper region area.
                TotalArea := TotalArea + CopperArea;
                TotCPerimeter := TotCPerimeter + PerimeterOutline(GMPC1);
                Rpt.Add('  Region ' + IntToStr(K) + ' area ' + SqrCoordToUnitString(CopperArea, BUnits) );
            end;

//            TotCPerimeter := TotCPerimeter + CPerimeter;

        end
        else if Polygon.PolyHatchStyle = ePolyNoHatch then
        begin
 //           Area  := Polygon.GetState_AreaSize;
            CopperArea := 0;
        end;

        Polygon.GroupIterator_Destroy(GIter);

        Rpt.Add('');
        Rpt.Add(' Poly Area    : '    + SqrCoordToUnitString(Polygon.AreaSize, BUnits) );     // FloatToStr(Polygon.AreaSize / SQR(k1Inch / mmInch) ));
        Rpt.Add(' Cu   Area    : '    + SqrCoordToUnitString(TotalArea, BUnits) );            // FloatToStr(TotalArea / SQR(k1Inch / mmInch) ));
        BUnits := Board.DisplayUnit;
        Rpt.Add(' Cu Perimeter : '    + CoordUnitToString(TotCPerimeter, BUnits) );            // FloatToStr(TotalArea / SQR(k1Inch / mmInch) ));
        Rpt.Add('');
        Rpt.Add('');
        Polygon := Iterator.NextPCBObject;
    End;
    Board.BoardIterator_Destroy(Iterator);

    Rpt.Insert(0, 'Polygon Information for ' + ExtractFileName(Board.FileName) + ' document.');

    FileName := ChangeFileExt(Board.FileName,'.pol');
    Rpt.SaveToFile(Filename);
    Rpt.Free;

    // Display the Polygons report
    Document  := Client.OpenDocument('Text', FileName);
    If Document <> Nil Then
    begin
        Client.ShowDocument(Document);
        if (Document.GetIsShown <> 0 ) then
            Document.DoFileLoad;
    end;

End;
