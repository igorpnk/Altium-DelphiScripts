{.................................................................................
 Summary   Used to test LayerClass methods in AD17-19 & report into text file.
           Works on PcbDoc & PcbLib files.
           Mechanical layer Names, Colours and MechanicalPairs can be
           exported to text file

  From script by:    Petar Perisin
  url: https://github.com/Altium-Designer-addons/scripts-libraries/tree/master/MechLayerNames

  Modified by: B Miller

 v 0.22 
 03/07/2017  :  mod to fix layer names output, why was import okay ??
 23/02/2018  :  added MechLayer Pairs & colours
 27/02/2018  :  MechPair detect logic; only remove existing if any MPs detected in file
 16/06/2019  :  Test for AD19 etc.
 01/07/2019  :  messed with MechPair DNW; added MinMax MechLayer constants to report
 08/09/2019  : use _V7 layerstack for mech layer info.
 11/09/2019  : use & report the LayerIDs & iterate to 64 mech layers.
 28/09/2019  : Added colour & display status to layerclass outputs

         tbd :  Use Layer Classes test in AD17 & AD19

Note: can export 1 to 64 mech layers in AD17/18/19

..................................................................................}

{.................................................................................}
var
    PCBSysOpts : IPCB_SystemOptions;
    Board      : IPCB_Board;
    LayerStack : IPCB_LayerStack;
    LayerObj   : IPCB_LayerObject;
    LayerClass : TLayerClassID;
    MechLayer  : IPCB_MechanicalLayer;
    MechPairs  : IPCB_MechanicalLayerPairs;
    MechPair   : TMechanicalLayerPair;
    Layer      : TLayer;
    Layer7     : TV7_Layer;
    ML1, ML2   : integer;

function LayerClassName (LClass : TLayerClassID) : WideString;
begin
//Type: TLayerClassID
    case LClass of
    eLayerClass_All           : Result := 'All';
    eLayerClass_Mechanical    : Result := 'Mechanical';
    eLayerClass_Physical      : Result := 'Physical';
    eLayerClass_Electrical    : Result := 'Electrical';
    eLayerClass_Dielectric    : Result := 'Dielectric';
    eLayerClass_Signal        : Result := 'Signal';
    eLayerClass_InternalPlane : Result := 'Internal Plane';
    eLayerClass_SolderMask    : Result := 'Solder Mask';
    eLayerClass_Overlay       : Result := 'Overlay';
    eLayerClass_PasteMask     : Result := 'Paste mask';
    else                        Result := 'Unknown';
    end;
end;

Procedure ExportMechLayerInfoTest;
var
   WS          : IWorkspace;
   // LayStack_V7 : IPCB_LayerStack_V7;
   // LayObj_V7   : IPCB_LayerObject_V7;
   i, j        : Integer;
   SaveDialog  : TSaveDialog;
   Flag        : Integer;
   FileName    : String;
   INIFile     : TIniFile;
   TempS       : TStringList;
   temp        : integer;
   LayerName   : WideString;
   LayerPos    : WideString;
   Layer       : integer;
   LColour     : WideString;
   LName       : WideString;
   IsDisplayed : boolean;

begin
    Board := PCBServer.GetCurrentPCBBoard;
    if Board = nil then exit;

    PCBSysOpts := PCBServer.SystemOptions;
    If PCBSysOpts = Nil Then exit;

    WS := GetWorkSpace;
    FileName := WS.DM_FocusedDocument.DM_FullPath;
    FileName := ExtractFilePath(FileName);

    TempS := TStringList.Create;

    TempS.Add(Client.GetProductVersion);
    TempS.Add('');
    TempS.Add(' ----- LayerStack(eLayerClass) ------');

    LayerStack := Board.LayerStack;


