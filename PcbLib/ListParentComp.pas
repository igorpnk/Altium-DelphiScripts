{ ListParentComp.pas
  PcbLib

  Select any number ComponentBody(s) (with filter or PCBList etc)
  Run Script & review Messages Manager Panel
  Can navigate by clicking MMP message.

  currently only supports ComponentBody, Pad, Track Arc & Regions.

BL Miller
12/02/2021  v0.10  POC view parent comp (FP) in Editor panel.
13/02/2021  v0.11  List selected CompBody in MessagesManagerPanel.
14/02/2021  v0.12  Add checksum value to MMP as is unique & in PCBList.

tbd:
Fix checksum Hex for non-generic models..
AddMessage2() to set primitive focused.
}

const
   IMG_Component  = 2;

function ModelTypeToStr (ModType : T3DModelType) : WideString;   forward;
function RegionKindToStr (RK: TPolyRegionKind);                  forward;

procedure FindParent;
var
    WS           : IWorkSpace;
    MM           : IDXPMessagesManager;
    MMess        : WideString;
    CurrentLib   : IPCB_Library;
    FIterator    : IPCB_LibraryIterator;
    GIterator    : IPCB_GroupIterator;
    Footprint    : IPCB_LibComponent;
    CompBody     : IPCB_ComponentBody;
    CompModel    : IPCB_Model;
    CompModelId  : WideString;
    ModType      : T3DModelType;
    ModTypeStr   : WideString;
    ModelCksum   : Cardinal;  // string;
    MSNibble     : Integer;                      // can't convert 64 bit unsigned to hex!
    HexString    : WideString;
    Prim, Prim2  : IPCB_Primitive;
    found        : boolean;
    I            : integer;

begin
    CurrentLib := PCBServer.GetCurrentPCBLibrary;
    If CurrentLib = Nil Then
    Begin
        ShowMessage('This is not a PcbLib document');
        Exit;
    End;

    for I := 0 to (CurrentLib.Board.SelectedObjectsCount - 1) do
    begin
        found := false;

        Prim := CurrentLib.Board.SelectecObject(I);
        Prim.InComponent;    // always false in PcbLib

        FIterator := CurrentLib.LibraryIterator_Create;
        FIterator.SetState_FilterAll;
        Footprint := FIterator.FirstPCBObject;

        while (not found) and (Footprint <> Nil) Do
        begin
            GIterator := Footprint.GroupIterator_Create;
            Prim2 := GIterator.FirstPCBObject;
            while (not found ) and (Prim2 <> Nil) Do
            begin
                if (Prim2.ObjectID = Prim.ObjectId) then
                if Prim2.I_ObjectAddress = Prim.I_ObjectAddress then
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
            MMess := 'Footprint Name : ' + Chr(34) + Footprint.Name + Chr(34);
            HexString := '';

            case Prim.ObjectId of
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
//  IntToHex can not handle uint32 or int64
                        ModelCkSum := ModelCksum + Power(2,32);
                        if (ModType <> e3DModelType_Generic) then
                        //    ModelCksum := -CompModel.Checksum;
                        //    ModelCkSum := ModelCksum + 171231973;
                             ModelCkSum := ModelCksum + 171231973;
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

{  // this focuses FP in editor
            CurrentLib.SetState_CurrentComponent(Footprint);
//            CurrentLib.CurrentComponent := TempPcbLibComp;
            CurrentLib.Board.ViewManager_FullUpdate;          // update all panels assoc. with PCB
            CurrentLib.RefreshView;
}
            WS := GetWorkSpace;
            MM := WS.DM_MessagesManager;
            MM.BeginUpdate;                                   // LibDoc.DM_FullPath
            MM.AddMessage ('[Info]', MMess , 'FindParent.pas', WS.DM_FocusedDocument.DM_FileName, 'PCB:GotoLibraryComponent', 'FileName=' + WS.DM_FocusedDocument.DM_FileName + '|Footprint=' + Footprint.Name, IMG_Component, false);
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
