{..............................................................................

 Iterate and find Selected Objects for all footprints within the current
 library.

 Use FindSimilarObjects filter UI to preselect objects.

 Created by: Colby Siemer
 Modified by: BL Miller

 24/07/2020  v1.1  fix one object not deleting (the actual user picked obj)
 25/07/2020  v1.2  set focused doc / current view as "dirty" as required.
 26/07/2020  v1.3  Using temp FP list finally solves problem.  Use create TempComp in middle.
 15/08/2020  v1.4  Take temp FP ObjectList soln from 02.pas (26/07/2020)

Creating a temporary component is required.
Selecting it with CurrentLib.SetState_CurrentComponent(TempPcbLibComp) clears all selections.

..............................................................................}
const
    MaxObjects = 10000;
    FP = '___TemporaryComponent__DeleteMeWhenDone___';   // name for temp FP comp.

function SetDocumentDirty (Dummy : Boolean) : IServerDocument;
Var
    AView           : IServerDocumentView;
//    AServerDocument : IServerDocument;
Begin
    Result := nil;
    If Client = Nil Then Exit;
    AView := Client.GetCurrentView;
    Result := AView.OwnerDocument;
    Result.Modified := True;
End;

Procedure DeleteSelectedItemsFromFootprints;
Var
    CurrentLib        : IPCB_Library;
    TempPCBLibComp    : IPCB_LibComponent;

    FootprintIterator : IPCB_LibraryIterator;
    GIterator         : IPCB_GroupIterator;

    Footprint         : IPCB_LibComponent;
    Text              : IPCB_Text;
    CompList          : TObjectList;
    DeleteList        : TObjectList;
    ThisFPList        : TObjectList;
    I, J, K, L        : Integer;
    MyPrim            : IPCB_Primitive;
    TempPrim          : IPCB_Primitive;
    HowMany           : String;
    HowManyInt        : Integer;
    intDialog         : Integer;
    Remove            : boolean;
    SelCountTot       : integer;
    SelObjSet         : TSet;

Begin
     HowManyInt := 0;
     CurrentLib := PCBServer.GetCurrentPCBLibrary;
     If CurrentLib = Nil Then
     Begin
         ShowMessage('This is not a PcbLib document');
         Exit;
     End;

// Verify user wants to continue, if cancel pressed, exit script.  If OK, continue
     intDialog := MessageDlg('!!! Operation can NOT be undone, proceed with caution !!! ', mtWarning, mbOKCancel, 0);
     if intDialog = mrCancel then
     begin
         ShowMessage('Cancel pressed. Exiting ');
         Exit;
     end;

    CompList   := TObjectList.Create;
    DeleteList := TObjectList.Create;
    SelCountTot := 0;

// make set of selected object types for filter..
    SelObjSet := MkSet();
    SelCountTot := CurrentLib.Board.SelectedObjectsCount;

{  alt code..
    for I := 0 to (CurrentLib.Board.SelectedObjectsCount - 1) do
    begin
         MyPrim := CurrentLib.Board.SelectecObject(I);
         if not InSet(MyPrim.ObjectId, SelObjSet) then SelObjSet := SetUnion(SelObjSet, MkSet(MyPrim.ObjectId));
         DeleteList.Add(MyPrim);
         if DeleteList.Count > MaxObjects then break;
    end;
}

    for L := 0 to (CurrentLib.ComponentCount - 1) do
    begin
        Footprint := CurrentLib.GetComponent(L);

        for K := FirstObjectId to LastObjectId do
        begin
            for  J := 1 to Footprint.GetPrimitiveCount(MkSet(K)) do       // require Set; ones based
            begin
                MyPrim := Footprint.GetPrimitiveAt(J, K);                 // requires int.
                if MyPrim.Selected then
                begin
                    DeleteList.Add(MyPrim);
                    if not InSet(MyPrim.ObjectId, SelObjSet) then SelObjSet := SetUnion(SelObjSet, MkSet(MyPrim.ObjectId));
                end;

                if DeleteList.Count >= MaxObjects then break;
            end;  // for J

            if DeleteList.Count >= MaxObjects then break;
        end;      // for K  objects

        if DeleteList.Count >= MaxObjects then break;
    end;          // for L  components


