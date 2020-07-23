{ CompModelHeights.pas

 Report all comp body models & max projections up & down:
    Iterate all footprints within the current doc.
    Get the overall height & standoff from 3d bodies & calc the max body height
    projections up & down allowing for board thickness.

ReportCompModelHeights()

 Author B. Miller
 26/01/2020  v0.1  POC
 27/01/2020  v0.2  Implement board thickness adjustment to standoff for reverse side projections.
             v0.21 Report sum the top & bottom heights & PCB thickness.
 27/01/2020  v0.22 Impl. export generic models to composite name from pattern & model.
 28/01/2020  v0.23 Check export folder exists before writing report file to it.
 23/06/2020  v0.24 Fixed export filename & model type check
 23/07/2020  v0.25 Add PcbLib support to GetCompModelHeight()
 24/07/2020  v0.26 Handle finding no top or bottom projection models. (display <none>)

Import/Export Board Step removed.

}
const
    cModel3DGeneric   = 'Generic Model';
    cModel3DExtruded  = 'Extruded';
    cExport3DMFolder  = 'Exported3DModels\';
    cExportCuCompStep = 4;
    cSXFolder         = 'stex';
    cSXOffsets        = '_Offsets.txt';
    cCoreFNLabel      = 'CoreFileName';

    cDummyTuples      = 'Area=51';

var
    Project   : IProject;
    Document  : IDocument;
    Rpt       : TStringList;
    FileName  : WideString;
    Board     : IPCB_Board;
    PcbLib    : IPCB_Library;
    BOrigin   : TPoint;

function ModelTypeToStr (ModType : T3DModelType) : WideString;
begin
    Case ModType of
        0                     : Result := 'Extruded';            // AD19 defines e3DModelType_Extrude but not works.
        e3DModelType_Generic  : Result := 'Generic Model';
        2                     : Result := 'Cylinder';
        3                     : Result := 'Sphere';
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
            if (LayerClass = eLayerClass_Electrical) then   // includes eLayerClass_Signal
            begin
                Copper := LayerObj;
                Result := Result + Copper.CopperThickness;
//                LayerPos  := IntToStr(Board.LayerPositionInSet(AllLayers, Copper));       // think this only applies to eLayerClass_Electrical
            end;
            if (LayerClass = eLayerClass_Dielectric) then   // includes eLayerClass_SolderMask
            begin
                Dielectric := LayerObj;   // .Dielectric Tv6
                Result := Result + Dielectric.DielectricHeight;
            end;

            LayerObj := LayerStack.Next(Layerclass, LayerObj);
        end;
    end;
    if Result <= 0 then Result := MMsToCoord(1.6);  // default thickness (1.6mm)
end;

function OSSafeFileName(FN : WideString) : WideString;
begin
    Result := GetWindowsFileName(FN);
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

function CheckForModelDifference(CompBody : IPCB_ComponentBody, FPO : IPCB_Component) : boolean;
var
    GIterator     : IPCB_GroupIterator;
    CompBody2     : IPCB_ComponentBody;
    CompModel     : IPCB_Model;
    CompModel2    : IPCB_Model;
    ModFileName   : WideString;
    ModFileName2  : WideString;

begin
    Result := false;
    if FPO = nil then exit;

    CompModel := CompBody.Model;
  
    GIterator := FPO.GroupIterator_Create;
    GIterator.Addfilter_ObjectSet(MkSet(eComponentBodyObject));
    CompBody2 := GIterator.FirstPCBObject;

    while CompBody2 <> Nil do
    begin
        if CompBody2.GetState_ModelType = CompBody.GetState_ModelType then
        begin
            CompModel2   := CompBody2.Model;
            ModFileName  := '';
            ModFileName2 := '';

            if CompModel2 <> nil then
                ModFileName2 := CompModel2.FileName;
            if CompModel <> nil then
                ModFileName := CompModel.FileName;

            if ModFileName2             <> ModFileName             then Result := true;
            if CompBody2.BodyProjection <> CompBody.BodyProjection then Result := true;
            if CompBody2.StandOffHeight <> CompBody.StandoffHeight then Result := true;
            if CompBody2.OverallHeight  <> CompBody.OverallHeight  then Result := true;
            if CompBody2.Layer          <> CompBody.Layer          then Result := true;
        end;
        CompBody2 := GIterator.NextPCBObject;
    end;
    FPO.GroupIterator_Destroy(GIterator);
end;

Procedure ReportModelHeights;
Var
//    LayerStack       : IPCB_LayerStack;
    FIterator        : IPCB_BoardIterator;
    GIterator        : IPCB_GroupIterator;
    BrdThickness     : TCoord;

