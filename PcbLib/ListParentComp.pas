{ ListParentComp.pas
  PcbLib

  Select any number ComponentBody(s) (with filter or PCBList etc)
  Run Script & review Messages Manager Panel
  Can navigate by clicking MMP message.

  currently supports ComponentBody, Pad, Track Arc, Text & Regions.

BL Miller
12/02/2021  v0.10  POC view parent comp (FP) in Editor panel.
13/02/2021  v0.11  List selected CompBody in MessagesManagerPanel.
14/02/2021  v0.12  Add checksum value to MMP as is unique & in PCBList.
14/02/2021  v0.13  obvious performance eff gain with iterator filter.
15/02/2021  v0.14  use list to cache selections so can try use MMP zoom, put filter in the right iterator!

tbd:
Fix checksum Hex for non-generic models..
AddMessage2() to set primitive zoomed. Still not working.
}

const
   IMG_Component  = 2;

function ModelTypeToStr (ModType : T3DModelType) : WideString;   forward;
function RegionKindToStr (RK: TPolyRegionKind);                  forward;

procedure FindParent;
var
    WS           : IWorkSpace;
    BUnits       : TUnit;
    BOrigin      : TCoordPoint;
    MM           : IDXPMessagesManager;
    MMess        : WideString;
    MID          : IDXPMessageItemDetails;
    CurrentLib   : IPCB_Library;
    FIterator    : IPCB_LibraryIterator;
    GIterator    : IPCB_GroupIterator;
    Footprint    : IPCB_LibComponent;
    CompBody     : IPCB_ComponentBody;
    CompModel    : IPCB_Model;
    PrimList      : TObjectList;
    CompModelId  : WideString;
    ModType      : T3DModelType;
    ModTypeStr   : WideString;
    ModelCksum   : Cardinal;  // string;
    MSNibble     : Integer;                      // can't convert 64 bit unsigned to hex!
    HexString    : WideString;
    Prim, Prim2  : IPCB_Primitive;
    BR           : TCoordRect;
    found        : boolean;
    I            : integer;

begin
    CurrentLib := PCBServer.GetCurrentPCBLibrary;
    If CurrentLib = Nil Then
    Begin
        ShowMessage('This is not a PcbLib document');
        Exit;
    End;

    BUnits := CurrentLib.Board.DisplayUnit;
    PrimList := TObjectList.Create;

// cache selected objs as FP select for origin & bounding rect will destroy state.
    for I := 0 to (CurrentLib.Board.SelectedObjectsCount - 1) do
    begin
        Prim := CurrentLib.Board.SelectecObject(I);
        PrimList.Add(Prim);
    end;

    for I := 0 to (PrimList.Count - 1) do
    begin
        Prim := PrimList.Items(I);

        found := false;

        FIterator := CurrentLib.LibraryIterator_Create;
        FIterator.AddFilter_ObjectSet(MkSet(eComponentObject));
        FIterator.SetState_FilterAll;
        Footprint := FIterator.FirstPCBObject;

        while (not found) and (Footprint <> Nil) Do
        begin
            GIterator := Footprint.GroupIterator_Create;
            GIterator.AddFilter_ObjectSet(MkSet(Prim.ObjectId));

            Prim2 := GIterator.FirstPCBObject;
            while (not found ) and (Prim2 <> Nil) Do
            begin
                if (Prim.I_ObjectAddress = Prim2.I_ObjectAddress) then
                begin
                   found := true;
                end;
                Prim2 := GIterator.NextPCBObject;
            end;
            Footprint.GroupIterator_Destroy(GIterator);

            if found then break;    // preserve the found Footprint object reference..
            Footprint := FIterator.NextPCBObject;
        end;
        CurrentLib.LibraryIterator_Destroy(FIterator);

        if found then
        begin
            MMess := 'Footprint : ' + Chr(34) + Footprint.Name + Chr(34);
            HexString := '';

            case Prim.ObjectId of
              eTextObject :
                MMess := MMess + ' | Text on Layer : ' + Layer2String(Prim.Layer) + ' | Text : ' + Prim.Text;
              ePadObject :
                MMess := MMess + ' | Pad on Layer : ' + Layer2String(Prim.Layer) + ' | Pin : ' + Prim.Name;
              eArcObject, ETrackObject :
                MMess := MMess + ' | Track or Arc on Layer : ' + Layer2String(Prim.Layer);
              eRegionObject :
                MMess := MMess + ' | Region on Layer : ' + Layer2String(Prim.Layer) + ' | Kind : ' + RegionKindToStr(Prim.Kind);
              eComponentBodyObject :
              begin
                CompBody := Prim;
                //CBodyName := CompBody.Name;
                CompModel   := CompBody.Model;
                CompModelId := CompBody.Identifier;
                ModTypeStr := 'no model';
                if CompModel <> nil then
                begin
                    Compbody.Area;
                    ModType := CompModel.ModelType;
                    ModelCksum := CompModel.Checksum;

                    if (ModelCkSum < 0) then
                    begin
