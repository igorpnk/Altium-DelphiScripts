{ SelectBadConnections02.pas   ..............................................
 Summary
    Checks if Tracks and Arcs on signal or mech layers connect completely on some
    other object. Center-to-center check is done.
    If not connected completely, the objects are displayed with all else masked.

    Signal layer objects MUST have an assigned Net
    Mech layer objects are NOT checked against Pads Vias or Multi-Layer.

    The tolerance is set in a form. Zero tolerance is supported.

 Created by:    Petar Perisin
 Modified B.L. Miller
10/06/2020  1.10  Add support Mech Layers up to eMech24.
12/06/2020  1.20  fixed problem with iterator layersets & added layer settings to form.
21/06/2020  1.21  Added Messages Panel notification/navigation
22/06/2020  1.22  Added actual x & y values to messages

Iterator layer filter methods use different parameters:
   .AddFilter_IPCB_LayerSet();  requires IPCB_LayerSet & LayerSetUtils interface to work correctly.
   .AddFilter_LayerSet();       uses TLayerSet, limited to 256 element Delphi/Pascal TSet restriction.

   Can NOT use MkSet, MkRange & SetUnion with IPCB_LayerSet type.

..............................................................................}

{..............................................................................}
const
    cIconOk        = 3;
    IMG_Cross      = 4;
    Marker_Warning = 108;
    BoardProject   = 56;
Var
   Board        : IPCB_Board;
   BOrigin      : TPoint;
   Units        : TUnit;
   MMPanel      : IDXPMessagesManager;
   Tolerance    : TCoord;
   bCopper      : boolean;
   bMech        : boolean;
   bCurrent     : boolean;

function IsStringANum(Tekst : String) : Boolean;
var
   i        : Integer;
   dotCount : Integer;
   ChSet    : TSet;
begin
   Result := True;
   // Test for number, dot or comma
   ChSet := SetUnion(MkSet(Ord('.'),Ord(',')), MkSetRange(Ord('0'), Ord('9')) );
   for i := 1 to Length(Tekst) do
      if not InSet(Ord(Tekst[i]), ChSet) then Result := false;

   // Test if we have more than one dot or comma
   dotCount := 0;
   ChSet := MkSet(Ord('.'),Ord(','));
   for i := 1 to Length(Tekst) do
      if InSet(Ord(Tekst[i]), ChSet) then
         Inc(dotCount);

   if dotCount > 1 then Result := False;
end;

function CheckWithTolerance(X1, Y1, X2, Y2) : Boolean;
begin
    Result := False;
    if (Abs(X1 - X2) <= Tolerance) and (Abs(Y1 - Y2) <= Tolerance) then
        Result := True;
end;

function CheckObject(Prim1, Prim2 : IPCB_Primitive, X, Y : TCoord) : boolean;
begin
    Result := false;
    case Prim2.ObjectId of
    eTrackObject :
        if (Prim2.Layer = Prim1.Layer) then
            if CheckWithTolerance(Prim2.x1, Prim2.y1, X, Y) or CheckWithTolerance(Prim2.x2, Prim2.y2, X, Y) then
                 Result := True;

    eArcObject :
        if (Prim2.Layer = Prim1.Layer) then
            if CheckWithTolerance(Prim2.StartX, Prim2.StartY, X, Y) or CheckWithTolerance(Prim2.EndX, Prim2.EndY, X, Y) then
                Result := True;

    ePadObject :
        if ((Prim2.Layer = eMultiLayer) or (Prim2.Layer = Prim1.Layer)) and CheckWithTolerance(Prim2.x, Prim2.y, X, Y) then
            Result := True;

    eViaObject :
        if Prim2.IntersectLayer(Prim1.Layer) and CheckWithTolerance(Prim2.x, Prim2.y, X, Y) then
            Result := True;
    end;
end;

procedure AddMessage(MM   : IMessagesManager; MClass : WideString; MText   : WideString; MSource : WideString;
                     MDoc : WideString; MCBProcess   : WideString; MCBPara : WideString; ImageIndex : Integer);
var
   F           : Boolean;
begin
        MM.BeginUpdate;
        F := False;
        If MM = Nil Then Exit;
        MM.AddMessage({MessageClass             } MClass,
                      {MessageText              } MText,
                      {MessageSource            } MSource,
                      {MessageDocument          } MDoc,
                      {MessageCallBackProcess   } MCBProcess,
                      {MessageCallBackParameters} MCBPara,
                      ImageIndex,
                      F);
        MM.EndUpdate;
end;

