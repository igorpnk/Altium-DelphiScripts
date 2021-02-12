{ ListParentComp.pas
  PcbLib

  Select any number ComponentBody(s) (with filter or PCBList etc)
  Run Script & review Messages Panel
  Can navigate by clicking MM messgae.

  currently only supports ComponentBody
BL Miller
12/02/2021  v0.10  POC view parent comp (FP) in Editor panel.
13/02/2021  v0.11  Lst selected CompBody in MessagesPanel.
}

const
   IMG_Component  = 2;

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

        while Footprint <> Nil Do
        begin
            GIterator := Footprint.GroupIterator_Create;
            Prim2 := GIterator.FirstPCBObject;
            while Prim2 <> Nil Do
            begin
                if Prim2.I_ObjectAddress = Prim.I_ObjectAddress then
                begin
                   found := true;
                   break;
                end;

                Prim2 := GIterator.NextPCBObject;
            end;
            Footprint.GroupIterator_Destroy(GIterator);
            Footprint := FIterator.NextPCBObject;
            if found then break;
        end;
        CurrentLib.LibraryIterator_Destroy(FIterator);

        if found then
        begin
            if Prim.ObjectId = eComponentBodyObject then
            begin
                CompBody := Prim;
                //CBodyName := CompBody.Name;
                CompModel   := CompBody.Model;
                CompModelId := CompBody.Identifier;
                if CompModel <> nil then
                    ModType     := CompModel.ModelType;
            end;

{  // this focuses FP in editor
            CurrentLib.SetState_CurrentComponent(Footprint);
//            CurrentLib.CurrentComponent := TempPcbLibComp;
            CurrentLib.Board.ViewManager_FullUpdate;          // update all panels assoc. with PCB
            CurrentLib.RefreshView;
}
            WS := GetWorkSpace;
            MM := WS.DM_MessagesManager;

            MMess := 'Footprint Name : ' + Chr(34) + Footprint.Name + Chr(34) + ' | BodyId : ' + CompModelId;
            MM.BeginUpdate;                                   // LibDoc.DM_FullPath
            MM.AddMessage('[Info]', MMess , 'FindParent.pas', WS.DM_FocusedDocument.DM_FileName, 'PCB:GotoLibraryComponent', 'FileName=' + WS.DM_FocusedDocument.DM_FileName + '|Footprint=' + Footprint.Name, IMG_Component, false);
            MM.EndUpdate;
            WS.DM_ShowMessageView;
            MM := nil;
        end;
    end; // for selectedobj..
end;
