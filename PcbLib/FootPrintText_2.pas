{ AddFootPrintText_2.pas

 PcbLib
 
 Add string/text to PCBLib footprints
 Could be extended to support PCB.

 Warning:
 using copper layers NOT ALREADY in target PCB stack could have very BAD consequences.
 Need to save library before direct placement is working 100% (first FP is wrong).

tbd
 check for pre-existing string; but what criteria?.
 Find bottom left line/track on specific layer
 Add text in cnr, scale to fit if required

Author BLM
 from AddFootPrintText with forms nonsense ripped out
30/05/2020  v0.10  POC works

...................................................................................}
const
    bMechLayer = true;            // Mechancial Layers if false then copper 1 - 32
// if bMechLayer then iLayerNum is mechlayer number from 1 to 1024
//               else iLayerNum is copper layer num 1 to 32
    iLayerNum  = 13;             //  layer integer index number;
    sNewText   = '.Designator';

Procedure AddFootPrintText;   // to run directly..
Var
    CurrentLib        : IPCB_Library;
    Board             : IPCB_Board;
    FootprintIterator : IPCB_LibraryIterator;
//    Iterator          : IPCB_GroupIterator;
    Footprint         : IPCB_Component;
    TextObj           : IPCB_Text;

    Layer             : TLayer;
    Box               : TCoordRect;

    Rpt               : TStringList;
    FileName          : TPCBString;
    Document          : IServerDocument;

Begin
    Board := PCBServer.GetCurrentPCBBoard;
    CurrentLib := PCBServer.GetCurrentPCBLibrary;
    If CurrentLib = Nil Then
    Begin
        ShowMessage('This is not a PCB Library document');
        Exit;
    End;

    Layer := iLayerNum;
    if bMechLayer then
        Layer := LayerUtils.MechanicalLayer(iLayerNum);

    Board := CurrentLib.Board;
    Board.LayerIsDisplayed[Layer] := True;
    Board.CurrentLayer := Layer;                // change current layer
    Board.ViewManager_UpdateLayerTabs;          // make GUI match the current layer.
// does not work in library!
//    Client.SendMessage('PCB:SetCurrentLayer', 'Layer=' + IntToStr(Layer) , 255, Client.CurrentView);
    CurrentLib.RefreshView;

    FootprintIterator := CurrentLib.LibraryIterator_Create;
    FootprintIterator.SetState_FilterAll;
    FootprintIterator.AddFilter_LayerSet(AllLayers);

    Filename := ExtractFilePath(Board.FileName) + 'PcbLib_AddFPText.txt';
    Rpt := TStringList.Create;
    Rpt.Add(ExtractFileName(Board.FileName));
    Rpt.Add('Layer : ' + Board.LayerName(Layer));
    Rpt.Add('');
    //Rpt.Add('Current Footprint : ' + CurrentLib.CurrentComponent.Name);

    // A footprint is a IPCB_LibComponent inherited from
    Footprint := FootprintIterator.FirstPCBObject;
    While Footprint <> Nil Do
    Begin
        Board := CurrentLib.Board;
    //  one of the next 3 or 4 lines seems to fix the erronous bounding rect of the alphabetic first item in Lib list
    //  suspect it changes the Pad.Desc text as well
        CurrentLib.SetState_CurrentComponent (Footprint);
        Board.ViewManager_FullUpdate;                // makes a slideshow
        Board.GraphicalView_ZoomRedraw;

       Rpt.Add('Current Footprint : ' + Footprint.Name);

       Box := Footprint.BoundingRectangle;
           //   RectToCoordRect(Footprint.BoundingRectangleNoNameComment);  // PCB only

      // CoordUnitToString(Footprint.Height, eImperial) = '0mil'
      // StringToCoordUnit(GeometryHeight, NewHeight, eImperial);

        PCBServer.PreProcess;
        TextObj := PCBServer.PCBObjectFactory(eTextObject, eNoDimension, eCreate_Default);

        TextObj.XLocation := Board.XOrigin + MilsToCoord(-10);
        TextObj.YLocation := Board.YOrigin + MilsToCoord(-10);
        TextObj.Layer     := Layer;
        TextObj.UnderlyingString  := sNewText;
        TextObj.Size      := MilsToCoord(11);   // sets the height of the text.
        TextObj.Width     := MilsToCoord(1);;

        Board.AddPCBObject(TextObj);           // each board is the FP in library
//        Footprint.AddPCBObject(TextObj);     // only for use in PCB

        PCBServer.SendMessageToRobots(Footprint.I_ObjectAddress,c_Broadcast,PCBM_BoardRegisteration,TextObj.I_ObjectAddress);
// using below ONLY results in odd placement behaviour: first placed FP has NO extra text ??
// if you don't save the library BEFORE placing FP the first placed FP has NO text
        PCBServer.SendMessageToRobots(Board.I_ObjectAddress,c_Broadcast,PCBM_BoardRegisteration,TextObj.I_ObjectAddress);

        PCBServer.PostProcess;

        if TextObj.IsHidden then
            Board.ShowPCBObject(TextObj);
        Rpt.Add('');

        Footprint := FootprintIterator.NextPCBObject;
    End;

    CurrentLib.LibraryIterator_Destroy(FootprintIterator);

    CurrentLib.Navigate_FirstComponent;
    CurrentLib.Board.GraphicalView_ZoomRedraw;
    CurrentLib.RefreshView;

    Rpt.SaveToFile(Filename);
    Rpt.Free;
    Document  := Client.OpenDocument('Text', FileName);
    If Document <> Nil Then
    begin
        Client.ShowDocument(Document);
        if (Document.GetIsShown <> 0 ) then
            Document.DoFileLoad;
    end;
End;
{..............................................................................}

