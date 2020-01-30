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

}
Const
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
  Rpt.Add('  HoleCount ' + IntToStr(Region.HoleCount) );
  for i := 0 to Region.HoleCount - 1 do
     Area := Area - Region.Holes[i].Area;
  Result := Area;
end;

function PolyHatchStyleToStr(HS : TPolyHatchStyle) : WideString;
begin
    case HS of
    ePolyHatch90, ePolyHatch45, ePolyVHatch, ePolyHHatch :
        Result := 'Hatched';
    ePolyNoHatch  : Result := 'No Hatch';
    ePolySolid : Result := 'Solid';
    else
        Result := '';
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
    PrimCount  : integer;
    CopperArea : Double;
    TotalArea  : Double;

    FileName   : TPCBString;
    Document   : IServerDocument;
    PolyNo     : Integer;
    I, J       : Integer;

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
    Iterator := Board.BoardIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(ePolyObject));
    Iterator.AddFilter_LayerSet(AllLayers);       // alt. SignalLayers    ??
    Iterator.AddFilter_Method(eProcessAll);

    PolyNo     := 0;
    Rpt := TStringList.Create;
    Rpt.Add(' Board Area size : '  + SqrCoordToUnitString(Board.BoardOutline.AreaSize, BUnits) ) ; // FloatToStr(Board.BoardOutline.AreaSize / SQR(k1Inch) + ' sq in'));
    Rpt.Add('');

    Polygon := Iterator.FirstPCBObject;
    While (Polygon <> Nil) Do
    Begin
        Inc(PolyNo);
        Rpt.Add('Polygon No : '     + IntToStr(PolyNo));
        Rpt.Add(' Name : '          + Polygon.Name);
        Rpt.Add(' Detail : '        + Polygon.Detail);
        Rpt.Add(' Layer : '         + Board.LayerName(Polygon.Layer)  + ' -  ' + Layer2String(Polygon.Layer) );
        Rpt.Add(' Hatch Style : '   + PolyHatchStyleToStr(Polygon.PolyHatchStyle) );


        //Check if Net exists before getting the Name property.
        If Polygon.Net <> Nil Then
            Rpt.Add(' Net : '     + Polygon.Net.Name);

        If Polygon.PolygonType = eSignalLayerPolygon Then
            Rpt.Add(' Type : '     + 'Polygon on Signal Layer')
        Else
            Rpt.Add(' Type : '     + 'Split plane polygon');

        Rpt.Add(' BorderWidth : '  + CoordUnitToString(Polygon.BorderWidth ,BUnits) );     //  FloatToStr(Polygon.BorderWidth));

        // Segments of a polygon
        For I := 0 To (Polygon.PointCount - 1) Do
        Begin
            If Polygon.Segments[I].Kind = ePolySegmentLine Then
            Begin
                Rpt.Add(' Segment Line X :  ' + PadLeft(IntToStr(Polygon.Segments[I].vx), 15) + ' Y : ' + PadLeft(IntToStr(Polygon.Segments[I].vy), 15) );
            End
            Else
            Begin
                Rpt.Add(' Segment Arc 1  : ' + FloatToStr(Polygon.Segments[I].Angle1) );
                Rpt.Add(' Segment Arc 2  : ' + FloatToStr(Polygon.Segments[I].Angle2) );
                Rpt.Add(' Segment Radius : ' + FloatToStr(Polygon.Segments[I].Radius) );
            End;
        End;

        PrimCount := Polygon.GetPrimitiveCount(AllObjects);
        Rpt.Add(' Prim (All types) Count : '  + IntToStr(PrimCount));

        CopperArea := 0;
        TotalArea := 0;
        I := 0; J := 0;

        if Polygon.PolyHatchStyle = ePolySolid then
        begin
            GIter := Polygon.GroupIterator_Create;
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
            Polygon.GroupIterator_Destroy(GIter);
        end;
        Rpt.Add('');
        Rpt.Add(' Poly Area : '    + SqrCoordToUnitString(Polygon.AreaSize, BUnits) );     // FloatToStr(Polygon.AreaSize / SQR(k1Inch / mmInch) ));
        Rpt.Add(' Cu   Area : '    + SqrCoordToUnitString(TotalArea, BUnits) );            // FloatToStr(TotalArea / SQR(k1Inch / mmInch) ));
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