//    Footprint        : IPCB_LibComponent;
    Footprint        : IPCB_Component;
    OListFP          : IPCB_Component;
    MaxTHFP          : IPCB_Component;
    MaxBHFP          : IPCB_Component;  // backside projection max
    FPName           : IPCB_Text;       // Short string?
    I, J             : Integer;
    FPPattern        : TPCBString;
    FPHeight         : TCoord;

    CompBody         : IPCB_ComponentBody;
    CompModel        : IPCB_Model;
    MaxTHeight       : TCoord;
    MaxBHeight       : TCoord;      // backside max height
    ModDefName       : TPCBString;  // WideString
    ModFileName      : WideString;
    MaxTHFPName      : WideString;   // name of height FP
    MaxBHFPName      : WideString;   // name of height FP
    ModHeight        : TCoord;
    ModStandOff      : TCoord;
    ModProject       : TBoardSide;        // cBoardSideStrings : Array [TBoardSide] Of String[20] = ('Top Side','Bottom Side');
    ModLayer         : TLayer;
    ModType          : T3DModelType;

    CompFPPattern    : TStringList;
    FPOList          : TObjectList;      // Unique Footprint list
    Count3DBody      : Integer;

    ButtonSelected   : Integer;
    AView            : IServerDocumentView;
    AServerDocument  : IServerDocument;
    IsLib            : boolean;

Begin
    Count3DBody := 0;
    MaxTHeight  := 0;
    MaxBHeight  := 0;
    MaxTHFP     := nil;
    MaxBHFP     := nil;

    Document := GetWorkSpace.DM_FocusedDocument;
    if not ((Document.DM_DocumentKind = cDocKind_PcbLib) or (Document.DM_DocumentKind = cDocKind_Pcb)) Then
    begin
         ShowMessage('No PcbDoc or PcbLib selected. ');
         Exit;
    end;
    IsLib  := false;
    if (Document.DM_DocumentKind = cDocKind_PcbLib) then
    begin
        PcbLib := PCBServer.GetCurrentPCBLibrary;
        Board := PcbLib.Board;
        IsLib := true;
    end else
        Board  := PCBServer.GetCurrentPCBBoard;

    if (Board = nil) and (PcbLib = nil) then
    begin
        ShowError('Failed to find PcdDoc or PcbLib.. ');
        exit;
    end;
   
    BrdThickness := BoardThickness(Board.LayerStack);

    Rpt := TStringList.Create;
    Rpt.Add('');
    Rpt.Add('3D Models:');

// need to store RefDes & FP of highest models
// need to check if a FP model is diff to others of the same FPs 
// list of RefDes vs FP pattern
// list of RefDes vs it's FP max body height
// only report unique footprint heights.

// designator linked FP patterns & heights
    CompFPPattern               := TStringList.Create;
//    CompFPPattern.Delimiter     := '|';
//    CompFPPattern.Duplicates    := dupIgnore;        // dupAccept  dupIgnore
//    CompFPPattern.DelimitedText := cDummyTuples;     // dummy start data

    FPOList := TObjectList.Create;

    if IsLib then
        FIterator := PcbLib.LibraryIterator_Create
    else FIterator := Board.BoardIterator_Create;

    FIterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    FIterator.AddFilter_IPCB_LayerSet(LayerSetUtils.AllLayers);
    if IsLib then
        FIterator.SetState_FilterAll
    else
    FIterator.AddFilter_Method(eProcessAll);   // TIterationMethod { eProcessAll, eProcessFree, eProcessComponents }

    Rpt.Add(' Layer      ModType             Projection   Model height & standoff     filename');

    MaxBHFPName := '<none>'; MaxTHFPName := '<none>';
    MaxBHeight  := 0;        MaxTHeight  := 0;
    MaxBHFP     := nil;      MaxTHFP     := nil;

    Footprint := FIterator.FirstPCBObject;
    while Footprint <> Nil Do
    begin
        J := 1;
        if IsLib then
        begin
            FPName := Footprint.Name;
            FPPattern := '';
        end else
        begin
            FPName    := Footprint.Name.Text;
            FPPattern := Footprint.Pattern;
        end;
        FPHeight  := Footprint.Height;

        GIterator := Footprint.GroupIterator_Create;
        GIterator.Addfilter_ObjectSet(MkSet(eComponentBodyObject));
        CompBody := GIterator.FirstPCBObject;

        while CompBody <> Nil do
        begin
            CompModel := CompBody.Model;
            ModDefName  := '';
            ModFileName := '';

            if CompModel <> nil then
            begin
                ModDefName  := CompModel.Name;    //  DefaultPCB3DModel;
                ModFileName := CompModel.FileName;
                CompModel.Rotation;
                CompModel.ModelType;
                    // CompModel.UniqueName;
                    // CompModel.Descriptor    .Detail;
                    // CompBody.SaveModelToFile(path);
            end;

            ModProject  := CompBody.BodyProjection;
            ModStandOff := CompBody.StandoffHeight;
            ModHeight   := CompBody.OverallHeight;
            ModLayer    := CompBody.Layer;
            ModType     := CompBody.GetState_ModelType;  // T3DModelType

 //  Add one instance of unique FPs (name or o.height or standoff or model filename)
