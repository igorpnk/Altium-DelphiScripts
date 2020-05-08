{ FootPrintReport.pas

was FootPrintPadReport.pas
 from GeometryHeight..
 from General\TextFileConvert.pas
 from Footprint-SS-Fix.pas 16/09/2017

ReportPadHole()
    Pad copper shapes stacks, hole & masks
  and
ReportLayersUsed()
    FP primitive obj totals & mech layer summary table.
    FP copper layers are reported by the highest Pad padstack Mode.

 13/09/2019  BLM  v0.1  Cut&paste out of Footprint-SS-Fix.pas
 13/09/2019  BLM  v0.11 Holetype was converted as boolean..
                  v0.12 Set units with const.
28/09/2019   BLM  v0.13 Add footprint/board origin
29/09/2019   BLM  v0.14 Add tests for origin & bounding rectangle CoG.
30/09/2019   BLM  v0.15 Seems lots of info BR & desc was not valid until after some setup
04/05/2020   BLM  v0.16 Add layers used report.
07/05/2020        v0.17 use ParameterList to (big!) speed up layer indexing.
08/05/2020        v0.18 list mech pairs by index , tested in AD19

note: First 4 or 5 statements run in loop seem to prevent false stale info

reports layer by exception if layer > cFullMechLayerReport const.

PadStack Mode:
X == Full External stack
L == Local stack
S == Simple stack

}
//...................................................................................
const
    Units          = eMetric; //eImperial;
    XOExpected     = 50000;   // expected X origin mil
    YOExpected     = 50000;   // mil

    cFullMechLayerReport = 32;

    AD19VersionMajor  = 19;
    AD17MaxMechLayers = 32;       // scripting API has broken consts from TV6_Layer
    AD19MaxMechLayers = 1024;
    NoMechLayerKind   = 0;        // enum const does not exist for AD17/18

Var
    CurrentLib    : IPCB_Library;
    FPIterator    : IPCB_LibraryIterator;
    Iterator      : IPCB_GroupIterator;
    Prim          : IPCB_Primitive;
    Footprint     : IPCB_LibComponent;
    Rpt           : TStringList;
    FilePath      : WideString;
    MaxMechLayer  : integer;
    VerMajor      : WideString;


function Version(const dummy : boolean) : TStringList;
begin
    Result               := TStringList.Create;
    Result.Delimiter     := '.';
    Result.Duplicates    := dupAccept;
    Result.DelimitedText := Client.GetProductVersion;
end;

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

function LayerToIndex(var PL : TParameterList, const L : TLayer) : integer;
var
   I    : integer;
   PVal : integer;
begin
    Result := 0;
// cache results to speed layer to index conversion
    if not PL.GetState_ParameterAsInteger(L, PVal) then
    begin
        I := 1;
        repeat
            if LayerUtils.MechanicalLayer(I) = L then Result := I;
            inc(I);
            if I >  MaxMechLayer then break;
        until Result <> 0;
        PVal := Result;
        PL.SetState_AddParameterAsInteger(L, PVal);
    end
    else
        Result := PVal;
end;

procedure ReportLayersUsed;
var
    LayerUsed    : Array [0..1025]; // of boolean;
    LayerPCount  : Array [0..1025]; // of integer;
    LayerIsUsed  : boolean;
    plLayerIndex : TParameterList;
    NoOfPrims    : Integer;
    PadStack  : WideString;
    PadCount  : Integer;
    RegCount  : Integer;
    TrkCount  : Integer;
    TxtCount  : Integer;
    FilCount  : integer;
    LayerRow  : WideString;
    Layer     : TLayer;
    I, J      : integer;
    sLayer    : WideString;
    FPName    : WideString;
    HoleSet   : TSet;
    LayerStack    : IPCB_LayerStack_V7;
    MechLayer     : IPCB_MechanicalLayer;
    MechPairs     : IPCB_MechanicalLayerPairs;
    MechLayerKind : TMechanicalLayerKind;
    ML1, ML2      : integer;

begin
    CurrentLib := PCBServer.GetCurrentPCBLibrary;
    If CurrentLib = Nil Then
    Begin
        ShowMessage('This is not a PcbLib document');
        Exit;
    End;

    BeginHourGlass(crHourGlass);
//    Units := eImperial;

    VerMajor := Version(true).Strings(0);
    MaxMechLayer := AD17MaxMechLayers;
