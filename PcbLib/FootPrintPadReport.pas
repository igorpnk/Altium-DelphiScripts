{ FootPrintPadReport.pas

 from GeometryHeight..
 from General\TextFileConvert.pas
 from Footprint-SS-Fix.pas 16/09/2017

 13/09/2019  BLM  rev0.1  Cut&paste out of Footprint-SS-Fix.pas

}
//...................................................................................

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

begin
    CurrentLib := PCBServer.GetCurrentPCBLibrary;
    If CurrentLib = Nil Then
    Begin
        ShowMessage('This is not a PcbLib document');
        Exit;
    End;


    // For each page of library is a footprint
    FPIterator := CurrentLib.LibraryIterator_Create;
    FPIterator.SetState_FilterAll;
    FPIterator.AddFilter_LayerSet(AllLayers);

    Rpt := TStringList.Create;
    Rpt.Add(ExtractFileName(CurrentLib.Board.FileName));
    Rpt.Add('');

    Footprint := FPIterator.FirstPCBObject;
    while Footprint <> Nil Do
    begin
        Rpt.Add('Footprint : ' + Footprint.Name);

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
                Rpt.Add('Pad.x        : ' + PadRight(CoordToMils(Pad.x),10)                + '  Pad.y       : ' + PadRight(CoordToMils(Pad.y),10) );
                Rpt.Add('Pad offsetX  : ' + PadRight(CoordToMils(Pad.XPadOffset(Layer)),10) + '  Pad offsetY : ' + PadRight(CoordToMils(Pad.YPadOffset(Layer)),10) );
                Rpt.Add('Holesize     : ' + CoordUnitToString(Pad.Holesize,eMetric));
                Rpt.Add('Holetype     : ' + BoolToStr(Pad.Holetype));
                Rpt.Add('DrillType    : ' + IntToStr(Pad.DrillType));
                Rpt.Add('Plated       : ' + BoolToStr(Pad.Plated));

                Rpt.Add('Pad Name     : ' + Pad.Name);         // should be designator / pin number
                Rpt.Add('Pad ID       : ' + Pad.Identifier);
                Rpt.Add('Pad desc     : ' + Pad.Descriptor);
                Rpt.Add('Pad Detail   : ' + Pad.Detail);
                Rpt.Add('Pad ObjID    : ' + Pad.ObjectIDString);
                Rpt.Add('Pad Pin Desc : ' + Pad.PinDescriptor);

                Rpt.Add('Pad Mode     : ' + IntToStr(Pad.Mode));
                Rpt.Add('Pad Stack Size Top(X,Y): (' + CoordUnitToString(Pad.TopXSize,eMetric) + ',' + CoordUnitToString(Pad.TopYSize,eMetric) + ')');
                Rpt.Add('Pad Stack Size Mid(X,Y): (' + CoordUnitToString(Pad.MidXSize,eMetric) + ',' + CoordUnitToString(Pad.MidYSize,eMetric) + ')');
                Rpt.Add('Pad Stack Size Bot(X,Y): (' + CoordUnitToString(Pad.BotXSize,eMetric) + ',' + CoordUnitToString(Pad.BotYSize,eMetric) + ')');

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

                Rpt.Add('PEX  : ' + CoordUnitToString(PadCache.PasteMaskExpansion, eMetric) );
                Rpt.Add('SMEX : ' + CoordUnitToString(PadCache.SolderMaskExpansion,eMetric) );
            end;

            Handle := Iterator.NextPCBObject;
        end;

        Rpt.Add('Num Pads: ' + IntToStr(NoOfPrims));
        Rpt.Add('');

        Footprint.GroupIterator_Destroy(Iterator);
        Footprint := FPIterator.NextPCBObject;
    end;

    CurrentLib.LibraryIterator_Destroy(FPIterator);

    SaveReportLog('PadHoleReport.txt', true);
    Rpt.Free;

end;