// LayerClass methods    Mechanical is strangely absent/empty.

    for LayerClass := eLayerClass_All to eLayerClass_PasteMask do
    begin
        TempS.Add('');
        TempS.Add('eLayerClass ' + IntToStr(LayerClass) + '  ' + LayerClassName(LayerClass));
        TempS.Add('lc.i : |   name           short name           IsDisplayed?   Colour');
        i := 1;
        LayerObj := LayerStack.First(LayerClass);

        While (LayerObj <> Nil ) do
        begin
            if LayerClass <> eLayerClass_Mechanical then
                Layer := LayerObj.V6_LayerID             //  V7_LayerID;
            else
                Layer :=  LayerUtils.MechanicalLayer(i);

            LayerObj.IsInLayerStack;

            LayerPos :='';
            if LayerClass = eLayerClass_Electrical then
               LayerPos := IntToStr(Board.LayerPositionInSet(AllLayers, LayerObj));       // think this only applies to eLayerClass_Electrical

            LName := LayerObj.GetState_LayerDisplayName(eLayerNameDisplay_Short) ; // TLayernameDisplayMode: eLayerNameDisplay_Long/Short/Medium
            IsDisplayed := Board.LayerIsDisplayed(Layer);
           // ColorToString(Board.L .LayerColor(Layer]));   // TV6_Layer
            LColour := ColorToString(PCBSysOpts.LayerColors(Layer));

            TempS.Add(Padright(IntToStr(LayerClass) + '.' + IntToStr(i),4) + ' | ' + Padright(LayerPos,3) + ' ' + PadRight(LayerObj.Name, 15)
                      + PadRight(LName, 20) + '  ' + PadRight(BoolToStr(IsDisplayed,true), 6) + '  ' + LColour);

//       if LayerObj <> Nil then MechLayer := LayerObj;
            LayerObj := LayerStack.Next(Layerclass, LayerObj);
            Inc(i);
        end;
    end;

    TempS.Add('');
    TempS.Add('');

    TempS.Add('API Layers constants: (all obsolute)');
    TempS.Add('MaxRouteLayer = ' +  IntToStr(MaxRouteLayer) +' |  MaxBoardLayer = ' + IntToStr(MaxBoardLayer) );
    TempS.Add(' MinLayer = ' + IntToStr(MinLayer) + '   | MaxLayer = ' + IntToStr(MaxLayer) );
    TempS.Add(' MinMechanicalLayer = ' + IntToStr(MinMechanicalLayer) + '  | MaxMechanicalLayer =' + IntToStr(MaxMechanicalLayer) );
    TempS.Add('');
    TempS.Add(' ----- .LayerObject(index) Mechanical ------');
    TempS.Add('');


// Old? Methods for Mechanical Layers.

    LayerStack := Board.LayerStack_V7;
    TempS.Add('Idx LayerID    boardlayername      layername           V6_LayerID');
    for i := 1 to 64 do
    begin
        ML1 := LayerUtils.MechanicalLayer(i);
        Layer := i + MinMechanicalLayer - 1;        // just calcs same as above until eMech16.
        LayerObj := LayerStack.LayerObject_V7[ML1];
        LayerName := 'broken method NO name';
        if LayerObj <> Nil then                     // 2 different indices for the same object info, Fg Madness!!!
        begin
            LayerName := LayerObj.Name;
            Layer7 := LayerObj.V7_LayerID;      // needs wrapper function  __TV7_Layer_Wrapper() how to use?

      //  ('MechLayer' + IntToStr(i), 'Enabled', MechLayer.MechanicalLayerEnabled);
      //  ('MechLayer' + IntToStr(i), 'Show',    MechLayer.IsDisplayed[Board]);
      //  ('MechLayer' + IntToStr(i), 'Sheet',   MechLayer.LinkToSheet);
      //  ('MechLayer' + IntToStr(i), 'SLM',     MechLayer.DisplayInSingleLayerMode);
      //  ('MechLayer' + IntToStr(i), 'Color',   ColorToString(Board.LayerColor[ML1]) );

        end;
        TempS.Add(PadRight(IntToStr(i),3) + ' ' + PadRight(IntToStr(ML1),10) + ' ' + PadRight(Board.LayerName(ML1),20) + ' ' + PadRight(LayerName,20) + ' ' + IntToStr(LayerObj.V6_LayerID));
        // LayerObj.UsedByPrims;
    end;


{ LayerPair[I : Integer] property defines indexed layer pairs and returns a TMechanicalLayerPair record of two PCB layers.
  TMechanicalLayerPair = Record
    Layer1 : TLayer;
    Layer2 : TLayer;
  End;
}
    TempS.Add('');
    TempS.Add('');
    TempS.Add(' ----- MechLayerPairs Legacy 1 to 32/64 ?? -----');
    TempS.Add('');

    MechPairs := Board.MechanicalPairs;

    TempS.Add('Mech Layer Pair Count : ' + IntToStr(MechPairs.Count));
    TempS.Add('');

    for j := 0 to (MechPairs.Count - 1) do
    begin
        MechPair := MechPairs.LayerPair[j];
        if MechPair <> Nil then
        begin
 //  broken because no wrapper function to handle TMechanicalLayerPair record.
{
TMechanicalLayerPair = Record
Layer1 : TLayer;
Layer2 : TLayer;
End;
}
//            Layer := MechPair ;   //  .Layer1;              // does NOT work
//            MechPair(Layer1);
//            Layer := MechPair.GetTypeInfoCount(0);         // __TMechanicalLayerPair__Wrapper()