//    LegacyMLS     := true;
    MechLayerKind := NoMechLayerKind;
    if (VerMajor >= AD19VersionMajor) then
    begin
//        LegacyMLS     := false;
        MaxMechLayer := AD19MaxMechLayers;
    end;


    // For each page of library is a footprint
    FPIterator := CurrentLib.LibraryIterator_Create;
    FPIterator.SetState_FilterAll;
    FPIterator.AddFilter_LayerSet(AllLayers);

    Rpt := TStringList.Create;
    Rpt.Add(ExtractFileName(CurrentLib.Board.FileName));
    Rpt.Add('');

    plLayerIndex := TParameterList.Create;

    for I := 0 to 1001 do
        LayerUsed[I]   := 0;

// assume same layerstack & mech pairs for whole library
// proper method has broken function return type so iterate.
    LayerStack := CurrentLib.Board.LayerStack_V7;
    MechPairs  := CurrentLib.Board.MechanicalPairs;
    for I := 1 to (MaxMechLayer - 1) do
    begin
        ML1 := LayerUtils.MechanicalLayer(I);
        MechLayer := LayerStack.LayerObject_V7[ML1];
        if MechLayer.MechanicalLayerEnabled then
        begin
            for J := (I + 1) to MaxMechLayer do
            begin
                ML2 := LayerUtils.MechanicalLayer(J);
                MechLayer := LayerStack.LayerObject_V7[ML2];
                if MechLayer.MechanicalLayerEnabled then
                begin
                     if MechPairs.PairDefined(ML1, ML2) then
                     begin
                        LayerUsed[I]:= J;
                        LayerUsed[J]:= I;
                     end;
                end;
            end;
        end;
    end;

    Rpt.Add('');
    Rpt.Add('FootPrint                           PadStack| Primitive Counts  | Mechanical Layers                                                                                                             | 33 + ');
    Rpt.Add('Name                                    |PS |Pad|Reg|Trk|Txt|Fil| 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10| 11| 12| 13| 14| 15| 16| 17| 18| 19| 20| 21| 22| 23| 24| 25| 26| 27| 28| 29| 30| 31| 32|...');
    // Rpt.Add('');

    LayerRow := '';
    for I := 1 to (MaxMechLayer) do
    begin
        J := LayerUsed[I];
        sLayer := IntToStr(J);
        if J = 0 then  sLayer := ' ';  // should never happen!

        if I <= cFullMechLayerReport then
        begin
            LayerRow := LayerRow + PadLeft(sLayer, 3) + '|';
        end else
        begin
            if (J > 0) and (J > I) then     // avoid double pair reporting
                LayerRow := LayerRow + IntToStr(I) + '=' + sLayer + '|';
        end;
        LayerUsed[I] := 0;
    end;
    Rpt.Add('                        mechanical pairs -->                    |' + LayerRow);

    HoleSet := MkSet(ePadObject, eViaObject);

    Footprint := FPIterator.FirstPCBObject;
    while Footprint <> Nil Do
    begin
//  one of the next 4 or 5 lines seems to fix the erronous bounding rect of the alphabetic first item in Lib list
//  suspect it changes the Pad.Desc text as well
        CurrentLib.SetState_CurrentComponent (Footprint);
        CurrentLib.Board.ViewManager_FullUpdate;                // makes a slideshow
//        Client.SendMessage('PCB:Zoom', 'Action=Redraw' , 255, Client.CurrentView);
        CurrentLib.Board.GraphicalView_ZoomRedraw;
//        CurrentLib.Board.Viewport.ViewportRect (FootPrint.BoundingRectangleForPainting);
        CurrentLib.RefreshView;

//        LayerIsUsed := FootPrint.LayerUsed(TV6_Layer);
//        FootPrint.GetState_LayersUsedArray;

