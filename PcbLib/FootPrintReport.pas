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
    PcbDoc & PcbLib

Author BL Miller
13/09/2019  v0.1   Cut&paste out of Footprint-SS-Fix.pas
13/09/2019  v0.11  Holetype was converted as boolean..
            v0.12  Set units with const.
28/09/2019  v0.13  Add footprint/board origin
29/09/2019  v0.14  Add tests for origin & bounding rectangle CoG.
30/09/2019  v0.15  Seems lots of info BR & desc was not valid until after some setup
04/05/2020  v0.16  Add layers used report.
07/05/2020  v0.17  use ParameterList to (big!) speed up layer indexing.
08/05/2020  v0.18  list mech pairs by index , tested in AD19
09/05/2020  v0.19  Added mechlayer used row at top of table. (not checked in AD19)
07/08/2020  v0.20  test around PlanesArray mess.
17/08/2020  v0.21  Add bit more MechLayerKind data collection.
18/08/2020  v0.22  Add MechLayer Kind & legend at end of report.
18/08/2020  v0.23  Added mechlayer names & kinds summary for enabled layers. Added enabled & used status.
18/08/2020  v0.24  Support PcbDoc; Disable kind legend (redundant repeat info).
19/08/2020  v0.25  Fix pad stack display for non stack FPs.
05/01/2021  v0.26  Added paste shape size (rule & fixed exp.) & support for PcbDoc in PadReport.
11/02/2021  v0.27  Added ReportBodies() list footprint patterns & comp body names.
12/02/2021  v0.28  Improve? formating ReportBodies() add extra info
12/02/2021  v0.29  Overwrite CBody Id with FP name (if blank) CBody.Name & Model.Name just useless
14/02/2021  v0.30  ReportBodies() need to make each FP "current" to get the correct origin data

note: First 4 or 5 statements run in the top of main loop seem to prevent false stale info
Paste mask shape may not return the minimal dimension.

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
    MaxMechLayerKinds = 30;
    cMLEnabled        = 1;
    cMLUsedByPrims    = 2;

Var
    Doc           : IDocument;
    CurrentLib    : IPCB_Library;
    CBoard        : IPCB_Board;
    BOrigin      : TCoordPoint;
    FPIterator    : IPCB_LibraryIterator;
    Iterator      : IPCB_GroupIterator;
    Prim          : IPCB_Primitive;
    Footprint     : IPCB_LibComponent;
    PLayerSet     : IPCB_LayerSet;
    FPName        : WideString;
    FPPattern     : WideString;
    Rpt           : TStringList;
    FilePath      : WideString;
    MaxMechLayer  : integer;
    VerMajor      : WideString;
    IsLib         : boolean;

function Version(const dummy : boolean) : TStringList;                      forward;
function ModelTypeToStr (ModType : T3DModelType) : WideString;              forward;
procedure SaveReportLog(FileExt : WideString, const display : boolean);     forward;
function GetCacheState (Value : TCacheState) : String;                      forward;
function GetPlaneConnectionStyle (Value : TPlaneConnectionStyle) : String;  forward;
function LayerKindToStr(LK : TMechanicalLayerKind) : WideString;            forward;
function LayerToIndex(var PL : TParameterList, const L : TLayer) : integer; forward;
procedure ReportTheBodies(const fix : boolean);                                forward;


{..................................................................................................}
procedure ReportLayersUsed;
var
    LayerUsed    : Array [0..1025]; // of boolean;
    LayerPCount  : Array [0..1025]; // of integer;
    LayerKind    : Array [0..1025]; // of TMechanicalLayerKind
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
    KindRow   : WideString;
    Layer     : TLayer;
    I, J      : integer;
    sLayer    : WideString;
    sKind     : WideString;
    HoleSet   : TSet;
    LayerStack    : IPCB_LayerStack_V7;
    MechLayer     : IPCB_MechanicalLayer;
    MechPairs     : IPCB_MechanicalLayerPairs;
    LegacyMLS     : boolean;
    MechLayerKind : TMechanicalLayerKind;
    ML1, ML2      : integer;

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
        CBoard := CurrentLib.Board;
        IsLib := true;
    end else
        CBoard  := PCBServer.GetCurrentPCBBoard;

    if ((CBoard = nil) and (CurrentLib = nil)) then
    begin
        ShowError('Failed to find PcbDoc or PcbLib.. ');
        exit;
    end;

    BeginHourGlass(crHourGlass);
