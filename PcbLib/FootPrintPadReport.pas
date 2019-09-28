{ FootPrintPadReport.pas

 from GeometryHeight..
 from General\TextFileConvert.pas
 from Footprint-SS-Fix.pas 16/09/2017

 13/09/2019  BLM  v0.1  Cut&paste out of Footprint-SS-Fix.pas
 13/09/2019  BLM  v0.11 Holetype was converted as boolean..
                  v0.12 Set units with const.
28/09/2019   BLM  v0.13 Add footprint/board origin
29/09/2019   BLM  v0.14 Add tests for origin & bounding rectangle CoG.

note:  Creating a PcbLib from problem PcbDoc footprints can show incorrect Origin.
Reloading PcbLib appears to cuase dll crash & then Origin is fixed but BR & pads are offset.


}
//...................................................................................
const
    Units      = eMetric; //eImperial;
    XOExpected = 50000;   // expected X origin mil
    YOExpected = 50000;   // mil

Var
    CurrentLib : IPCB_Library;
    FPIterator : IPCB_LibraryIterator;
    Iterator   : IPCB_GroupIterator;
    Handle     : IPCB_Primitive;
    Rpt        : TStringList;
    FilePath   : WideString;

procedure SaveReportLog(FileExt : WideString, const display : boolean);
var
    FileName     : TPCBString;
    Document     : IServerDocument;
begin
//    FileName := ChangeFileExt(Board.FileName, FileExt);
    FileName := ChangeFileExt(CurrentLib.Board.FileName, FileExt);
    Rpt.SaveToFile(Filename);
    Document  := Client.OpenDocument('Text', FileName);
    If display and (Document <> Nil) Then
    begin
        Client.ShowDocument(Document);
        if (Document.GetIsShown <> 0 ) then
            Document.DoFileLoad;
    end;
end;

procedure ReportPadHole;
var
    Footprint    : IPCB_LibComponent;
    Pad          : IPCB_Pad;
    PadCache     : TPadCache;
    Layer        : TLayer;
    NoOfPrims    : Integer;
    BR           : TCoordRect;
    FPCoG        : TCoordPoint;
    BOrigin      : TCoordPoint;
    BWOrigin     : TCoordPoint;
    TestPoint    : TPoint;
    BadFPList    : TStringList;
    I            : integer;
//    Units        : TUnit;

begin
    CurrentLib := PCBServer.GetCurrentPCBLibrary;
    If CurrentLib = Nil Then
    Begin
        ShowMessage('This is not a PcbLib document');
        Exit;
    End;

    BeginHourGlass(crHourGlass);
//    Units := eImperial;

    // For each page of library is a footprint
    FPIterator := CurrentLib.LibraryIterator_Create;
    FPIterator.SetState_FilterAll;
    FPIterator.AddFilter_LayerSet(AllLayers);

    BadFPList := TStringList.Create;
    Rpt       := TStringList.Create;
    Rpt.Add(ExtractFileName(CurrentLib.Board.FileName));
    Rpt.Add('');
    Rpt.Add('');

    Footprint := FPIterator.FirstPCBObject;
    while Footprint <> Nil Do
    begin
        Rpt.Add('Footprint : ' + Footprint.Name);
        Rpt.Add('');

        BOrigin  := Point(CurrentLib.Board.XOrigin,      CurrentLib.Board.YOrigin     );  // abs Tcoord
        BWOrigin := Point(CurrentLib.Board.WorldXOrigin, CurrentLib.Board.WorldYOrigin);

        BR    := Footprint.BoundingRectangle;                  // always zero!!  abs origin TCoord
        BR    := Footprint.BoundingRectangleChildren;          // abs origin TCoord
        FPCoG := Point(BR.x1 + (RectWidth(BR) / 2), BR.y1 + (RectHeight(BR) / 2));

        BR := RectToCoordRect(                         // relative to origin TCoord
              Rect((BR.x1), (BR.y2), (BR.x2), (BR.y1)) );
              // Rect((BR.x1 - BORigin.X), (BR.y2 - BOrigin.Y), (BR.x2 - BOrigin.X), (BR.y1 - BOrigin.Y)) );

        Rpt.Add('origin board x ' + CoordUnitToString(BOrigin.X,  eMil) + '  y ' + CoordUnitToString(BOrigin.Y,  eMil) );
        Rpt.Add('origin world x ' + CoordUnitToString(BWOrigin.X, eMil) + '  y ' + CoordUnitToString(BWOrigin.Y, eMil) );
        Rpt.Add('FP b.rect ref origin x1 ' + CoordUnitToString(BR.x1, eMil) + '  y1 ' + CoordUnitToString(BR.y1, eMil) +
                '  x2 ' + CoordUnitToString(BR.x2, eMil) + '  y2 ' + CoordUnitToString(BR.y2, eMil) );

        if (CoordToMils(BOrigin.X) <> XOExpected) or (CoordToMils(BOrigin.Y) <> YOExpected) then
            BadFPList.Add('BAD FP origin     ' + Footprint.Name);
        if (BR.x1 > 0) or (BR.x2 < 0) or (BR.y1 > 0) or (BR.y2 < 0) then
            BadFPList.Add('BAD origin Outside b.rect ' + Footprint.Name);

        if (abs(FPCoG.X) > MilsToRealCoord(100)) or (abs(FPCoG.Y) > MilsToRealCoord(100))then
            BadFPList.Add('possible bounding rect. offset ' + Footprint.Name);

 