procedure HighlightBadConnections(const dummy :boolean);
var
   BIter      : IPCB_BoardIterator;
   SIter      : IPCB_SpatialIterator;
   Prim1      : IPCB_Primitive;
   Prim2      : IPCB_Primitive;
   i          : Integer;
   X, Y       : TCoord;
   Found      : Boolean;
   TempString : String;
   bMechLayer : boolean;
   CLayer     : TLayer;
   LayerSet   : IPCB_LayerSet;
   dValue     : extended;
   MMessage   : WideString;
   MSource    : WideString;
   FPObjAddr  : TPCBObjectHandle;

begin
//    Units := Board.DisplayUnit;
    BOrigin := Point(Board.XOrigin, Board.YOrigin);
    MMPanel.ClearMessages;
    GetWorkSpace.DM_ShowMessageView;
    MSource := 'SelectBadConnections Project script';
    MMessage := 'Highlight Bad Connections script started';
    AddMessage(MMPanel,'[Info]',MMessage ,MSource , Board.FileName, '', '', BoardProject);


   TempString := EditTolerance.Text;
   if LastDelimiter(',.', TempString) = Length(TempString) then
      SetLength(TempString, Length(TempString - 1))
   else if LastDelimiter(',.', TempString) <> 0 then
      TempString[LastDelimiter(',.', TempString)] := DecimalSeparator;

   if Units = eMil then
   begin
      Tolerance := MilsToRealCoord(StrToFloat(TempString));
   end
   else
      Tolerance := MMsToRealCoord(StrToFloat(TempString));

   ResetParameters;
   AddStringParameter('Scope','All');
   RunProcess('PCB:DeSelect');

   CLayer := Board.CurrentLayer;
   bMechLayer := false;

   BIter := Board.BoardIterator_Create;
   BIter.AddFilter_ObjectSet(MkSet(eTrackObject, eArcObject));

   LayerSet := LayerSetUtils.EmptySet;
   if bCurrent then
       LayerSet.Include(CLayer);
   if bCopper then
       LayerSet.IncludeSignalLayers;
   if bMech then
       LayerSet.IncludeMechanicalLayers;
   if bCopper and bMech then
       Layerset.IncludeAllLayers;

   BIter.AddFilter_IPCB_LayerSet(LayerSet);
   Prim1  := BIter.FirstPCBObject;
   SIter  := Board.SpatialIterator_Create;

   While Prim1 <> nil do
   begin
      bMechLayer := LayerUtils.IsMechanicalLayer(Prim1.Layer);

      if Prim1.TearDrop or Prim1.InComponent then
          Found := true;
      if (not Prim1.InNet) and not bMechLayer then
         Found := true
      else if (Prim1.ObjectId = eArcObject) and (Prim1.StartAngle = 0) and (Prim1.EndAngle = 360) then
         Found := True
      else

      LayerSet := LayerSetUtils.EmptySet;
      LayerSet.Include(Prim1.Layer);
      if bMechLayer then
      begin
          SIter.AddFilter_ObjectSet(MkSet(eTrackObject, eArcObject));
      end else
      begin
          LayerSet.Include(eMultiLayer);
          SIter.AddFilter_ObjectSet(MkSet(eTrackObject, eArcObject, ePadObject, eViaObject));
      end;
      SIter.AddFilter_IPCB_LayerSet(LayerSet);

      for i := 1 to 2 do
      begin
         if i = 1 then
         begin
            if Prim1.ObjectId = eTrackObject then
            begin
               X := Prim1.x1;
               Y := Prim1.y1;
            end
            else
            begin
               X := Prim1.StartX;
               Y := Prim1.StartY;
            end;
         end
         else
         begin
            if Prim1.ObjectId = eTrackObject then
            begin
               X := Prim1.x2;
               Y := Prim1.y2;
            end
            else
            begin
               X := Prim1.EndX;
               Y := Prim1.EndY;
            end;
         end;

         Found := False;

         SIter.AddFilter_Area(X - Tolerance, Y - Tolerance, X + Tolerance, Y + Tolerance);
         Prim2 := SIter.FirstPCBObject;

         While (Prim2 <> nil) and not Found do
         begin
            if (Prim1.I_ObjectAddress <> Prim2.I_ObjectAddress) and not Prim2.TearDrop then
            begin
                if (not bMechLayer) and Prim2.InNet then
                if (Prim2.Net.Name = Prim1.Net.Name) then
                    Found := CheckObject(Prim1, Prim2, X, Y);
                if bMechLayer then
                    Found := CheckObject(Prim1, Prim2, X, Y);
            end;

            Prim2 := SIter.NextPCBObject;
         end;

         if not Found then
         begin
             FPObjAddr := Prim1.I_ObjectAddress;
             MMessage := Prim1.Descriptor + '  ' + CoordUnitToString((X-BOrigin.X),Units) + ' ' + CoordUnitToString((Y-BOrigin.Y), Units);
             AddMessage(MMPanel, '[warning]', MMessage , MSource, Board.FileName, 'PCB:CrossProbeNotify', 'Kind=Primitive|Handle='+ IntToStr(FPObjAddr), Marker_Warning);
             Prim1.Selected := True;
         end;
      end;  // for i

      Prim1 := BIter.NextPCBObject;
   end;
   Board.SpatialIterator_Destroy(SIter);
   Board.BoardIterator_Destroy(BIter);