//    Units := eImperial;

    VerMajor := Version(true).Strings(0);
    MaxMechLayer  := AD17MaxMechLayers;
    LegacyMLS     := true;
    MechLayerKind := NoMechLayerKind;
    if (VerMajor >= AD19VersionMajor) then
    begin
        LegacyMLS    := false;
        MaxMechLayer := AD19MaxMechLayers;
    end;

    Rpt := TStringList.Create;
    Rpt.Add(ExtractFileName(CBoard.FileName));
    Rpt.Add('');

    plLayerIndex := TParameterList.Create;

    for I := 0 to 1025 do
    begin
        LayerUsed[I]   := 0;    // used for 'prims on layer'
        LayerPCount[I] := 0;    // used for 'pairs' & 'prim count'
        LayerKind[I]   := NoMechLayerKind;
    end;

// assume same layerstack & mech pairs for whole library
// proper method has broken function return type so iterate.
    LayerStack := CBoard.LayerStack_V7;
    MechPairs  := CBoard.MechanicalPairs;
    for I := 1 to MaxMechLayer do
    begin
        ML1 := LayerUtils.MechanicalLayer(I);
        MechLayer := LayerStack.LayerObject_V7[ML1];
// layer must be enabled to have any primitives on it.
        if MechLayer.MechanicalLayerEnabled then
        begin
            LayerUsed[I] := cMLEnabled;
            if MechLayer.UsedByPrims then
                LayerUsed[I] := cMLUsedByPrims;

            if (not LegacyMLS) then
                 LayerKind[I] := MechLayer.Kind;

            for J := (I + 1) to MaxMechLayer do
            begin
                ML2 := LayerUtils.MechanicalLayer(J);
                MechLayer := LayerStack.LayerObject_V7[ML2];
                if MechLayer.MechanicalLayerEnabled then
                begin
                     if MechPairs.PairDefined(ML1, ML2) then
                     begin
                        LayerPCount[I]:= J;
                        LayerPCount[J]:= I;
                     end;
                end;
            end;
        end;
    end;

    Rpt.Add('');
    Rpt.Add(' Legend Pad Stacks (PS) Types :  Simple = S  |  Local = L  |  Full External = X');
    Rpt.Add('');
    Rpt.Add('');
    Rpt.Add('FootPrint                           PadStack| Primitive Counts  | Mechanical Layers                                                                                                             | 33 + ');
    Rpt.Add('Name                                    |PS |Pad|Reg|Trk|Txt|Fil| 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10| 11| 12| 13| 14| 15| 16| 17| 18| 19| 20| 21| 22| 23| 24| 25| 26| 27| 28| 29| 30| 31| 32|...');
    // Rpt.Add('');

// IPCB_Board.MechanicalLayerIterator.AddFilter_MechanicalLayers;   // IPCB_layerIterator

// report mech pairs
    if not LegacyMLS then
    begin
        LayerRow := '';
        KindRow  := '';
        for I := 1 to (MaxMechLayer) do
        begin
            J := LayerPCount[I];
            sLayer := IntToStr(J);
            sKind  :=  IntToStr(LayerKind[I]);
            if J = 0 then  sLayer := ' ';  // should never happen!

            if I <= cFullMechLayerReport then
            begin
                LayerRow := LayerRow + PadLeft(sLayer, 3) + '|';
                KindRow  := KindRow  + PadLeft(sKind, 3)  + '|';
            end else
            begin
                if (LayerUsed[I] >= cMLEnabled) then
                begin
                    LayerRow := LayerRow + PadLeft(sLayer, 4) + '|';
                    KindRow  := KindRow  + PadLeft(sKind, 4)  + '|';
                end;
            end;
        end;
        Rpt.Add('             Mechanical Layer Pairs  -->                        |' + LayerRow);
        Rpt.Add('                              Kinds  -->                        |' + KindRow);
    end;