// electrical layers prim cnts
        TrkCount := Footprint.GetPrimitiveCount(MkSet(eTrackObject, eArcObject));
        TxtCount := Footprint.GetPrimitiveCount(MkSet(eTextObject));
        RegCount := Footprint.GetPrimitiveCount(MkSet(eRegionObject));
        FilCount := Footprint.GetPrimitiveCount(MkSet(eFillObject));
        PadCount := Footprint.GetPrimitiveCount(MkSet(ePadObject));

        PadStack := '';
        for I := 1 to (PadCount) do        // one's based
        begin
            Prim := FootPrint.GetPrimitiveAt(I, ePadObject);
            if Prim <> nil then
            begin
                Case Prim.Mode of
                ePadMode_Simple        : PadStack := PadStack + 'S';
                ePadMode_LocalStack    : PadStack := PadStack + 'L';
                ePadMode_ExternalStack : PadStack := PadStack + 'X';
                end;
            end;
        end;

        if ansipos('X', PadStack) > 0 then PadStack := 'X';   // external full stack
        if ansipos('L', PadStack) > 0 then PadStack := 'L';   // local stack
        if ansipos('S', PadStack) > 0 then PadStack := 'S';   // simple

        FPName := Footprint.Name;
//      Copy(FPName, 29);

// mechanical layers

        Iterator := Footprint.GroupIterator_Create;
        Iterator.AddFilter_ObjectSet(AllObjects);  //  MkSet(ePadObject, eViaObject));

        NoOfPrims := 0;
        for I := 0 to (MaxMechLayer + 1) do
            LayerPCount[I] := 0;

        Prim := Iterator.FirstPCBObject;
        while (Prim <> Nil) Do
        begin
            Inc(NoOfPrims);

//            if LayerUtils.IsElectricalLayer(Prim.Layer) then Copper= true;

            I := -1;
            if  LayerUtils.IsMechanicalLayer(Prim.Layer) then
                I := LayerToIndex(plLayerIndex, Prim.Layer);

            if (I <> -1) and (not InSet(Prim.ObjectId, HoleSet) ) then
            begin
                if I = 0 then
                begin      // check for oddball objects..
                    LayerUsed[MaxMechLayer + 1]   := 1;
                    LayerPCount[MaxMechLayer + 1] := LayerPCount[MaxMechLayer + 1] + 1;
                end else
                begin
                    LayerUsed[I]   := 1;
                    LayerPCount[I] := LayerPCount[I] + 1;
                end;
            end;
            Prim := Iterator.NextPCBObject;
        end;

        LayerRow := '';
        for I := 1 to (MaxMechLayer + 1) do
        begin
            if I <= cFullMechLayerReport then
            begin
               LayerRow := LayerRow + PadLeft(IntToStr(LayerPCount[I]), 3) + '|';
            end else
            begin
                if (LayerPCount[I] > 0) and (LayerUsed[I] > 0) then
                    LayerRow := LayerRow + IntToStr(I) + '=' + IntToStr(LayerPCount[I]) + '|';
            end;
        end;

        Rpt.Add(PadRight(FPName,40) + '| ' + PadStack + ' |' + PadLeft(IntToStr(PadCount),3) + '|' + PadLeft(IntToStr(RegCount),3) + '|'
                + PadLeft(IntToStr(TrkCount),3) + '|' +  PadLeft(IntToStr(TxtCount),3) + '|' + PadLeft(IntToStr(FilCount),3) + '|'
                +LayerRow);

        Footprint.GroupIterator_Destroy(Iterator);
        Footprint := FPIterator.NextPCBObject;
    end;

    CurrentLib.LibraryIterator_Destroy(FPIterator);

    CurrentLib.Navigate_FirstComponent;
    CurrentLib.Board.GraphicalView_ZoomRedraw;
    CurrentLib.RefreshView;

    plLayerIndex.Destroy;

    EndHourGlass;
    SaveReportLog('LayersUsedReport.txt', true);
    Rpt.Free;
end;