end;

procedure SetFiltermask(dummy : boolean);
begin
   Board.SetState_ViewManager_FilterChanging;
//   Client.SendMessage('PCB:RunQuery','Apply=True|Expr=IsSelected|Select=False|Mask=True', Length('Apply=True|Expr=IsSelected|Select=True|Mask=True'), Client.CurrentView);
   Client.PostMessage('PCB:RunQuery','Apply=True|Expr=IsSelected|Select=False|Mask=True', Length('Apply=True|Expr=IsSelected|Select=True|Mask=True'), Client.CurrentView);
end;

Procedure Start;
begin
// form create event has already happened!
   Board := PCBServer.GetCurrentPCBBoard;
   if Board = nil then exit;
   MMPanel := GetWorkSpace.DM_MessagesManager;
   FormSelectBadConnections.Show; //  .ShowModal;
end;

{..............................................................................}
procedure TFormSelectBadConnections.ButtonOKClick(Sender: TObject);
begin
//    FormSelectBadConnections.Hide;
    HighlightBadConnections(true);
//    FormSelectBadConnections.Show;
end;

procedure TFormSelectBadConnections.ButtonCancelClick(Sender: TObject);
begin
   FormSelectBadConnections.Close;
   SetFilterMask(true);
   exit;
end;

procedure TFormSelectBadConnections.EditToleranceChange(Sender: TObject);
begin
   if not IsStringANum(EditTolerance.Text) then
   begin
      ButtonOK.Enabled := False;
      EditTolerance.Font.Color := clRed;
   end else
   begin
      EditTolerance.Font.Color := clWindowText;
      ButtonOK.Enabled := True;
   end;
end;

procedure TFormSelectBadConnections.RadioGroupUnitsClick(Sender: TObject);
begin
    Units := eMil;
    if RadioGroupUnits.ItemIndex = 1 then Units := eMM;
end;

procedure CheckCurrentCheckBox(const dummy : boolean);
begin
    if not (bCopper or bMech) then bCurrent := true;
    if (bCurrent) then CheckBoxCurrent.State := cbChecked
    else CheckBoxCurrent.State := cbUnchecked;
end;

procedure TFormSelectBadConnections.CheckBoxCopperClick(Sender: TObject);
begin
    if CheckBoxCopper.State = cbChecked then bCopper := true
    else bCopper := false;
    CheckCurrentCheckBox(true);
end;

procedure TFormSelectBadConnections.CheckBoxMechClick(Sender: TObject);
begin
    if CheckBoxMech.State = cbChecked then bMech := true
    else bMech := false;
    CheckCurrentCheckBox(true);
end;

procedure TFormSelectBadConnections.CheckBoxCurrentClick(Sender: TObject);
begin
    if CheckBoxCurrent.State = cbChecked then bCurrent := true
    else bCurrent := false;
    CheckCurrentCheckBox(true);
end;

// this event is called immediately script starts NOT when form is shown.
procedure TFormSelectBadConnections.FormSelectBadConnectionsCreate(Sender: TObject);
begin
    bCopper  := true;          // set initial defaults.
    bMech    := false;
    bCurrent := true;
    Units := eMil;

    if (Units = eMil) then RadioGroupUnits.ItemIndex(0)
    else RadioGroupUnits.ItemIndex(1);

    if (bCopper) then CheckBoxCopper.State := cbChecked
    else CheckBoxCopper.State := cbUnchecked;

    if (bMech) then CheckBoxMech.State := cbChecked
    else CheckBoxMech.State := cbUnchecked;

    if (bCurrent) then CheckBoxCurrent.State := cbChecked
    else CheckBoxCurrent.State := cbUnchecked;
end;

procedure TFormSelectBadConnections.ClearMMPanelClick(Sender: TObject);
begin
   MMPanel.ClearMessages; // ForDocument(Board.FileName);
end;