// report mech layers used
    LayerRow := '';
    for I := 1 to (MaxMechLayer) do
    begin
        J := LayerUsed[I];
        sLayer := 'e ';
        if J = cMLUsedByPrims then sLayer := 'u ';
        if J = 0 then  sLayer := ' ';  // should never happen!

        if I <= cFullMechLayerReport then
        begin
            LayerRow := LayerRow + PadLeft(sLayer, 3) + '|';
        end else
        begin
            if (J > 0) then
                LayerRow := LayerRow + PadLeft(sLayer, 4) + '|';
        end;
    end;
    Rpt.Add('                 (E)nabled / (U)sed  -->                        |' + LayerRow);

    for I := 0 to 1025 do
    begin
        LayerUsed[I]   := 0;    // used for 'prims on layer'
        LayerPCount[I] := 0;    // used for 'prim count'
    end;

    HoleSet := MkSet(ePadObject, eViaObject);

    if IsLib then
        FPIterator := CurrentLib.LibraryIterator_Create
    else FPIterator := CBoard.BoardIterator_Create;
    FPIterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    FPIterator.AddFilter_IPCB_LayerSet(LayerSetUtils.AllLayers);
    if IsLib then
        FPIterator.SetState_FilterAll
    else
        FPIterator.AddFilter_Method(eProcessAll);   // TIterationMethod { eProcessAll, eProcessFree, eProcessComponents }

    Footprint := FPIterator.FirstPCBObject;
    while Footprint <> Nil Do
    begin
//  one of the next 4 or 5 lines seems to fix the erronous bounding rect of the alphabetic first item in Lib list
//  suspect it changes the Pad.Desc text as well
        if IsLib then
        begin
            CBoard := CurrentLib.Board;
            CurrentLib.SetState_CurrentComponent (Footprint);
        end;
        CBoard.ViewManager_FullUpdate;                // makes a slideshow
        CBoard.GraphicalView_ZoomRedraw;
//        if Not IsLib then CBoard.GraphicalView_ZoomOnRect(FootPrint.BoundingRectangleForPainting);
        if IsLib then CurrentLib.RefreshView;

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
        if PadStack = '' then PadStack := ' ';

        if IsLib then
        begin
            FPName    := Footprint.Name;
            FPPattern := '';
        end else
        begin
            FPName    := Footprint.Name.Text;
            FPPattern := Footprint.Pattern;
            FPName    := FPName + ' ' + FPPattern;
        end;

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

    if IsLib then
        CurrentLib.LibraryIterator_Destroy(FPIterator)
    else CBoard.BoardIterator_Destroy(FPIterator);

    if IsLib then CurrentLib.Navigate_FirstComponent;
    CBoard.GraphicalView_ZoomRedraw;
    if IsLib then CurrentLib.RefreshView;

    Rpt.Add('');

// report layer names & kinds if enabled
    Rpt.Add('Mechanical Layers Enabled  Names and Kinds');
    Rpt.Add('Index Name                    Kind & Description');
    for I := 1 to MaxMechLayer do
    begin
        ML1 := LayerUtils.MechanicalLayer(I);
        MechLayer := LayerStack.LayerObject_V7[ML1];
        if MechLayer.MechanicalLayerEnabled then
        begin
            LayerRow := PadRight(IntToStr(I), 5) + PadRight(MechLayer.Name, 35) ;
            if (not LegacyMLS) then
                 LayerRow := LayerRow + ' ' + PadRight(IntToStr(MechLayer.Kind),3) + ' = ' + LayerKindToStr(MechLayer.Kind);
            Rpt.Add(LayerRow);
        end;
    end;
    Rpt.Add('');

    Rpt.Add('Mechanical Layer Kinds Legend');
    if (false) and (not LegacyMLS) then
    begin
        LayerRow := '';
        KindRow  := '';
        for I := 0 to (MaxMechLayerKinds) do
        begin
            Rpt.Add(PadRight(IntToStr(I), 3) + ' = ' + LayerKindToStr(I) );
        end;
    end;

    plLayerIndex.Destroy;

    EndHourGlass;
    SaveReportLog('LayersUsedReport.txt', true);
    Rpt.Free;
end;

procedure ReportPadHole;
var
    Pad          : IPCB_Pad;
    PShape       : TShape;
    PadCache     : TPadCache;
    PlanesArray  : TPlanesConnectArray;
    CPL          : WideString;
    Layer        : TLayer;
    NoOfPrims    : Integer;
    BR           : TCoordRect;
    FPCoG        : TCoordPoint;
    BWOrigin     : TCoordPoint;
    TestPoint    : TPoint;
    BadFPList    : TStringList;
    I, L         : integer;
//    Units        : TUnit;

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
        CBoard := CurrentLib.Board;
        IsLib := true;
    end else
        CBoard  := PCBServer.GetCurrentPCBBoard;

    if (CBoard = nil) and (CurrentLib = nil) then
    begin
        ShowError('Failed to find PcbDoc or PcbLib.. ');
        exit;
    end;

    BeginHourGlass(crHourGlass);