//                if FPOList.IndexOf(Footprint) = -1 then
//                    FPOList.Add(Footprint)
//                else begin
//                    for I := 0 to (FPOList.Count - 1) do
//                    begin
//                        OListFP := FPOList.Items(I);
//                        if CheckForModelDifference(CompBody, OListFP) then
//                        begin
//                            FPOList.Add(Footprint);
            if J = 1 then
                Rpt.Add('FP ' + FPName + '   ' + FPPattern + '  FP height ' + CoordUnitToString(FPHeight, cUnitMM) );

               // LayerUtils.AsString(CurrentLayer) + '  ' + Layer2String() +  Board.LayerName(CurrentLayer) + '  ' + LayerObject.Name ;
            Rpt.Add(' '  + Board.LayerName(ModLayer)  + '  ' + PadRight(ModelTypeToStr(ModType), 10) +
                    '  ' + BoardSideToStr(ModProject) + '  ' + CoordUnitToString(ModHeight, cUnitMM ) +
                    '  ' + CoordUnitToString(ModStandOff, cUnitMM) + '       ' + ModFileName);
//                        end;

//                    end;
//                end;

            If ModProject = eBoardSide_Top then
            begin
                if ModHeight > MaxTHeight Then
                begin
                    MaxTHeight := ModHeight;
                    MaxTHFP    := Footprint;
                end;
//        projection thru board to bottom side
                If (-1 * ModStandOff - BrdThickness) > MaxBHeight Then
                begin
                    MaxBHeight := -1 * ModStandOff - BrdThickness;
                    MaxBHFP    := Footprint;
                end;
            end
            else begin
                if ModHeight > MaxBHeight then
                begin
                    MaxBHeight := ModHeight;
                    MaxBHFP    := Footprint;
                end;
//       projection thru to top side board
                if (-1 * ModStandOff - BrdThickness) > MaxTHeight then
                begin
                    MaxTHeight := -1 * ModStandOff - BrdThickness;
                    MaxTHFP    := Footprint;
                end;
            end;

            if ModHeight <> 0 then
                if ModHeight > Footprint.Height then
                begin
//                     Footprint.Height := CompModel.OverallHeight;
                     Inc(Count3DBody);
                end;

            CompBody := GIterator.NextPCBObject;
        end;

        Footprint.GroupIterator_Destroy(GIterator);
        Footprint := FIterator.NextPCBObject;
    end;

    if IsLib then
        PcbLib.LibraryIterator_Destroy(FIterator)
    else Board.BoardIterator_Destroy(FIterator);


    ShowMessage('Max 3D Model Height Up ' + CoordUnitToString(MaxTHeight, cUnitMM ) + '  down ' + CoordUnitToString(MaxBHeight, cUnitMM ));   // FloatToStrF(MaxHeight, ffNumber, 3, 6));

    FPOList.Destroy;

    if IsLib then
    begin
        if MaxTHFP <> nil then MaxTHFPName := MaxTHFP.Name;
        if MaxBHFP <> nil then MaxBHFPName := MaxBHFP.Name;
    end else
    begin
        if MaxTHFP <> nil then MaxTHFPName := MaxTHFP.Name.Text + '  ' + MaxTHFP.Pattern;
        if MaxBHFP <> nil then MaxBHFPName := MaxBHFP.Name.Text + '  ' + MaxBHFP.Pattern;
    end;

    Rpt.Insert(0, '3D Model Information for ' + ExtractFileName(Board.FileName) + ' document.');
    Rpt.Insert(1, '----------------------------------------------------------');
    Rpt.Insert(2, 'Board Thickness  ' + CoordUnitToString(BrdThickness, eMetric) );
    Rpt.Insert(3, 'Max (top side projection ) 3D Model Height ' + MaxTHFPName + '  ' + CoordUnitToString(MaxTHeight, cUnitMM ));
    Rpt.Insert(4, 'Max (bottom side projn.  ) 3D Model Height ' + MaxBHFPName + '  ' + CoordUnitToString(MaxBHeight, cUnitMM ));
    Rpt.Insert(5, 'Total Overall Height top to bottom ' + CoordUnitToString( (MaxBHeight + MaxTHeight + BrdThickness), cUnitMM ));

    // Display the report
    FileName := ExtractFilePath(Board.FileName) + ChangefileExt(ExtractFileName(Board.FileName),'') + '-3DModelReport.txt';
    Rpt.SaveToFile(Filename);

    Rpt.Free;
    CompFPPattern.Free;
   
    Document  := Client.OpenDocument('Text', FileName);
    If Document <> Nil Then
    begin
        Client.ShowDocument(Document);
        if (Document.GetIsShown <> 0 ) then
            Document.DoFileLoad;
    end;