// these are cleared again by focusing the temp component..
    CurrentLib.Board.SelectedObjects_BeginUpdate;
    CurrentLib.Board.SelectedObjects_Clear;
    CurrentLib.Board.SelectedObjects_EndUpdate;

// Create a temporary component to hold focus while we delete items
    PCBServer.PreProcess;
    TempPCBLibComp := PCBServer.CreatePCBLibComp;
    TempPcbLibComp.Name := FP;
    CurrentLib.RegisterComponent(TempPCBLibComp);
    PCBServer.SendMessageToRobots(Nil,c_Broadcast,PCBM_BoardRegisteration,TempPCBLibComp.I_ObjectAddress);
    PCBServer.PostProcess;
// focus the temp footprint
    CurrentLib.SetState_CurrentComponent(TempPcbLibComp);
//    CurrentLib.CurrentComponent := TempPcbLibComp;
    CurrentLib.Board.ViewManager_FullUpdate;   // update all panels assoc. with PCB
    CurrentLib.RefreshView;

// need to refresh some cache ??

    GetWorkSpace.DM_FocusedDocument.DM_Compile;

    for L := 0 to (CurrentLib.ComponentCount - 1) do
    begin
        Footprint := CurrentLib.GetComponent(L);
//        Footprint.SetState_PrimitiveLock(false);
        ThisFPList := TObjectList.Create;

        for K := FirstObjectId to LastObjectId do
        begin
            if Inset(K, SelObjSet) then
            begin                         // NOT ObjectSet
                J := 1;
                while (J <= Footprint.GetPrimitiveCount(MkSet(K)) ) do
                begin
                    TempPrim := Footprint.GetPrimitiveAt(J, K);

 //  Process list and make this footprint only list; remove items from global list
                    for I := 0 to (DeleteList.Count - 1) do
                    begin
                        MyPrim := DeleteList.Items(I);
                        if (MyPrim.I_ObjectAddress = TempPrim.I_ObjectAddress) then
                        begin
//           Showmessage(IntToStr(MyPrim.I_ObjectAddress) + '  ' + IntToStr(TempPrim.I_ObjectAddress) );
                            ThisFPList.Add(MyPrim);
                            DeleteList.Remove(I);   // does this dec obj refcount?
                            break;
                        end;
                    end;
                    inc(J);
                end;
            end;  // if InSet()
        end;      // K  objects

        PCBServer.PreProcess;
        I := 0;
        while (I < ThisFPList.Count)  do
        begin
            MyPrim := ThisFPList.Items(I);
//            Footprint.SetState_PrimitiveLock(false);
            Footprint.RemovePCBObject(MyPrim);
//            CurrentLib.Board.RemovePCBObject(MyPrim);
            PCBServer.SendMessageToRobots(CurrentLib.Board.I_ObjectAddress, c_BroadCast,
                                                      PCBM_BoardRegisteration, MyPrim.I_ObjectAddress);
            inc(HowmanyInt);
            inc(I);
        end;
        PCBServer.PostProcess;
        ThisFPList.Destroy;

        Footprint.GraphicallyInvalidate;
    end;          // L      components

    CurrentLib.Board.GraphicallyInvalidate;

//  Delete Temporary Footprint
    CurrentLib.RemoveComponent(TempPcbLibComp);

    CurrentLib.Navigate_FirstComponent;
    CurrentLib.Board.ViewManager_FullUpdate;
    CurrentLib.Board.GraphicalView_ZoomRedraw;
    CurrentLib.RefreshView;

    if HowManyInt > 0 then CurrentLib.Board.SetState_DocumentHasChanged; // SetDocumentDirty(true);

    HowMany := IntToStr(HowManyInt);
    if HowManyInt = 0 then HowMany := '-NO-';
    ShowMessage('Deleted ' + HowMany + ' Items ' + IntToStr(SelCountTot) );
//    ShowMessage('Deleted ' + HowMany + ' Items ' + '  List ' + IntToStr(DeleteList.Count) + '  SelCount' + IntToStr(SelCountTot) );
    DeleteList.Destroy;
End;
{..............................................................................}

