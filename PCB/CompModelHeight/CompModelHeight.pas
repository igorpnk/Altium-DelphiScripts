{ CompModelHeights.pas

 Report all comp body models & max projections up & down:
    Iterate all footprints within the current doc.
    Get the overall height & standoff from 3d bodies & calc the max body height
    projections up & down allowing for board thickness.


 Author B. Miller
 26/01/2020  v0.1 POC
 27/01/2020  V0.2 Implement board thickness adjustment to standoff for reverse side projections.

}
var
    Rpt       : TStringList;
    FileName  : WideString;
    Document  : IDocument;

function ModelTypeToStr (ModType : T3DModelType) : WideString;
begin
    Case ModType of
        0 : Result := 'Extruded';
        1 : Result := 'Generic 3D';
        2 : Result := 'Cylinder';
        3 : Result := 'Sphere';
    else
        Result := 'unknown';
    end;
end;

function BoardThickness(LayerStack : IPCB_LayerStack) : TCoord;
var
    LayerObj    : IPCB_LayerObject;
    LayerClass  : TLayerClassID;
    Dielectric  : IPCB_DielectricObject;
    Copper      : IPCB_ElectricalLayer;

begin
    Result := 0;

    for LayerClass := eLayerClass_All to eLayerClass_PasteMask do
    begin
        LayerObj := LayerStack.First(LayerClass);

        while (LayerObj <> Nil ) do
        begin
            LayerObj.IsInLayerStack;       // check always true.

            if (LayerClass = eLayerClass_Electrical) or (LayerClass = eLayerClass_Signal) then
            begin
                Copper := LayerObj;
                Result := Result + Copper.CopperThickness;
//                LayerPos  := IntToStr(Board.LayerPositionInSet(AllLayers, Copper));       // think this only applies to eLayerClass_Electrical
            end;
            if (LayerClass = eLayerClass_Dielectric) or (LayerClass = eLayerClass_SolderMask) then
            begin
                Dielectric := LayerObj;   // .Dielectric Tv6
                Result := Result + Dielectric.DielectricHeight;
            end;

            LayerObj := LayerStack.Next(Layerclass, LayerObj);
        end;
    end;
    if Result <= 0 then Result := MMsToCoord(1.6);  // default thickness (1.6mm)
end;

function BoardSideToStr (BS : TBoardSide) : WideString;
// cBoardSideStrings[    ] broken
begin
    Case BS of
        eBoardSide_Top    : Result := 'Top Side   ';
        eBoardSide_Bottom : Result := 'Bottom Side';
    else
        Result            := 'bad side!  ';
    end;
end;

Procedure GetCompModelHeight;
Var
    Board            : IPCB_Board;
//    LayerStack       : IPCB_LayerStack;
    FIterator        : IPCB_Iterator;
    GIterator        : IPCB_GroupIterator;
    BrdThickness     : TCoord;

    Footprint        : IPCB_Component;
    MaxTHFP          : IPCB_Component;
    MaxBHFP          : IPCB_Component;  // backside projection max
    FPName           : IPCB_Text;       // Short string?
    I                : Integer;
    FPPattern        : TPCBString;
    FPHeight         : TCoord;

    CompBody         : IPCB_ComponentBody;
    MyModel          : IPCB_Model;
    MaxTHeight       : TCoord;
    MaxBHeight       : TCoord;      // backside max height
    ModDefName       : TPCBString;  // WideString
    ModFileName      : WideString;
    ModHeight        : TCoord;
    ModStandOff      : TCoord;
    ModProject       : TBoardSide;        // cBoardSideStrings : Array [TBoardSide] Of String[20] = ('Top Side','Bottom Side');
    ModLayer         : TLayer;
    ModType          : T3DModelType;

    Count3DB         : Integer;

    ButtonSelected   : Integer;
    AView            : IServerDocumentView;
    AServerDocument  : IServerDocument;

Begin
    MaxTHeight := 0;
    MaxBHeight := 0;
    MaxTHFP    := nil;
    MaxBHFP    := nil;

    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then
    Begin
         ShowMessage('Not a PCB document');
         Exit;
    End;

    BrdThickness := BoardThickness(Board.LayerStack);

    Rpt := TStringList.Create;
    Rpt.Add('');
    Rpt.Add('3D Models:');

    FIterator := Board.BoardIterator_Create;
    FIterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    FIterator.AddFilter_LayerSet(AllLayers);
    FIterator.AddFilter_Method(eProcessAll);   // TIterationMethod { eProcessAll, eProcessFree, eProcessComponents }