//  IntToHex can not handle uint32 or int64 ; make unsigned & decode MS nibble.
                        ModelCkSum := ModelCksum + Power(2,32);
// who knows what silly Altium nonsense is at play here
                        if (ModType <> e3DModelType_Generic) then
                           ModelCkSum := ModelCksum + 171231973;
                        //    ModelCksum := -CompModel.Checksum;
                        //    ModelCkSum := ModelCksum + 171231973;
                    end;
                    MSNibble  := Int(ModelCkSum / Power(2,28));
                    HexString := IntToHex( MSNibble, 1);
                    ModelCkSum := ModelCksum - (MSNibble * Power(2,28) );
                    HexString := HexString + IntToHex( ModelCkSum, 7);

                    if (ModType <> e3DModelType_Generic) then HexString := 'tbd';

                    ModTypeStr := ModelTypeToStr(ModType);
                end;
                MMess := MMess + ' | Identifier : ' + CompModelId + ' | Checksum : ' + HexString + ' |  ' + ModTypeStr;
              end;
            end;  // case

// this focuses FP in editor but unselects all objects !!
            CurrentLib.SetState_CurrentComponent(Footprint);    //must use else Origin & BR all wrong.
            BOrigin := Point(CurrentLib.Board.XOrigin, CurrentLib.Board.YOrigin);
            BR := Prim.BoundingRectangle;

            MID := nil;
            WS := GetWorkSpace;
            MM := WS.DM_MessagesManager;
//            MM.ClearMessages;
            MM.BeginUpdate;
                                                                  // LibDoc.DM_FullPath or WS.DM_FocusedDocument.DM_FileName
//            MM.AddMessage ('[Info]', MMess , 'FindParent.pas', ExtractFileName(CurrentLib.Board.FileName), 'PCB:GotoLibraryComponent', 'FileName=' + CurrentLib.Board.FileName + '|Footprint=' + Footprint.Name, IMG_Component, false);
            MM.AddMessage2('[Info]', MMess , 'FindParentComp.pas', ExtractFileName(CurrentLib.Board.FileName), 'PCB:GotoLibraryComponent', 'FileName=' + CurrentLib.Board.FileName + '|Footprint=' + Footprint.Name, IMG_Component, false,
                           'PCB:Zoom', 'Action=Area | Location1.X=' + CoordUnitToString(BR.X1-BOrigin.X, BUnits) + ' | Location1.Y=' + CoordUnitToString(BR.Y1-BOrigin.Y, BUnits) +
                                                  ' | Location2.X=' + CoordUnitToString(BR.X2-BOrigin.X, BUnits) + ' | Location2.Y=' + CoordUnitToString(BR.Y2-BOrigin.Y, BUnits), MID );
            MM.EndUpdate;
            WS.DM_ShowMessageView;
            MM := nil;
        end;
    end; // for selectedobj..
end;
{--------------------------------------------------------------------------------------------------------------------------}
function RegionKindToStr (RK: TPolyRegionKind);
begin
    Case RK of
      eRegionKind_Copper      : Result := 'copper';
      eRegionKind_Cutout      : Result := 'cutout';
      eRegionKind_NamedRegion : Result := 'named';
      eRegionKind_BoardCutout : Result := 'board cutout';
      eRegionKind_Cavity      : Result := 'cavity';
    else
        Result := 'unknown';
    end;
end;
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