//    Units := eImperial;
    BadFPList := TStringList.Create;
    Rpt       := TStringList.Create;
    Rpt.Add(ExtractFileName(CBoard.FileName));
    Rpt.Add('');
    Rpt.Add('');
    Rpt.Add('');

    // For each page of library is a footprint
    if IsLib then
        FPIterator := CurrentLib.LibraryIterator_Create
    else FPIterator := CBoard.BoardIterator_Create;
    FPIterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    FPIterator.AddFilter_IPCB_LayerSet(LayerSetUtils.AllLayers);
    if IsLib then
        FPIterator.SetState_FilterAll
    else
        FPIterator.AddFilter_Method(eProcessAll);   // TIterationMethod { eProcessAll, eProcessFree, eProcessComponents }

    Footprint := FPIterator.FirstPCBObject;
    while Footprint <> Nil Do
    begin
       if IsLib then
        begin
            FPName    := Footprint.Name;
            FPPattern := '';
        end else
        begin
            FPName    := Footprint.Name.Text;
            FPPattern := Footprint.Pattern;
            FPName    := FPName + ' ' + FPPattern;
        end;

// one of the next 4 or 5 lines seems to fix the erronous bounding rect of the alphabetic first item in Lib list
// suspect it changes the Pad.Desc text as well
        if IsLib then
        begin
            CurrentLib.SetBoardToComponentByName(Footprint.Name) ;   // fn returns boolean
//  this below line unselects selected objects;
            CurrentLib.SetState_CurrentComponent (Footprint);
            CurrentLib.RefreshView;
        end;

        CBoard.ViewManager_FullUpdate;
        CBoard.RebuildPadCaches;

        Rpt.Add('Footprint : ' + FPName + ' | ' + FPPattern);
        Rpt.Add('');

        BOrigin  := Point(CBoard.XOrigin,      CBoard.YOrigin     );  // abs Tcoord
        BWOrigin := Point(CBoard.WorldXOrigin, CBoard.WorldYOrigin);

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
            BadFPList.Add('BAD FP origin     ' + FPName);
        if (BR.x1 > 0) or (BR.x2 < 0) or (BR.y1 > 0) or (BR.y2 < 0) then
            BadFPList.Add('BAD origin Outside b.rect ' + FPName);

        if (abs(FPCoG.X) > MilsToRealCoord(200)) or (abs(FPCoG.Y) > MilsToRealCoord(200))then
            BadFPList.Add('possible bounding rect. offset ' + FPName);

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
                Pad := Prim;
                Layer := Pad.Layer;
                // Pad.HoleType := eRoundHole;
                // ePadMode_LocalStack;       // top-mid-bottom stack
                Rpt.Add('');
                Rpt.Add('Pad Name      : ' + Pad.Name);                  // should be designator / pin number
                Rpt.Add('Enabled       : ' + BoolToStr(Pad.Enabled, true) + '  (E=' + IntToStr(Pad.Enabled) + ') (ED=' + IntToStr(Pad.EnableDraw) + ')' );
                Rpt.Add('Layer         : ' + CBoard.LayerName(Layer));
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


//                Pad.XStackSizeOnLayer(eTopSolder);
//                PShape := Pad.StackShapeOnLayer(eTopPaste);
//                PShape := Pad.ShapeOnLayer(eTopPaste);
//                if Layer = eMultiLayer then
//                begin

                if Layer = eTopLayer then
                begin
//        BR same answer put no rotation adjustment.
                       BR := Pad.BoundingRectangleOnLayer(eTopPaste);
//                       Rpt.Add('Pad PM BROL Top(X,Y): (' + CoordUnitToString(BR.X2-BR.X1, Units) + ',' + CoordUnitToString(BR.Y2-BR.Y1, Units) + ')');
                       Rpt.Add('Pad PasteMask SOL  Top(X,Y): (' + CoordUnitToString(Pad.XSizeOnLayer(eTopPaste), Units) + ',' +
                                                    CoordUnitToString(Pad.YSizeOnLayer(eTopPaste), Units) + ')' );
                end;
                if Layer = eBottomLayer then
                begin
                      BR := Pad.BoundingRectangleOnLayer(eBottomPaste);