//     FFS !! why is MechPair Layer properties not the same/similar to DrillPairs.

//            IniFile.WriteString('MechLayer' + IntToStr(MechPair[0]), 'Pair',    Board.LayerName(MechPair[0]) );
//            IniFile.WriteString('MechLayer' + IntToStr(MechPair[1]), 'Pair',    Board.LayerName(MechPair[1]) );
        end;
    end;


// working mickey mouse soln

    TempS.Add('MechLayer Pairs:     LayerName1 - LayerName2 ');

    for i := 1 to 64 do
//  for Layer := MinMechanicalLayer to MaxMechanicalLayer do
    begin
        ML1 := LayerUtils.MechanicalLayer(i);
        Layer := i + MinMechanicalLayer - 1;
        MechLayer := LayerStack.LayerObject_V7[ML1];

//        MechLayer := LayerStack.LayerObject[Layer];      // this method does not work above eMech24 !!

//        if MechPairs.LayerUsed(Layer) then         // always false ! ; pass it (MechLayer) & will crash!
//        begin

            for j := (i + 1) to 64 do
            begin
                ML2 := LayerUtils.MechanicalLayer(j);
                if MechPairs.PairDefined(ML1, ML2) then
                    TempS.Add(PadRight(IntToStr(i),3) + '-' + PadLeft(IntToStr(j),3) + '                 ' + Board.LayerName(ML1) + ' - ' + Board.LayerName(ML2) );
            end;
    end;

    WS := GetWorkSpace;
    FileName := WS.DM_FocusedDocument.DM_FullPath;
    FileName := ExtractFilePath(FileName) + '\mechlayername.txt';

    TempS.SaveToFile(FileName);
    Exit;

end;

{
// Use of LayerObject method to display specific layers
    Var
       Board      : IPCB_Board;
       Stack      : IPCB_LayerStack;
       LyrObj     : IPCB_LayerObject;
       Layer        : TLayer;

    Begin
       Board := PCBServer.GetCurrentPCBBoard;
       Stack := Board.LayerStack;
       for Lyr := eMechanical1 to eMechanical16 do
       begin
          LyrObj := Stack.LayerObject[Lyr];
          If LyrObj.MechanicalLayerEnabled then ShowInfo(LyrObj.Name);
       end;
    End;
}
{ //copper layers     below is for drill pairs need to get top & bottom copper.
     LowLayerObj  : IPCB_LayerObject;
     HighLayerObj : IPCB_LayerObject;
     LowPos       : Integer;
     HighPos      : Integer;
     LowLayerObj  := PCBBoard.LayerStack.LayerObject[PCBLayerPair.LowLayer];
     HighLayerObj := PCBBoard.LayerStack.LayerObject[PCBLayerPair.HighLayer];
     LowPos       := PCBBoard.LayerPositionInSet(SignalLayers, LowLayerObj);
     HighPos      := PCBBoard.LayerPositionInSet(SignalLayers, HighLayerObj);
}
{   TheLayerStack := PCBBoard.LayerStack_V7;
    If TheLayerStack = Nil Then Exit;
    LS       := '';
    LayerObj := TheLayerStack.FirstLayer;
    Repeat
        LS       := LS + Layer2String(LayerObj.LayerID) + #13#10;
        LayerObj := TheLayerStack.NextLayer(LayerObj);
    Until LayerObj = Nil;
}

{  // better to use later method ??
   Stack      : IPCB_LayerStack;
   Lyr        : TLayer;
   for Lyr := eTopLayer to eBottomLayer do
   for Lyr := eMechanical1 to eMechanical16 do  // but eMechanical17 - eMechanical32 are NOT defined ffs.
       LyrObj := Stack.LayerObject[Lyr];
}

{
Function  LayerPositionInSet(ALayerSet : TLayerSet; ALayerObj : IPCB_LayerObject)  : Integer;
 ex. where do layer consts come from??            VV             VV
      LowPos  := PCBBoard.LayerPositionInSet( SignalLayers + InternalPlanes, LowLayerObj);
      HighPos := PCBBoard.LayerPositionInSet( SignalLayers + InternalPlanes, HighLayerObj);
}