End;


Procedure ExportCompModels;
var
    FIterator        : IPCB_BoardIterator;
    GIterator        : IPCB_GroupIterator;

    Footprint        : IPCB_Component;
    FPPattern        : TPCB_String;
    FPName           : IPCB_Text;
    CompBody         : IPCB_ComponentBody;
    CompModel        : IPCB_Model;
    TempCompModel    : IPCB_Model;
    ModType          : T3DModelType;
    FilePath         : WideString;
    ModFileName      : WideString;
    FSSafeFileName   : WideString;
    FileSaved        : boolean;

    ORotX,ORotY,ORotZ : double;
    OISOHeight        : integer;

begin
    Document := GetWorkSpace.DM_FocusedDocument;
    Board := PCBServer.GetCurrentPCBBoard;
    If Board = Nil Then Exit;

    FilePath := ExtractFilePath(Board.FileName) + cExport3DMFolder;

    Rpt := TStringList.Create;
    Rpt.Add('');
    Rpt.Add('Export Generic 3D Models:');

    FIterator := Board.BoardIterator_Create;
    FIterator.AddFilter_ObjectSet(MkSet(eComponentObject));
    FIterator.AddFilter_IPCB_LayerSet(LayerSetUtils.AllLayers);
    FIterator.AddFilter_Method(eProcessAll);   // TIterationMethod { eProcessAll, eProcessFree, eProcessComponents }

    try
        Footprint := FIterator.FirstPCBObject;

        while Footprint <> Nil Do
        begin
//            Rpt.Add('');
            FPName    := Footprint.Name.Text;
            FPPattern := Footprint.Pattern;

            GIterator := Footprint.GroupIterator_Create;
            GIterator.Addfilter_ObjectSet(MkSet(eComponentBodyObject));

            CompBody := GIterator.FirstPCBObject;
            While CompBody <> Nil Do
            Begin
                CompModel := CompBody.Model;

                if not DirectoryExists(FilePath) then DirectoryCreate(FilePath);
                FileSaved := false;

                if CompModel <> nil then
                begin
                    ModFileName := CompModel.FileName;
                    ModFileName := FPPattern + '_' + ModFileName;
                    FSSafeFileName := ModFileName;

                    CompModel.Rotation;
                    // CompBody.SetState_FromModel;
        //            TempCompModel := CompModel.I_Replicate;

                    ORotX := 0.01 ; ORotY := 0.01; ORotZ := 0.01; OISOHeight := 1;
       //             TempCompModel.GetState(Get ORotX, ORotY, ORotZ, OISOHeight);

                    ModType     := CompModel.ModelType;
               //   ModType     := CompBody.GetState_ModelType;  // T3DModelType
                    if ModelTypeToString(ModType) =  cModel3DGeneric then
                    begin

                        FSSafeFileName := OSSafeFileName(ModFileName);
                        FileSaved := CompBody.SaveModelToFile(FilePath + FSSafeFileName);
                        Rpt.Add('FP ' + FPName + '  ' + FPPattern + '  exported to  ' + FSSafeFileName);
                    end;
                end;

                CompBody := GIterator.NextPCBObject;
            End;

            Footprint.GroupIterator_Destroy(GIterator);
            Footprint := FIterator.NextPCBObject;
        End;

    finally

        Board.BoardIterator_Destroy(FIterator);
    end;
 
    Rpt.Insert(0, 'Export 3D Models  for ' + ExtractFileName(Board.FileName) );
    Rpt.Insert(1, '----------------------------------------------------------');

    // Display the report
    if DirectoryExists(FilePath) then
        FileName := FilePath +                        ChangefileExt(ExtractFileName(Board.FileName),'') + '-3DModelExportReport.txt'
    else
        FileName := ExtractFilePath(Board.FileName) + ChangefileExt(ExtractFileName(Board.FileName),'') + '-3DModelExportReport.txt';

    Rpt.SaveToFile(Filename);
    Rpt.Free;

    Document  := Client.OpenDocument('Text', FileName);
    If Document <> Nil Then
    begin
        Client.ShowDocument(Document);
        if (Document.GetIsShown <> 0 ) then
            Document.DoFileLoad;
    end;
end;

{ eof }

