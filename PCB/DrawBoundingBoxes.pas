{  DrawBoundingBoxes.pas

   With pre-selected component or primitive in PcbDoc or focused LibComponent "board", the script will:
   - draw 4 or 5 bounding boxes

   Can select boxlines by Union in PcbDoc.


BLM
05/06/2020  v0.10 POC
06/06/2020  v0.11 Added text labels & layer enable stuff & support for PcbLib.
19/09/2020  v0.12 Add report with dimensions. Make the output mech layer visible
21/09/2020  v0.13 Add (x,y) of the primitive.

Button RunScriptText
Text=Var B,P,U;Begin    end;
}

Const
    cShowReport = true;
    iMechLayer  = 2;       // Mechanical Layer 2 == 2

var
    Board     : IPCB_Board;
    BUnits    : TUnit;
    BOrigin   : TPoint;
    Document  : IServerDocument;
    Filename  : WideString;
    Report    : TStringList;


function DrawBox(BR : TCoordRect, UIndex : integer, const Tag : WideString) : boolean;
var
    Track    : IPCB_Track;
    Text     : IPCB_Text;
    VP1, VP2 : TPoint;
    I        : integer;

begin
    VP1:= Point(BR.x1, BR.y1);
    for I := 0 to 3 do
    begin
        Case I of
        0 :  VP2 := Point(BR.x2, BR.y1);
        1 :  VP1 := Point(BR.x2, BR.y2);
        2 :  VP2 := Point(BR.x1, BR.y2);
        3 :  VP1 := Point(BR.x1, BR.y1);
        end;

        Track := PCBServer.PCBObjectFactory(eTrackObject, eNoDimension, eCreate_Default);
        Track.Width := MilsToCoord(0.5);
        Track.Layer := LayerUtils.MechanicalLayer(iMechLayer);
        Track.x1 := VP1.x;
        Track.y1 := VP1.y;
        Track.x2 := VP2.x;
        Track.y2 := VP2.y;
        Track.UnionIndex := UIndex;
        Board.AddPCBObject(Track);
    end;
    Text := PCBServer.PCBObjectFactory(eTextObject, eNoDimension, eCreate_Default);
    Text.Text := Tag;
    Text.Size  := MilsToCoord(5);
    Text.Width := MilsToCoord(0.5);
    Text.Layer := LayerUtils.MechanicalLayer(2);
    Text.XLocation  := BR.x2;
    Text.YLocation  := BR.y2 - Text.Size;
    Text.UnionIndex := UIndex;
    Board.AddPCBObject(Text);
    Report.Add(PadRight(Tag, 10) + PadRight(CoordUnitToString(BR.X1-BOrigin.X, BUnits),10) + ' '
                                 + PadRight(CoordUnitToString(BR.Y1-Borigin.Y, BUnits),10) + ' '
                                 + PadRight(CoordUnitToString(BR.X2-BOrigin.X, BUnits),10) + ' '
                                 + PadRight(CoordUnitToString(BR.Y2-BOrigin.Y, BUnits),10) );
end;

procedure DrawBBoxes;
var
    PcbLib    : IPCB_Library;
    ML        : TLayer;
    MLayer    : IPCB_MechanicalLayer;
    Prim      : IPCB_Primitive;
    PCentre   : TPoint;
    sPCentre  : WideString;
    FPName    : WideString;
    FPPattern : WideString;
    UIndex    : integer;
    BRect     : TCoordRect;
    IsLib     : boolean;

begin
    Board  := PCBServer.GetCurrentPCBBoard;
    PcbLib := PCBServer.GetCurrentPCBLibrary;
    IsLib  := false;
    if PcbLib <> nil then IsLib := true;

    if not IsLib then
    begin
        if Board = nil then exit;
        if(Board.SelectecObjectCount = 0) then exit;
        Prim := Board.SelectecObject(0);
    end
    else
    begin
        Board := PcbLib.Board;
        Prim := PcbLib.CurrentComponent;
    end;

