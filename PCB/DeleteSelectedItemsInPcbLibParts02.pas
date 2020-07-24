{..............................................................................

 Iterate and find Selected Objects for all footprints within the current
 library.

 Use FindSimilarObjects filter UI to preselect objects.

 Created by: Colby Siemer
 Modified by: BL Miller

 24/07/2020  v1.1  fix one object not deleting (the actual user picked obj)


..............................................................................}
const
    FP = '___TemporaryComponent__DeleteMeWhenDone___';   // name for temp FP comp.

Procedure DeleteSelectedItemsFromAllFootprints;
Var
    CurrentLib        : IPCB_Library;
    TempPCBLibComp    : IPCB_LibComponent;

    FootprintIterator : IPCB_LibraryIterator;
    GIterator         : IPCB_GroupIterator;

    Footprint         : IPCB_LibComponent;
    Text              : IPCB_Text;
    DeleteList        : TObjectList;
    I                 : Integer;
    MyPrim            : IPCB_Primitive;
    TempPrim          : IPCB_Primitive;
    HowMany           : String;
    HowManyInt        : Integer;
    ButtonSelected    : Integer;
    Remove            : boolean;

Begin
     HowManyInt := 0;
     CurrentLib := PCBServer.GetCurrentPCBLibrary;
     If CurrentLib = Nil Then
     Begin
         ShowMessage('This is not a PcbLib document');
         Exit;
     End;

// Verify user wants to continue, if cancel pressed, exit script.  If OK, continue
     buttonSelected := MessageDlg('!!! Operation CAN NOT be undone, proceed with caution !!! ', mtwarning, mbOKCancel, 0);
     if buttonSelected = mrCancel then
     begin
         ShowMessage('Cancel pressed. Exiting ');
         Exit;
     end;

// Create a temporary component to hold focus while we delete items
    TempPCBLibComp := PCBServer.CreatePCBLibComp;
    TempPcbLibComp.Name := FP;
    CurrentLib.RegisterComponent(TempPCBLibComp);

    CurrentLib.Board.ViewManager_FullUpdate;

    DeleteList := TObjectList.Create;

//  Each page of library is a Lib FootPrint: a board with group of primitives.
//  A Footprint is a IPCB_LibComponent inherited from IPCB_Group,
//  which is a container object that stores primitives.
//  Iterate through each footprint & FP group finding Selected objects and build a list
    FootprintIterator := CurrentLib.LibraryIterator_Create;
    FootprintIterator.SetState_FilterAll;
    FootprintIterator.AddFilter_IPCB_LayerSet(LayerSetUtils.AllLayers);

    Try
        Footprint := FootprintIterator.FirstPCBObject;
        while Footprint <> Nil Do
        begin
            CurrentLib.Board.SelectecObjectCount;
            currentLib.Board.SelectedObjectsCount;
            Footprint.Name;

            GIterator := Footprint.GroupIterator_Create;
          // example filter below can limit the type of items that are allowed to be deleted,
          // this would limit the script to Component Body objects
          // Iterator.Addfilter_ObjectSet(MkSet(eComponentBodyObject));
            MyPrim := GIterator.FirstPCBObject;
            while MyPrim <> Nil Do
            begin
                if MyPrim.Selected = true then
                begin
                    DeleteList.Add(MyPrim);
                    CurrentLib.Board.SelectedObjects_BeginUpdate;
                    MyPrim.Selected := false;
                    CurrentLib.Board.SelectedObjects_EndUpdate;
                end;
                MyPrim := GIterator.NextPCBObject;
            end;
            Footprint.GroupIterator_Destroy(GIterator);
            Footprint := FootprintIterator.NextPCBObject;
        End;

    Finally
        CurrentLib.LibraryIterator_Destroy(FootprintIterator);
    End;

// focus the temp footprint
        CurrentLib.SetState_CurrentComponent(TempPcbLibComp);
        CurrentLib.Board.ViewManager_FullUpdate;
        CurrentLib.RefreshView;

    Try
        FootprintIterator := CurrentLib.LibraryIterator_Create;
        FootprintIterator.SetState_FilterAll;
        FootprintIterator.AddFilter_IPCB_LayerSet(LayerSetUtils.AllLayers);
        Footprint := FootprintIterator.FirstPCBObject;

        while Footprint <> Nil Do
        begin
            GIterator := Footprint.GroupIterator_Create;
            TempPrim := GIterator.FirstPCBObject;
            while TempPrim <> Nil Do
            begin
//  Process list and delete items from created list
                for I := 0 to (DeleteList.Count - 1) do
                begin
                    Remove := false;
                    MyPrim := DeleteList.Items(I);
                    if (MyPrim.I_ObjectAddress = TempPrim.I_ObjectAddress) then
                    begin
                        Remove := true;
                        break;
                    end;
                end;

                TempPrim := GIterator.NextPCBObject;

                if (MyPrim <> nil) and (Remove) then
                begin
                    PCBServer.PreProcess;
                    Footprint.RemovePCBObject(MyPrim);
                    CurrentLib.Board.RemovePCBObject(MyPrim);
                    PCBServer.PostProcess;
                    inc(HowmanyInt);
                end;
            end;
            Footprint.GroupIterator_Destroy(GIterator);

            Footprint.GraphicallyInvalidate;
            CurrentLib.Board.GraphicallyInvalidate;
            Footprint := FootprintIterator.NextPCBObject;
        end;

    Finally
        CurrentLib.LibraryIterator_Destroy(FootprintIterator);
    End;

    DeleteList.Destroy;

//  Delete Temporary Footprint
    CurrentLib.RemoveComponent(TempPcbLibComp);

    CurrentLib.Navigate_FirstComponent;
    CurrentLib.Board.ViewManager_FullUpdate;
    CurrentLib.Board.GraphicalView_ZoomRedraw;
    CurrentLib.RefreshView;

    HowMany := IntToStr(HowManyInt);
    ShowMessage('Deleted ' + HowMany + ' Items');
End;
{..............................................................................}