//    FIterator.SetState_FilterAll;

    Rpt.Add(' Layer      ModType             Projection   Model height & standoff     filename');

    try
        Footprint := FIterator.FirstPCBObject;

        while Footprint <> Nil Do
        begin
            Rpt.Add('');
            FPName    := Footprint.Name.Text;
            FPPattern := Footprint.Pattern;
            FPHeight  := Footprint.Height;

            Rpt.Add('FP ' + FPName + '   ' + FPPattern + '  FP height ' + CoordUnitToString(FPHeight, cUnitMM) );

            GIterator := Footprint.GroupIterator_Create;
            GIterator.Addfilter_ObjectSet(MkSet(eComponentBodyObject));

            CompBody := GIterator.FirstPCBObject;
            While CompBody <> Nil Do
            Begin
                MyModel := CompBody.Model;
                ModDefName  := '';
                ModFileName := '';

                if MyModel <> nil then
                begin
                    ModDefName  := MyModel.Name;    //  DefaultPCB3DModel;
                    ModFileName := MyModel.FileName;
                    MyModel.Rotation;
                    MyModel.ModelType;
                    // MyModel.UniqueName;
                    // MyModel.Descriptor    .Detail;
                    // MyModel.SaveModelToFile(path);
                end;

                ModProject  := CompBody.BodyProjection;
                ModStandOff := CompBody.StandoffHeight;
                ModHeight   := CompBody.OverallHeight;
                ModLayer    := CompBody.Layer;
                ModType     := CompBody.GetState_ModelType;  // T3DModelType

                If ModProject = eBoardSide_Top then
                begin
                    if ModHeight > MaxTHeight Then
                    begin
                        MaxTHeight := ModHeight;
                        MaxTHFP    := Footprint;
                    end;
                //  projection thru board to bottom side
                    If (-1 * ModStandOff - BrdThickness) > MaxBHeight Then
                    begin
                        MaxBHeight := -1 * ModStandOff - BrdThickness;
                        MaxBHFP    := Footprint;
                    end;
                end
                else begin
                    if ModHeight > MaxBHeight Then
                    begin
                        MaxBHeight := ModHeight;
                        MaxBHFP    := Footprint;
                    end;
                //  projection thru to top side board
                    if (-1 * ModStandOff - BrdThickness) > MaxTHeight Then
                    begin
                        MaxTHeight := -1 * ModStandOff - BrdThickness;
                        MaxTHFP    := Footprint;
                    end;
                end;

 // LayerUtils.AsString(CurrentLayer) + '  ' + Layer2String() +  Board.LayerName(CurrentLayer) + '  ' + LayerObject.Name ;

                Rpt.Add(' ' + Board.LayerName(ModLayer) + '  ' + PadRight(ModelTypeToStr(ModType), 10) + '  ' + BoardSideToStr(ModProject) +
                        '  ' + CoordUnitToString(ModHeight, cUnitMM ) + '  ' + CoordUnitToString(ModStandOff, cUnitMM) + '       ' + ModFileName);

                If ModHeight <> 0 Then
                    If ModHeight > Footprint.Height Then
                    Begin
//                         Footprint.Height := MyModel.OverallHeight;
                         Inc(Count3DB);
                    End;

                CompBody := GIterator.NextPCBObject;
            End;

            Footprint.GroupIterator_Destroy(GIterator);
            Footprint := FIterator.NextPCBObject;
        End;

    finally

        if Count3DB>0 then
        begin
            // warn FP height is less than 3D model height n times ??
        end;

        ShowMessage('Max 3D Model Height Up ' + CoordUnitToString(MaxTHeight, cUnitMM ) + '  down ' + CoordUnitToString(MaxBHeight, cUnitMM ));   // FloatToStrF(MaxHeight, ffNumber, 3, 6));

        Board.BoardIterator_Destroy(FIterator);
    end;

    Rpt.Insert(0, '3D Model Information for ' + ExtractFileName(Board.FileName) + ' document.');
    Rpt.Insert(1, '----------------------------------------------------------');
    Rpt.Insert(2, 'Board Thickness  ' + CoordUnitToString(BrdThickness, eMetric) );
    Rpt.Insert(3, 'Max (top side projection ) 3D Model Height ' + MaxTHFP.Pattern + '  ' + CoordUnitToString(MaxTHeight, cUnitMM ));
    Rpt.Insert(4, 'Max (bottom side projn.  ) 3D Model Height ' + MaxBHFP.Pattern + '  ' + CoordUnitToString(MaxBHeight, cUnitMM ));

    // Display the report
    FileName := ExtractFilePath(Board.FileName) + ChangefileExt(ExtractFileName(Board.FileName),'') + '-3DModelReport.txt';
    Rpt.SaveToFile(Filename);
    Rpt.Free;

    Document  := Client.OpenDocument('Text', FileName);
    If Document <> Nil Then
    begin
        Client.ShowDocument(Document);
        if (Document.GetIsShown <> 0 ) then
            Document.DoFileLoad;
    end;

End;
{ eof }