// bits of footprint
        Iterator := Footprint.GroupIterator_Create;
        Iterator.AddFilter_ObjectSet(MkSet(ePadObject, eViaObject));

        NoOfPrims := 0;

        Handle := Iterator.FirstPCBObject;
        while (Handle <> Nil) Do
        begin
            Inc(NoOfPrims);
            if Handle.GetState_ObjectId = ePadObject then
            begin
                Pad := Handle;
                Layer := Pad.Layer;
                // Pad.HoleType := eRoundHole;
                // ePadMode_LocalStack;       // top-mid-bottom stack

                Rpt.Add('Layer        : ' + CurrentLib.Board.LayerName(Layer));
                Rpt.Add('Pad.x        : ' + PadLeft(CoordUnitToString(Pad.x,                 Units), 10) + '  Pad.y       : ' + PadLeft(CoordUnitToString(Pad.y,                 Units),10) );
                Rpt.Add('Pad offsetX  : ' + PadLeft(CoordUnitToString(Pad.XPadOffset(Layer), Units), 10) + '  Pad offsetY : ' + PadLeft(CoordUnitToString(Pad.YPadOffset(Layer), Units),10) );
                Rpt.Add('Holesize     : ' + PadLeft(CoordUnitToString(Pad.Holesize,          Units), 10) );
                Rpt.Add('Holetype     : ' + IntToStr(Pad.Holetype));     // TExtendedHoleType
                Rpt.Add('DrillType    : ' + IntToStr(Pad.DrillType));    // TExtendedDrillType
                Rpt.Add('Plated       : ' + BoolToStr(Pad.Plated));

                Rpt.Add('Pad Name     : ' + Pad.Name);                  // should be designator / pin number
                Rpt.Add('Pad ID       : ' + Pad.Identifier);
                Rpt.Add('Pad desc     : ' + Pad.Descriptor);
                Rpt.Add('Pad Detail   : ' + Pad.Detail);
                Rpt.Add('Pad ObjID    : ' + Pad.ObjectIDString);
                Rpt.Add('Pad Pin Desc : ' + Pad.PinDescriptor);

                Rpt.Add('Pad Mode     : ' + IntToStr(Pad.Mode));
                Rpt.Add('Pad Stack Size Top(X,Y): (' + CoordUnitToString(Pad.TopXSize,Units) + ',' + CoordUnitToString(Pad.TopYSize,Units) + ')');
                Rpt.Add('Pad Stack Size Mid(X,Y): (' + CoordUnitToString(Pad.MidXSize,Units) + ',' + CoordUnitToString(Pad.MidYSize,Units) + ')');
                Rpt.Add('Pad Stack Size Bot(X,Y): (' + CoordUnitToString(Pad.BotXSize,Units) + ',' + CoordUnitToString(Pad.BotYSize,Units) + ')');

            end;

            if (Handle.GetState_ObjectId = ePadObject) then
            begin
                Pad := Handle;
                PadCache := Pad.Cache;

// add these at some point..

                CoordToMils(Padcache.ReliefAirGap);
                CoordToMils(Padcache.PowerPlaneReliefExpansion);
                CoordToMils(Padcache.PowerPlaneClearance);
                CoordToMils(Padcache.ReliefConductorWidth);

                PadCache.PasteMaskExpansionValid;   // eCacheManual;
                CoordToMils(PadCache.PasteMaskExpansion);
                PadCache.SolderMaskExpansionValid;   // eCacheManual;
                CoordToMils(PadCache.SolderMaskExpansion);

                Pad.SolderMaskExpansionFromHoleEdgeWithRule;
                Pad.SolderMaskExpansionFromHoleEdge;
                Pad.GetState_IsTenting_Top;
                Pad.GetState_IsTenting_Bottom;

                Rpt.Add('PEX  : ' + CoordUnitToString(PadCache.PasteMaskExpansion,  Units) );
                Rpt.Add('SMEX : ' + CoordUnitToString(PadCache.SolderMaskExpansion, Units) );
            end;

            Handle := Iterator.NextPCBObject;
        end;

        Rpt.Add('Num Pads+Vias : ' + IntToStr(NoOfPrims));
        Rpt.Add('');
        Rpt.Add('');

        Footprint.GroupIterator_Destroy(Iterator);
        Footprint := FPIterator.NextPCBObject;
    end;

    CurrentLib.LibraryIterator_Destroy(FPIterator);

    for I := 0 to (BadFPList.Count - 1) do
    begin
        Rpt.Insert((I + 3), BadFPList.Strings(I));
    end;
    if (BadFPList.Count > 0) then Rpt.Insert(3, 'bad footprints detected');  

    BadFPList.Free;
    EndHourGlass;

    SaveReportLog('PadHoleReport.txt', true);
    Rpt.Free;

end;

{
TUnit = (eMetric, eImperial);

TExtendedDrillType =(
    eDrilledHole,
    ePunchedHole,
    eLaserDrilledHole,
    ePlasmaDrilledHole
);
TExtendedHoleType= (
    eRoundHole,
    eSquareHole,
    eSlotHole
);

}