procedure ReportPadHole;
var
    
    Pad          : IPCB_Pad;
    PadCache     : TPadCache;
    PlanesArray  : TPlanesConnectArray;
    CPL          : WideString;
    Layer        : TLayer;
    NoOfPrims    : Integer;
    BR           : TCoordRect;
    FPCoG        : TCoordPoint;
    BOrigin      : TCoordPoint;
    BWOrigin     : TCoordPoint;
    TestPoint    : TPoint;
    BadFPList    : TStringList;
    I, L         : integer;
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

        BR := Footprint.BoundingRectangle;                  // always zero!!  abs origin TCoord
        BR := Footprint.BoundingRectangleChildren;          // abs origin TCoord
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

        Prim := Iterator.FirstPCBObject;
        while (Prim <> Nil) Do
        begin
            Inc(NoOfPrims);
            if Prim.GetState_ObjectId = ePadObject then
            begin
                Pad := Handle;
                Layer := Pad.Layer;
                // Pad.HoleType := eRoundHole;
                // ePadMode_LocalStack;       // top-mid-bottom stack
                Rpt.Add('');
                Rpt.Add('Pad Name      : ' + Pad.Name);                  // should be designator / pin number
                Rpt.Add('Enabled       : ' + BoolToStr(Pad.Enabled, true) + '  (E=' + IntToStr(Pad.Enabled) + ') (ED=' + IntToStr(Pad.EnableDraw) + ')' );
                Rpt.Add('Layer         : ' + CurrentLib.Board.LayerName(Layer));
                Rpt.Add('Pad.x         : ' + PadLeft(CoordUnitToString((Pad.x - BOrigin.X),   Units), 10) + '  Pad.y         : ' + PadLeft(CoordUnitToString((Pad.y - BOrigin.Y),   Units),10) );
                Rpt.Add('All L offsetX : ' + PadLeft(CoordUnitToString(Pad.XPadOffsetAll,     Units), 10) + '  All L offsetY : ' + PadLeft(CoordUnitToString(Pad.YPadOffsetAll,     Units),10) );
// not actually implemented.
                Rpt.Add('OffsetX       : ' + PadLeft(CoordUnitToString(Pad.XPadOffset(Layer), Units), 10) + '  offsetY       : ' + PadLeft(CoordUnitToString(Pad.YPadOffset(Layer), Units),10) );
                Rpt.Add('TearDrop      : ' + BoolToStr(    Pad.TearDrop, true) + '  (' + IntToStr(Pad.TearDrop) + ')' );
                Rpt.Add('Rotation      : ' + PadLeft(FloatToStr(       Pad.Rotation                            ), 10) + ' deg');
                Rpt.Add('Holesize      : ' + PadLeft(CoordUnitToString(Pad.Holesize,                      Units), 10) );
                Rpt.Add('Hole Tol +ve  : ' + PadLeft(CoordUnitToString(Pad.HolePositiveTolerance,         Units), 10) );
                Rpt.Add('Hole Tol -ve  : ' + PadLeft(CoordUnitToString(Pad.HoleNegativeTolerance,         Units), 10) );
                Rpt.Add('HoleWidth     : ' + PadLeft(CoordUnitToString(Pad.HoleWidth,                     Units), 10) );
                Rpt.Add('HoleRotation  : ' + PadLeft(FloatToStr(       Pad.HoleRotation                        ), 10) + ' deg' );
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

            if (Prim.GetState_ObjectId = ePadObject) then
            begin
                Pad := Prim;
                PadCache := Pad.Cache;

                Rpt.Add('Pad Cache Robot Flag               : ' + BoolToStr(Pad.PadCacheRobotFlag, true)  + '  (' + IntToStr(Pad.PadCacheRobotFlag) + ')');
//      CPLV - Plane Layers (List) valid ?
                Rpt.Add('Planes Valid                  CPLV : ' + GetCacheState(PadCache.PlanesValid) );
//      CCSV - Plane Connection Style valid ?
                Rpt.Add('Plane Style Valid             CCSV : ' + GetCacheState(PadCache.PlaneConnectionStyleValid) );
                Rpt.Add('Plane Connection Style        CCS  : ' + GetPlaneConnectionStyle(PadCache.PlaneConnectionStyle) );
                Rpt.Add('Plane Connect Style for Layer      : ' + GetPlaneConnectionStyle(Pad.PlaneConnectionStyleForLayer(Layer)) );
                                                         

        // Transfer Pad.Cache's Planes field (Word type) to the Planes variable (TPlanesConnectArray type).
                PlanesArray := PadCache.Planes;
                CPL := '';
                for L := kMinInternalPlane To kMaxInternalPlane Do
                begin
            // Planes is a TPlanesConnectArray and each internal plane has a boolean value.
            // at the moment PlanesArray[L] is always true which is not TRUE!
                if (PlanesArray[L] = True) Then
                    CPL := CPL + '1'
                else
                    CPL := CPL + '0';
                end;
//        CPL_Hex := IntegerToHexString(CPL);

                if (PadCache.PlanesValid <> eCacheInvalid) Then
                begin
                    Rpt.Add('   Power Planes Connection Code (binary): ' + CPL );
                end else
                begin
                    Rpt.Add('   { Power Planes Connection Code (binary): ' + CPL + ' }');
                end;


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

            Prim := Iterator.NextPCBObject;
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

