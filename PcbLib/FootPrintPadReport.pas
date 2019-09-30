{ FootPrintPadReport.pas

 from GeometryHeight..
 from General\TextFileConvert.pas
 from Footprint-SS-Fix.pas 16/09/2017

 13/09/2019  BLM  v0.1  Cut&paste out of Footprint-SS-Fix.pas
 13/09/2019  BLM  v0.11 Holetype was converted as boolean..
                  v0.12 Set units with const.
28/09/2019   BLM  v0.13 Add footprint/board origin
29/09/2019   BLM  v0.14 Add tests for origin & bounding rectangle CoG.
30/09/2019   BLM  v0.15 Seems lots of info BR & desc was not valid until after some setup

note: First 4 or 5 statements run in loop seem to prevent false stale info

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
{..................................................................................................}
function GetCacheState (Value : TCacheState) : String;
begin
    Result := '?';
    If Value = eCacheInvalid Then Result := 'Invalid';
    If Value = eCacheValid   Then Result := 'Valid';
    If Value = eCacheManual  Then Result := '''Manual''';
end;
{..................................................................................................}
function GetPlaneConnectionStyle (Value : TPlaneConnectionStyle) : String;
begin
    Result := 'Unknown';
    If Value = ePlaneNoConnect     Then Result := 'No Connect';
    If Value = ePlaneReliefConnect Then Result := 'Relief';
    If Value = ePlaneDirectConnect Then Result := 'Direct';
end;
{..................................................................................................}

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
    Rpt.Add('');

    Footprint := FPIterator.FirstPCBObject;
    while Footprint <> Nil Do
    begin
// one of the next 4 or 5 lines seems to fix the erronous bounding rect of the alphabetic first item in Lib list
// suspect it changes the Pad.Desc text as well

        CurrentLib.SetBoardToComponentByName(Footprint.Name) ;   // fn returns boolean
        CurrentLib.SetState_CurrentComponent (Footprint);
        CurrentLib.Board.ViewManager_FullUpdate;
        CurrentLib.RefreshView;

        CurrentLib.Board.RebuildPadCaches;

        Rpt.Add('Footprint : ' + Footprint.Name);
        Rpt.Add('');

        BOrigin  := Point(CurrentLib.Board.XOrigin,      CurrentLib.Board.YOrigin     );  // abs Tcoord
        BWOrigin := Point(CurrentLib.Board.WorldXOrigin, CurrentLib.Board.WorldYOrigin);

        BR    := Footprint.BoundingRectangle;                  // always zero!!  abs origin TCoord
        BR    := Footprint.BoundingRectangleChildren;          // abs origin TCoord
        BR := RectToCoordRect(                         // relative to origin TCoord
              // Rect((BR.x1), (BR.y2), (BR.x2), (BR.y1)) );
              Rect((BR.x1 - BORigin.X), (BR.y2 - BOrigin.Y), (BR.x2 - BOrigin.X), (BR.y1 - BOrigin.Y)) );
        FPCoG := Point(BR.x1 + (RectWidth(BR) / 2), BR.y1 + (RectHeight(BR) / 2));

        Rpt.Add('origin board x ' + CoordUnitToString(BOrigin.X,  eMil) + '  y ' + CoordUnitToString(BOrigin.Y,  eMil) );
        Rpt.Add('origin world x ' + CoordUnitToString(BWOrigin.X, eMil) + '  y ' + CoordUnitToString(BWOrigin.Y, eMil) );
        Rpt.Add('FP b.rect ref origin x1 ' + CoordUnitToString(BR.x1, eMil) + '  y1 ' + CoordUnitToString(BR.y1, eMil) +
                '  x2 ' + CoordUnitToString(BR.x2, eMil) + '  y2 ' + CoordUnitToString(BR.y2, eMil) );

        if (CoordToMils(BOrigin.X) <> XOExpected) or (CoordToMils(BOrigin.Y) <> YOExpected) then
            BadFPList.Add('BAD FP origin     ' + Footprint.Name);
        if (BR.x1 > 0) or (BR.x2 < 0) or (BR.y1 > 0) or (BR.y2 < 0) then
            BadFPList.Add('BAD origin Outside b.rect ' + Footprint.Name);

        if (abs(FPCoG.X) > MilsToRealCoord(200)) or (abs(FPCoG.Y) > MilsToRealCoord(200))then
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
                Rpt.Add('');
                Rpt.Add('Pad Name      : ' + Pad.Name);                  // should be designator / pin number
                Rpt.Add('Layer         : ' + CurrentLib.Board.LayerName(Layer));
                Rpt.Add('Pad.x         : ' + PadLeft(CoordUnitToString((Pad.x - BOrigin.X),   Units), 10) + '  Pad.y         : ' + PadLeft(CoordUnitToString((Pad.y - BOrigin.Y),   Units),10) );
                Rpt.Add('All L offsetX : ' + PadLeft(CoordUnitToString(Pad.XPadOffsetAll,     Units), 10) + '  All L offsetY : ' + PadLeft(CoordUnitToString(Pad.YPadOffsetAll,     Units),10) );
// not actually implemented.
                Rpt.Add('OffsetX       : ' + PadLeft(CoordUnitToString(Pad.XPadOffset(Layer), Units), 10) + '  offsetY       : ' + PadLeft(CoordUnitToString(Pad.YPadOffset(Layer), Units),10) );
                Rpt.Add('TearDrop      : ' + BoolToStr(    Pad.TearDrop, true) + '  (' + IntToStr(Pad.TearDrop) + ')' );
                Rpt.Add('Rotation      : ' + PadLeft(IntToStr(         Pad.Rotation                            ), 10) );
                Rpt.Add('Holesize      : ' + PadLeft(CoordUnitToString(Pad.Holesize,                      Units), 10) );
                Rpt.Add('Hole Tol +ve  : ' + PadLeft(CoordUnitToString(Pad.HolePositiveTolerance,         Units), 10) );
                Rpt.Add('Hole Tol -ve  : ' + PadLeft(CoordUnitToString(Pad.HoleNegativeTolerance,         Units), 10) );
                Rpt.Add('HoleWidth     : ' + PadLeft(CoordUnitToString(Pad.HoleWidth,                     Units), 10) );
                Rpt.Add('Holetype      : ' + IntToStr(                 Pad.Holetype));     // TExtendedHoleType
                Rpt.Add('DrillType     : ' + IntToStr(                 Pad.DrillType));    // TExtendedDrillType
                Rpt.Add('Plated        : ' + BoolToStr(                Pad.Plated, true) +    '  (' + IntToStr(Pad.Plated) + ')');

                Rpt.Add('Pad ID        : ' + Pad.Identifier);
                Rpt.Add('Pad desc      : ' + Pad.Descriptor);
                Rpt.Add('Pad Detail    : ' + Pad.Detail);
                Rpt.Add('Pad ObjID     : ' + Pad.ObjectIDString);
                Rpt.Add('Pad Pin Desc  : ' + Pad.PinDescriptor);

                Rpt.Add('Pad Mode      : ' + IntToStr(Pad.Mode));
                Rpt.Add('Pad Stack Size Top(X,Y): (' + CoordUnitToString(Pad.TopXSize, Units) + ',' + CoordUnitToString(Pad.TopYSize, Units) + ')');
                Rpt.Add('Pad Stack Size Mid(X,Y): (' + CoordUnitToString(Pad.MidXSize, Units) + ',' + CoordUnitToString(Pad.MidYSize, Units) + ')');
                Rpt.Add('Pad Stack Size Bot(X,Y): (' + CoordUnitToString(Pad.BotXSize, Units) + ',' + CoordUnitToString(Pad.BotYSize, Units) + ')');

            end;

            if (Handle.GetState_ObjectId = ePadObject) then
            begin
                Pad := Handle;
                PadCache := Pad.Cache;

                Rpt.Add('Pad Cache Robot Flag               : ' + BoolToStr(Pad.PadCacheRobotFlag, true)  + '  (' + IntToStr(Pad.PadCacheRobotFlag) + ')');
//      CPLV - Plane Layers (List) valid ?
                Rpt.Add('Planes Valid                  CPLV : ' + GetCacheState(PadCache.PlanesValid) );
//      CCSV - Plane Connection Style valid ?
                Rpt.Add('Plane Style Valid             CCSV : ' + GetCacheState(PadCache.PlaneConnectionStyleValid) );
                Rpt.Add('Plane Connection Style        CCS  : ' + GetPlaneConnectionStyle(PadCache.PlaneConnectionStyle) );
                Rpt.Add('Plane Connect Style for Layer      : ' + GetPlaneConnectionStyle(Pad.PlaneConnectionStyleForLayer(Layer)) );
                                                         
(*
        // Transfer Pad.Cache's Planes field (Word type) to the Planes variable (TPlanesConnectArray type).
        PlanesArray := PadCache.Planes;
        // Calculate the decimal value of the 'CPL' number.
        CPL := 0;
        For L := kMaxInternalPlane DownTo kMinInternalPlane Do
        Begin
            // Planes is a TPlanesConnectArray and each internal plane has a boolean value.
            // at the moment PlanesArray[L] is always true which is not TRUE!
            If (PlanesArray[L] = True) Then
                CPL := (2 * CPL) + 1
            Else
                CPL := 2 * CPL;
        End;

        // Calculate the hexadecimal value of the 'CPL' number.
        CPL_Hex := IntegerToHexString(CPL);
        If (PadCache.PlanesValid <> eCacheInvalid) Then
        Begin
            LS := LS + #13 +   'Power Planes Connection Code (Decimal): ' + IntToStr(CPL);
            LS := LS + #13 +   'Power Planes Connection Code (Base 16): ' + CPL_Hex;
        End
        Else
        Begin
            LS := LS + #13 + '{ Power Planes Connection Code (Decimal): ' + IntToStr(CPL) + ' }';
            LS := LS + #13 + '{ Power Planes Connection Code (Base 16): ' + CPL_Hex + ' }';
        End;
*)

//     CCWV - Relief Conductor Width valid ?
                Rpt.Add('Relief Conductor Width Valid  CCWV : ' + GetCacheState(PadCache.ReliefConductorWidthValid) );
                Rpt.Add('Relief Conductor Width        CCW  : ' + CoordUnitToString(PadCache.ReliefConductorWidth, Units) );
//     CENV - Relief Entries valid ?
                Rpt.Add('Relief Entries Valid          CENV : ' + GetCacheState(PadCache.ReliefEntriesValid) );
                Rpt.Add('Relief Entries                CEN  : ' + IntToStr(PadCache.ReliefEntries) );
//     CAGV - Relief Air Gap Valid ?
                Rpt.Add('Relief Air Gap Valid          CAGV : ' + GetCacheState(PadCache.ReliefAirGapValid) );
                Rpt.Add('Relief Air Gap                CAG  : ' + CoordUnitToString(PadCache.ReliefAirGap, Units) );
//     CPRV - Power Plane Relief Expansion Valid ?
                Rpt.Add('Power Plane Relief Exp. Valid CPRV : ' + GetCacheState(PadCache.PowerPlaneReliefExpansionValid) );
                Rpt.Add('Power Plane Relief Expansion  CPR  : ' + CoordUnitToString(PadCache.PowerPlaneReliefExpansion, Units) );
//     CPCV - Power Plane Clearance Valid ?
                Rpt.Add('Power Plane Clearance Valid   CPCV : '  + GetCacheState(PadCache.PowerPlaneClearanceValid) );
                Rpt.Add('Power Plane Clearance         CPC  : ' + CoordUnitToString(PadCache.PowerPlaneClearance, Units) );
//     CSEV - Solder Mask Expansion Valid ?
                Rpt.Add('Solder Mask Expansion Valid   CSEV : ' + GetCacheState(PadCache.SolderMaskExpansionValid) );
                Rpt.Add('Solder Mask Expansion         CSE  : ' + CoordUnitToString(PadCache.SolderMaskExpansion, Units) );

                Rpt.Add('SMEX from Hole Edge                : ' + BoolToStr(Pad.SolderMaskExpansionFromHoleEdge, true) );
                Rpt.Add('SMEX from Hole Edge with Rule      : ' + BoolToStr(Pad.SolderMaskExpansionFromHoleEdgeWithRule, true) );
                Rpt.Add('IsTenting                          : ' + BoolToStr(Pad.GetState_IsTenting, true) );
                Rpt.Add('IsTenting Top                      : ' + BoolToStr(Pad.GetState_IsTenting_Top, true) );
                Rpt.Add('IsTenting Bottom                   : ' + BoolToStr(Pad.GetState_IsTenting_Bottom, true) );

//     CPEV - Paste Mask Expansion Valid ?
                Rpt.Add('Paste Mask Expansion Valid    CPEV : ' + GetCacheState(PadCache.PasteMaskExpansionValid) );
                Rpt.Add('Paste Mask Expansion          CPE  : ' + CoordUnitToString(PadCache.PasteMaskExpansion, Units) );

//                Rpt.Add('PEX  : ' + CoordUnitToString(PadCache.PasteMaskExpansion,  Units) );
//                Rpt.Add('SMEX : ' + CoordUnitToString(PadCache.SolderMaskExpansion, Units) );
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
        Rpt.Insert((I + 2), BadFPList.Strings(I));
    end;
    if (BadFPList.Count > 0) then Rpt.Insert(2, 'bad footprints detected');

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