// returns TUnits but with swapped meanings AD17 0 == Metric but API has eMetric=1 & eImperial=0
    BUnits := Board.DisplayUnit;
    GetCurrentDocumentUnit;
    if (BUnits = eImperial) then BUnits := eMetric
    else BUnits := eImperial;

    BOrigin := Point(Board.XOrigin, Board.YOrigin);
//    BRBoard := Board.BoardOutline.BoundingRectangle;
//    Height := RectHeight(BRBoard); // + MilsToCoord(200);
//    Width  := RectWidth(BRBoard);

    Report := TStringList.Create;
    Report.Add('Board originX : ' + CoordUnitToString(BOrigin.X, BUnits) + ' originY ' + CoordUnitToString(BOrigin.Y, BUnits));
//    Report.Add('Board width   : ' + CoordUnitToString(Width, BUnits) +     '  height ' + CoordUnitToString(Height, BUnits));
    Report.Add('');

    ML := LayerUtils.MechanicalLayer(iMechLayer);
    MLayer := Board.LayerStack_V7.LayerObject_V7[ML];
    MLayer.MechanicalLayerEnabled := true;
    MLayer.IsDisplayed(Board) := true;
    Board.ViewManager_UpdateLayerTabs;

    UIndex := GetHashID_ForString(GetWorkSpace.DM_GenerateUniqueID);

    FPName := ''; FPPattern := ''; sPCentre := '';
    if IsLib then
    begin
        FPName    := Prim.Name;
        FPPattern := '';
    end else
    begin
        if Prim.ObjectId = eComponentObject then
        begin
            FPName    := Prim.Name.Text;
            FPPattern := ' | '+ Prim.Pattern;
        end;
    end;
    if InSet(Prim.ObjectId, MkSet(eComponentObject, eNetObject, ePadObject, eViaObject, ePolyObject, eCoordinateObject, eDimensionObject) ) then
    begin
        PCentre := Point(Prim.X, Prim.Y);
        sPCentre := ' | Primitive X = ' + PadRight(CoordUnitToString(PCentre.X-BOrigin.X, BUnits),10)
                              + ' Y = ' + PadRight(CoordUnitToString(Pcentre.Y-Borigin.Y, BUnits),10);
    end;

    FPName := Prim.ObjectIdString + ' | ' + FPName + FPPattern + sPCentre;
    Report.Add(FPName);

// Bounding Rectangles
// PcbDoc: 3 of these are same; NoNameComment Painting Selection
// PcbLib: 2 are exactly same
// PcbLib: 2 are almost the same
    BRect := Prim.BoundingRectangle;
    DrawBox(BRect, UIndex, 'BRect');
    if not IsLib then
    if Prim.ObjectId = eComponentObject then
    begin
//        BRect := RectToCoordRect(Prim.BoundingRectangleNoNameComment);
        BRect := Prim.BoundingRectangleNoNameComment;
        DrawBox(BRect, UIndex, 'NNC');
    end;

    BRect := Prim.BoundingRectangleChildren;
    DrawBox(BRect, UIndex, 'Childn');
    BRect := Prim.BoundingRectangleForPainting;
    DrawBox(BRect, UIndex, 'Paintg');
    BRect := Prim.BoundingRectangleForSelection;
    DrawBox(BRect, UIndex, 'Selectn');

//    Board.CurrentLayer(ML);
    Client.SendMessage('PCB:SetCurrentLayer', 'Layer=' + IntToStr(ML) , 255, Client.CurrentView);
    Board.ViewManager_FullUpdate;

    Report.Insert(0, 'Bounding Boxes Information for ' + ExtractFileName(Board.FileName) + ' document.');

    FileName := ChangeFileExt(Board.FileName,'DBB.txt');
    Report.SaveToFile(Filename);
    Report.Free;

    Document  := Client.OpenDocument('Text', FileName);
    If Document <> Nil Then
    begin
        if (cShowReport) then
        begin
            Client.ShowDocument(Document);
            if (Document.GetIsShown <> 0 ) then
               Document.DoFileLoad;
        end;
    end;
end;