//                       Rpt.Add('Pad PM BROL Top(X,Y): (' + CoordUnitToString(BR.X2-BR.X1, Units) + ',' + CoordUnitToString(BR.Y2-BR.Y1, Units) + ')');
                       Rpt.Add('Pad PasteMask SOL  Top(X,Y): (' + CoordUnitToString(Pad.XSizeOnLayer(eBottomPaste), Units) + ',' +
                                                    CoordUnitToString(Pad.YSizeOnLayer(eBottomPaste), Units) + ')' );
                end;
//                end;
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
                CPL := '';
                if (PadCache.PlanesValid <> eCacheInvalid) Then
                begin
                    PlanesArray := PadCache.Planes;
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

    if IsLib then
        CurrentLib.LibraryIterator_Destroy(FPIterator)
    else CBoard.BoardIterator_Destroy(FPIterator);

    if IsLib then CurrentLib.Navigate_FirstComponent;
    CBoard.GraphicalView_ZoomRedraw;
    if IsLib then CurrentLib.RefreshView;

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

procedure ReportBodies;
begin
    ReportTheBodies(false);
end;
procedure FixAndReportBodyId;
begin
    ReportTheBodies(true);
end;

procedure ReportTheBodies(const fix : boolean);
var
    CompBody     : IPCB_ComponentBody;
    CompModel    : IPCB_Model;
    ModType      : T3DModelType;
    ModName      : WideString;
    CBodyName    : WideString;
    CompModelId  : WideString;
    MOrigin      : TCoordPoint;
    ModRot       : TAngle;
    NoOfPrims    : Integer;
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
        CBoard := CurrentLib.Board;
        IsLib := true;
    end else
        CBoard  := PCBServer.GetCurrentPCBBoard;

    if (CBoard = nil) and (CurrentLib = nil) then
    begin
        ShowError('Failed to find PcbDoc or PcbLib.. ');
        exit;
    end;

    BeginHourGlass(crHourGlass);
    BOrigin  := Point(CBoard.XOrigin,      CBoard.YOrigin     );  // abs Tcoord
    PLayerSet := LayerSetUtils.EmptySet;
    PLayerSet.Include(eTopLayer);
    PLayerSet.Include(eBottomLayer);

    Rpt := TStringList.Create;
    Rpt.Add(ExtractFileName(CBoard.FileName));
    Rpt.Add('');
    Rpt.Add('');
    Rpt.Add(PadRight('n',2) + ' | ' + PadRight('Footprint', 20) + ' | ' + PadRight('Identifier', 20) + ' | ' + PadRight('ModelName', 24) + ' | ' + PadRight('ModelType',12)
            + ' | ' + PadLeft('X',10) + ' | ' + PadLeft('Y',10) + ' | Ang ' );
    Rpt.Add('');

    // For each page of library is a footprint
    if IsLib then
        FPIterator := CurrentLib.LibraryIterator_Create
    else FPIterator := CBoard.BoardIterator_Create;
    FPIterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    FPIterator.AddFilter_IPCB_LayerSet(PLayerSet);
    if IsLib then
        FPIterator.SetState_FilterAll
    else
        FPIterator.AddFilter_Method(eProcessAll);   // TIterationMethod { eProcessAll, eProcessFree, eProcessComponents }

    Footprint := FPIterator.FirstPCBObject;
    while Footprint <> Nil Do
    begin
       if IsLib then
        begin
            FPName    := Footprint.Name;
            FPPattern := '';
            CurrentLib.SetState_CurrentComponent (Footprint)      // to make origin correct.
        end else
        begin
            FPName    := Footprint.Name.Text;
            FPPattern := Footprint.Pattern;
            FPName    := FPName + ' ' + FPPattern;
        end;

        Iterator := Footprint.GroupIterator_Create;
        Iterator.AddFilter_ObjectSet(MkSet(eComponentBodyObject));
        Iterator.AddFilter_IPCB_LayerSet(LayerSetUtils.AllLayers);

        NoOfPrims := 0;

        CompBody := Iterator.FirstPCBObject;
        while (CompBody <> Nil) Do
        begin
            CompModel := CompBody.Model;
            CBodyName := CompBody.Name;                      // ='' for all 3d comp body
            if CompModel <> nil then
            begin
                Inc(NoOfPrims);
                ModType     := CompModel.ModelType;
                MOrigin     := CompModel.Origin;
                ModRot      := CompModel.Rotation;
                CompModelId := CompBody.Identifier;
                if (Fix) then
                if (CompModelId = '') then  CompBody.SetState_Identifier(FPName);
                CompModelId := CompBody.Identifier;

                ModName := CBodyName;
           //     CompModel.Name := FPName;
           //     CompBody.Name  := FPName;
                if (ModType = e3DModelType_Generic) then
                    ModName := CompModel.FileName;

                Rpt.Add(PadRight(IntToStr(NoOfPrims),2) + ' | ' + PadRight(FPName, 20) + ' | ' + PadRight(CompModelId, 20) + ' | ' + PadRight(ModName, 24) + ' | ' + PadRight(ModelTypeToStr(ModType), 12)
                        + ' | ' + PadLeft(IntToStr(MOrigin.X-BOrigin.X),10) + ' | ' + PadLeft(IntToStr(MOrigin.Y-BOrigin.Y),10) + ' | ' + FloatToStr(ModRot) );
            end;
            CompBody := Iterator.NextPCBObject;
        end;

        Rpt.Add('');

        Footprint.GroupIterator_Destroy(Iterator);
        Footprint := FPIterator.NextPCBObject;
    end;

    if IsLib then
        CurrentLib.LibraryIterator_Destroy(FPIterator)
    else CBoard.BoardIterator_Destroy(FPIterator);

    if IsLib then CurrentLib.Navigate_FirstComponent;
    CBoard.GraphicalView_ZoomRedraw;
    if IsLib then CurrentLib.RefreshView;

    EndHourGlass;

    SaveReportLog('FPBodyReport.txt', true);
    Rpt.Free;
