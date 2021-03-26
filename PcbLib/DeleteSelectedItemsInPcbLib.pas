{..............................................................................
 DeleteSelectedItemsInPcbLibParts.pas

 Deletes all selected primitives in PcbLib.
 Iterate and find Selected Objects for all footprints within the current library.

 Use FSO FindSimilarObjects filter UI to preselect objects.

 Created by: Colby Siemer
 Modified by: BL Miller

 24/07/2020  v1.1  fix one object not deleting (the actual user picked obj)
 25/07/2020  v1.2  set focused doc / current view as "dirty" as required.
 26/07/2020  v1.3  Using temp FP list finally solves problem.  Use create TempComp in middle.
 15/08/2020  v1.4  Take temp FP ObjectList soln from 02.pas (26/07/2020)
 07/01/2021  v1.5  Try again with TInterfaceList & rearranged Delete() outside of GroupIterator
 08/01/22021 v1.6  Added StatusBar percentage delete progress & Cursor busy.

Can NOT delete primitives that are referenced inside an iterator as this messes up "indexing".
Must re-create the iterator after any object deletion.
Use of TInterfaceList (for external dll calls etc) may not be required.

Creating a temporary component is required.
Selecting Comp with CurrentLib.SetState_CurrentComponent(TempPcbLibComp) clears all selections.
..............................................................................}

const
    MaxObjects = 1000;
    FP = '___TemporaryComponent__DeleteMeWhenDone___';   // name for temp FP comp.

Procedure DeleteSelectedItemsFromFootprints;
Var
    GUIMan            : IGUIManager;
    CurrentLib        : IPCB_Library;
    TempPCBLibComp    : IPCB_LibComponent;

    FIterator         : IPCB_LibraryIterator;
    GIterator         : IPCB_GroupIterator;
    Footprint         : IPCB_LibComponent;

    FPList            : TObjectList;
    DeleteList        : TInterfaceList;
    I, J              : Integer;
    MyPrim            : IPCB_Primitive;

    HowMany           : String;
    HowManyInt        : Integer;
    SelCountTot       : integer;
    intDialog         : Integer;
    Remove            : boolean;
    First             : boolean;                // control (limit) LibCompList to ONE instance.
    sStatusBar        : WideString;
    iStatusBar        : integer;

Begin
     GUIMan := Client.GUIManager;

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

    DeleteList  := TInterfaceList.Create;
    FPList      := TObjectList.Create;            // hold a list of affected LibComponents.

    SelCountTot := 0;
    HowManyInt  := 0;

    FIterator := CurrentLib.LibraryIterator_Create;
    FIterator.SetState_FilterAll;

    Footprint := FIterator.FirstPCBObject;
    while Footprint <> Nil Do
    begin //Iterate through each footprint finding Selected objects and building a list
        First := true;
        GIterator := Footprint.GroupIterator_Create;

//  Use a line such as the following if you would like to limit the type of items you are allowed to delete, in the example line below,
//  this would limit the script to Component Body Objects
//       GIterator.Addfilter_ObjectSet(MkSet(eComponentBodyObject));

        MyPrim := GIterator.FirstPCBObject;
        while MyPrim <> Nil Do
        begin
            if MyPrim.Selected = true then
            begin
                if (First) then FPList.Add(Footprint);
                First := false;
                DeleteList.Add(MyPrim);
                inc(SelCountTot);
            end;
            MyPrim := GIterator.NextPCBObject;
        end;
        Footprint.GroupIterator_Destroy(GIterator);

        if DeleteList.Count >= MaxObjects then break;
        Footprint := FIterator.NextPCBObject;

    end;
    CurrentLib.LibraryIterator_Destroy(FIterator);


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
    CurrentLib.Board.ViewManager_FullUpdate;          // update all panels assoc. with PCB
    CurrentLib.RefreshView;

    BeginHourGlass(crHourGlass);
    PCBServer.PreProcess;

    FIterator := CurrentLib.LibraryIterator_Create;
    FIterator.SetState_FilterAll;

    Footprint := FIterator.FirstPCBObject;
    while Footprint <> Nil Do
    begin
        iStatusBar := Int(HowManyInt / SelCountToT * 100);
        sStatusBar := ' Deleting : ' + IntToStr(iStatusBar) + '% done';
        GUIMan.StatusBar_SetState (1, sStatusBar);

        for J := 0 to (FPList.Count - 1) do
        begin
            if (Footprint.Name = FPList.Items(J).Name) then
            begin
                I := 0;
                while (I < DeleteList.Count) Do
                begin
                    Remove := false;

// can NOT delete Prim without re-creating the Group Iterator.
                    GIterator := Footprint.GroupIterator_Create;
                    MyPrim := GIterator.FirstPCBObject;
                    while MyPrim <> Nil Do
                    begin
                        if MyPrim.I_ObjectAddress = DeleteList.Items(I).I_ObjectAddress then
                        begin
                            Remove := true;
                            break;
                        end;
                        MyPrim := GIterator.NextPCBObject;
                    end;
                    Footprint.GroupIterator_Destroy(GIterator);

                    if (Remove) then
                    begin
                         Footprint.RemovePCBObject(DeleteList.Items(I));
                         DeleteList.Delete(I);                              // speed up
                         inc(HowManyInt);
                    end
                    else
                        inc(I);                                             // do not inc() when removing elements!

                end; // while I

            end;
        end;   // next J

        Footprint := FIterator.NextPCBObject;
    end;

    CurrentLib.LibraryIterator_Destroy(FIterator);

    DeleteList.Clear;
    FPList.Destroy;
    DeleteList.Free;

    PCBServer.PostProcess;

    CurrentLib.Board.GraphicallyInvalidate;

//  Delete Temporary Footprint
    CurrentLib.RemoveComponent(TempPcbLibComp);

    CurrentLib.Navigate_FirstComponent;
    CurrentLib.Board.ViewManager_FullUpdate;
    CurrentLib.Board.GraphicalView_ZoomRedraw;
    CurrentLib.RefreshView;
    EndHourGlass;

    if HowManyInt > 0 then CurrentLib.Board.SetState_DocumentHasChanged;

    HowMany := IntToStr(HowManyInt);
    if HowManyInt = 0 then HowMany := '-NO-';
    ShowMessage('Deleted ' + HowMany + ' Items | selected count : ' + IntToStr(SelCountTot) );
//    ShowMessage('Deleted ' + HowMany + ' Items ' + '  List ' + IntToStr(DeleteList.Count) + '  SelCount' + IntToStr(SelCountTot) );

End;
{..............................................................................}

