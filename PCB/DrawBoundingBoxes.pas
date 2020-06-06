{  DrawBoundingBoxes.pas

   With pre-selected component in PcbDoc or focused LibComponent "board", the script will:
   - draw 4 or 5 bounding boxes

   Can select boxlines by Union in PcbDoc.


BLM
05/06/2020  v0.10 POC
06/06/2020  v0.11 Added text labels & layer enable stuff & support for PcbLib.

Button RunScriptText
Text=Var B,P,U;Begin    end;
}

Const
    iMechLayer = 2;       // Mechanical Layer 2 == 2

function DrawBox(Board : IPCB_Board, BR : TCoordRect, UIndex : integer, const Tag : WideString) : boolean;
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
end;

procedure DrawBBoxes;
var
    Board   : IPCB_Board;
    PcbLib  : IPCB_Library;
    ML      : TLayer;
    MLayer  : IPCB_MechanicalLayer;
    Prim    : IPCB_Primitive;
    UIndex  : integer;
    S       : TStringList;
    BRect   : TCoordRect;
    IsLib   : boolean;

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

    ML := LayerUtils.MechanicalLayer(iMechLayer);
    MLayer := Board.LayerStack_V7.LayerObject_V7[ML];
    MLayer.MechanicalLayerEnabled := true;
    Board.ViewManager_UpdateLayerTabs;

    UIndex := GetHashID_ForString(GetWorkSpace.DM_GenerateUniqueID);

// PcbLib component is a group of free primitives on a board.
    if not IsLib then
        if Prim.ObjectId <> eComponentObject then exit;

// Bounding Rectangles
// PcbDoc: 3 of these are same; NoNameComment Painting Selection
// PcbLib: 2 are exactly same
// PcbLib: 2 are almost the same
    BRect := Prim.BoundingRectangle;
    DrawBox(Board, BRect, UIndex, 'BRect');
    if not IsLib then
    begin
//        BRect := RectToCoordRect(Prim.BoundingRectangleNoNameComment);
        BRect := Prim.BoundingRectangleNoNameComment;
        DrawBox(Board, BRect, UIndex, 'NNC');
    end;
    BRect := Prim.BoundingRectangleChildren;
    DrawBox(Board, BRect, UIndex, 'Childn');
    BRect := Prim.BoundingRectangleForPainting;
    DrawBox(Board, BRect, UIndex, 'Paintg');
    BRect := Prim.BoundingRectangleForSelection;
    DrawBox(Board, BRect, UIndex, 'Selectn');

//    Board.CurrentLayer(ML);
    Client.SendMessage('PCB:SetCurrentLayer', 'Layer=' + IntToStr(ML) , 255, Client.CurrentView);
    Board.ViewManager_FullUpdate;
end;