end;
{..................................................................................................}
{..................................................................................................}
function ModelTypeToStr (ModType : T3DModelType) : WideString;
begin
    Case ModType of
        0                     : Result := 'Extruded';            // AD19 defines e3DModelType_Extrude but not work.
        e3DModelType_Generic  : Result := 'Generic';
        2                     : Result := 'Cylinder';
        3                     : Result := 'Sphere';
    else
        Result := 'unknown';
    end;
end;
{..................................................................................................}
function Version(const dummy : boolean) : TStringList;
begin
    Result               := TStringList.Create;
    Result.Delimiter     := '.';
    Result.Duplicates    := dupAccept;
    Result.DelimitedText := Client.GetProductVersion;
end;
{..................................................................................................}
procedure SaveReportLog(FileExt : WideString, const display : boolean);
var
    FileName : TPCBString;
    SerDoc   : IServerDocument;
begin
//    FileName := ChangeFileExt(CBoard.FileName, FileExt);
    FileName := ChangeFileExt(CBoard.FileName, FileExt);
    Rpt.SaveToFile(Filename);
    SerDoc  := Client.OpenDocument('Text', FileName);
    If display and (SerDoc <> Nil) Then
    begin
        Client.ShowDocument(SerDoc);
        if (SerDoc.GetIsShown <> 0 ) then
            SerDoc.DoFileLoad;
    end;
end;
{..................................................................................................}
function LayerKindToStr(LK : TMechanicalLayerKind) : WideString;
begin
    case LK of
    NoMechLayerKind : Result := 'Not Set';            // single
    1               : Result := 'Assembly Top';
    2               : Result := 'Assembly Bottom';
    3               : Result := 'Assembly Notes';     // single
    4               : Result := 'Board';
    5               : Result := 'Coating Top';
    6               : Result := 'Coating Bottom';
    7               : Result := 'Component Center Top';
    8               : Result := 'Component Center Bottom';
    9               : Result := 'Component Outline Top';
    10              : Result := 'Component Outline Bottom';
    11              : Result := 'Courtyard Top';
    12              : Result := 'Courtyard Bottom';
    13              : Result := 'Designator Top';
    14              : Result := 'Designator Bottom';
    15              : Result := 'Dimensions';         // single
    16              : Result := 'Dimensions Top';
    17              : Result := 'Dimensions Bottom';
    18              : Result := 'Fab Notes';         // single
    19              : Result := 'Glue Points Top';
    20              : Result := 'Glue Points Bottom';
    21              : Result := 'Gold Plating Top';
    22              : Result := 'Gold Plating Bottom';
    23              : Result := 'Value Top';
    24              : Result := 'Value Bottom';
    25              : Result := 'V Cut';             // single
    26              : Result := '3D Body Top';
    27              : Result := '3D Body Bottom';
    28              : Result := 'Route Tool Path';   // single
    29              : Result := 'Sheet';             // single
    else              Result := 'Unknown'
    end;
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

